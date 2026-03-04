#!/usr/bin/env bash
set -euo pipefail

SRC="$HOME/.config/zsh/.zshrc"
DST="$HOME/.zshrc}"

# ensure source exists
[ -f "$SRC" ] || { echo "ERROR: missing source: $SRC"; exit 1; }

# ensure target exists
if [ ! -f "$DST" ]; then
  echo "creating target: $DST"
  mkdir -p "${DST%/*}"
  touch "$DST"
fi

# source the config file~
grep -qxF "source $SRC" "$DST" \
  || printf "source %s" "$SRC" >> "$DST"

echo "sourced $SRC in $DST!"

