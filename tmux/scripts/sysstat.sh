#!/bin/sh
# Start (or restart) the background sysstat collector for the tmux status bar.
# Invoked once from tmux.conf. Safe to run repeatedly — it replaces any
# existing collector so a `tmux source-file` reload doesn't stack daemons.

DIR="$(cd "$(dirname "$0")" && pwd)"
COLLECTOR="$DIR/sysstat-collector.sh"
CACHE="/tmp/tmux-sysstat.txt"
PIDFILE="/tmp/tmux-sysstat.pid"

# Pull colours from the already-loaded theme (@color_* set in tmux.conf).
C_ACCENT="$(tmux show -gv @color_accent 2>/dev/null)"
C_FG="$(tmux show -gv @color_fg 2>/dev/null)"
C_SUBTLE="$(tmux show -gv @color_subtle 2>/dev/null)"

# Primary network interface (default route) + disk device.
NET_IFACE="$(route get default 2>/dev/null | awk '/interface:/{print $2}')"
[ -z "$NET_IFACE" ] && NET_IFACE="en0"
DISK_DEV="disk0"

# Stop the previous collector (by recorded PID, so we never match unrelated
# processes) before starting a fresh one detached.
if [ -f "$PIDFILE" ]; then
	oldpid="$(cat "$PIDFILE" 2>/dev/null)"
	case "$oldpid" in
		*[!0-9]* | "") ;;                       # ignore garbage
		*) kill "$oldpid" 2>/dev/null ;;
	esac
fi

SYSSTAT_CACHE="$CACHE" \
C_ACCENT="$C_ACCENT" C_FG="$C_FG" C_SUBTLE="$C_SUBTLE" \
NET_IFACE="$NET_IFACE" DISK_DEV="$DISK_DEV" \
	nohup sh "$COLLECTOR" >/dev/null 2>&1 &
echo $! > "$PIDFILE"

# Seed the cache so the bar has something to show before the first sample.
[ -f "$CACHE" ] || printf '#[fg=%s]CPU #[fg=%s]…' "$C_ACCENT" "$C_FG" > "$CACHE"
