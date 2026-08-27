#!/usr/bin/env sh
# telescope-style session finder for tmux (prefix + f) with vim-style modal nav.
# lists sesh.toml sessions + live tmux sessions + zoxide dirs, fuzzy-picks, connects.
#
# modes (fzf has no native modes; emulated via rebind/unbind):
#   starts in INSERT — just type to fuzzy-search
#   esc      -> NORMAL mode (j/k move, g/G top/bottom)
#   i / a    -> back to INSERT mode
#   enter    -> select    q -> quit    ctrl-c -> quit (always)
export PATH="/opt/homebrew/bin:$PATH"

# keys that toggle between typeable (insert) and nav commands (normal)
keys="i,a,j,k,h,l,g,G,q"

selected="$(
  sesh list --icons --hide-duplicates | fzf \
    --ansi \
    --reverse \
    --border \
    --no-sort \
    --cycle \
    --header 'INSERT: type to search  ·  esc: normal  ·  j/k: move  ·  enter: go  ·  q: quit' \
    --bind "start:unbind($keys)+change-prompt(  INSERT  )" \
    --bind "esc:rebind($keys)+change-prompt(  NORMAL  )" \
    --bind "i:unbind($keys)+change-prompt(  INSERT  )" \
    --bind "a:unbind($keys)+change-prompt(  INSERT  )" \
    --bind "j:down" \
    --bind "k:up" \
    --bind "h:ignore" \
    --bind "l:ignore" \
    --bind "g:first" \
    --bind "G:last" \
    --bind "q:abort"
)"

[ -n "$selected" ] && exec sesh connect "$selected"
