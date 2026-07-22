#!/bin/sh
# Background system-stats collector for the tmux status bar.
# Samples CPU / MEM / network / disk I/O every ~2s and writes a single
# pre-coloured line to a cache file. tmux just `cat`s that file, so the
# status bar never blocks on a slow command (top, netstat, etc).
#
# Colours + primary network interface are passed in via env by sysstat.sh:
#   C_ACCENT, C_FG, C_SUBTLE  (tmux #[...] hex colours)
#   NET_IFACE                 (e.g. en0)  DISK_DEV (e.g. disk0)
# Falls back to sane defaults if unset.

CACHE="${SYSSTAT_CACHE:-/tmp/tmux-sysstat.txt}"
IFACE="${NET_IFACE:-en0}"
DISK="${DISK_DEV:-disk0}"
ACCENT="${C_ACCENT:-#66d9ef}"
FG="${C_FG:-#f8f8f2}"
SUBTLE="${C_SUBTLE:-#878787}"
INTERVAL="${SYSSTAT_INTERVAL:-2}"

# Humanise a bytes-per-second figure into B/K/M/G.
human() {
	awk -v b="$1" 'BEGIN{
		if (b < 0) b = 0
		if (b < 1024)          printf "%dB",   b
		else if (b < 1048576)  printf "%dK",   b/1024
		else if (b < 1073741824) printf "%.1fM", b/1048576
		else                   printf "%.1fG", b/1073741824
	}'
}

# Cumulative network bytes (in, out) for the primary interface.
net_bytes() {
	netstat -ibn 2>/dev/null | awk -v i="$IFACE" '$1==i && /Link/ {print $7, $10; exit}'
}

# Cumulative disk bytes transferred (read+write combined) for the device.
disk_bytes() {
	# iostat -I gives since-boot totals; MB is the last column.
	iostat -Id "$DISK" 2>/dev/null | awk 'END{printf "%.0f", $NF * 1048576}'
}

prev_rx=""; prev_tx=""; prev_disk=""; prev_t=""

while :; do
	now=$(date +%s)

	set -- $(net_bytes)
	rx="${1:-0}"; tx="${2:-0}"
	disk=$(disk_bytes)

	# CPU: top -l 2 -n 0 prints the CPU line twice, 1s apart; the second is
	# a real delta (the first is since-boot and misleading). This blocks ~1s
	# but we're in the background so the bar never waits on it.
	cpu=$(top -l 2 -n 0 2>/dev/null | awk '/CPU usage/{u=$3; s=$5} END{gsub(/%/,"",u); gsub(/%/,"",s); printf "%.0f", u+s}')
	[ -z "$cpu" ] && cpu=0

	# MEM used% from vm_stat: (active + wired + compressor-occupied) / total.
	# Mirrors Activity Monitor's "Memory Used" far better than free-percentage.
	mem=$(vm_stat 2>/dev/null | awk '
		/page size of/ {ps=$8}
		/Pages active/ {a=$3}
		/Pages wired/  {w=$4}
		/occupied by compressor/ {c=$5}
		END{
			gsub(/\./,"",a); gsub(/\./,"",w); gsub(/\./,"",c)
			used=(a+w+c)*ps
			"sysctl -n hw.memsize" | getline total
			if (total>0) printf "%.0f", used/total*100; else printf "0"
		}')
	[ -z "$mem" ] && mem=0

	# Rates (need a previous sample + elapsed time).
	if [ -n "$prev_t" ]; then
		dt=$((now - prev_t)); [ "$dt" -lt 1 ] && dt=1
		rx_r=$(human $(( (rx   - prev_rx)   / dt )))
		tx_r=$(human $(( (tx   - prev_tx)   / dt )))
		dk_r=$(human $(( (disk - prev_disk) / dt )))
	else
		rx_r="-"; tx_r="-"; dk_r="-"
	fi

	# Single '%' on purpose: text substituted in via #() is NOT re-run through
	# tmux's strftime pass, so it must not be doubled (unlike literals in the
	# status-right template itself).
	line="#[fg=${ACCENT}]CPU #[fg=${FG}]${cpu}%\
 #[fg=${ACCENT}]MEM #[fg=${FG}]${mem}%\
 #[fg=${SUBTLE}]│\
 #[fg=${ACCENT}]NET #[fg=${FG}]↓${rx_r} ↑${tx_r}\
 #[fg=${SUBTLE}]│\
 #[fg=${ACCENT}]DIO #[fg=${FG}]${dk_r} "

	tmp="${CACHE}.tmp"
	printf '%s' "$line" > "$tmp" && mv -f "$tmp" "$CACHE"

	prev_rx="$rx"; prev_tx="$tx"; prev_disk="$disk"; prev_t="$now"
	sleep "$INTERVAL"
done
