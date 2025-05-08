#!/bin/bash
# Simplified session jump list for tmux

set -euo pipefail

TMUX_DIR="${HOME}/.config/tmux"
mkdir -p "$TMUX_DIR"

HISTORY_FILE="${TMUX_DIR}/session_history"
CURRENT_POS_FILE="${TMUX_DIR}/session_current_pos"

ACTION="${1:-}"
SESSION="${2:-}"

touch "$HISTORY_FILE"
[[ -f "$CURRENT_POS_FILE" ]] || echo 0 > "$CURRENT_POS_FILE"

SESSIONS=()
while IFS= read -r line; do
  SESSIONS+=("$line")
done < "$HISTORY_FILE"

CURRENT_POS=$(<"$CURRENT_POS_FILE")
HISTORY_SIZE="${#SESSIONS[@]}"

save_pos() {
  echo "$CURRENT_POS" > "$CURRENT_POS_FILE"
}

switch_to_session() {
  local target="$1"
  tmux switch-client -t "$target" 2>/dev/null || echo "Session '$target' no longer exists"
}

case "$ACTION" in
  backward)
    if (( CURRENT_POS > 0 )); then
      (( CURRENT_POS-- ))
      save_pos
      switch_to_session "${SESSIONS[CURRENT_POS]}"
    fi
    ;;
  forward)
    if (( CURRENT_POS < HISTORY_SIZE - 1 )); then
      (( CURRENT_POS++ ))
      save_pos
      switch_to_session "${SESSIONS[CURRENT_POS]}"
    fi
    ;;
  record)
    # Don't record if it's the same as the current session
    if [[ "${SESSIONS[CURRENT_POS]:-}" == "$SESSION" ]]; then
      exit 0
    fi

    # Truncate any "forward" history
    SESSIONS=( "${SESSIONS[@]:0:$((CURRENT_POS + 1))}" )
    SESSIONS+=( "$SESSION" )

    printf "%s\n" "${SESSIONS[@]}" > "$HISTORY_FILE"
    CURRENT_POS="${#SESSIONS[@]}"
    (( CURRENT_POS-- ))
    save_pos
    ;;
  *)
    echo "Usage: $0 {forward|backward|record SESSION_NAME}"
    exit 1
    ;;
esac

