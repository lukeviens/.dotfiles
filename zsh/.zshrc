# >>> Tmux passthrough support <<<
if [ -n "$TMUX" ]; then
  # ensure tmux allows escape sequences to pass through
  printf '\033Ptmux;\033\033]7;file://%s%s\033\\\033\\' "$(hostname)" "$PWD"
fi

export K9S_CONFIG_DIR="$HOME/.config/k9s"

### prompt bar

# colours (from shared theme)
source "$HOME/.config/theme/colors"

# vcs info + re-read the shared palette each prompt, so the prompt follows Caps-t live
autoload -Uz vcs_info
precmd() { vcs_info; source "$HOME/.config/theme/colors" 2>/dev/null; ZVM_VI_HIGHLIGHT_BACKGROUND=$subtle }

# reactive prompt: register this shell so town can SIGUSR1 it the INSTANT the theme changes
# (hammerspoon's theme listener signals every registered pid). The trap re-reads the palette and
# redraws the current prompt — no waiting for the next prompt. Deregister on exit.
_town_shells="$HOME/.cache/town/shells"
mkdir -p "$_town_shells" && : > "$_town_shells/$$"
TRAPUSR1() { source "$HOME/.config/theme/colors" 2>/dev/null; zle reset-prompt 2>/dev/null }
zshexit() { rm -f "$_town_shells/$$" }

# only show git branch
zstyle ':vcs_info:git:*' formats '%b'

# allow var substitution in prompt
setopt PROMPT_SUBST

# prompt
PROMPT='%F{$active}${vcs_info_msg_0_}%f %F{$subtle}%n@%m%f %F{$fg}%1~%f %F{$_town_mode}%#%f '

export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"   # gopls, stylua, gofumpt, etc. — usable from any shell, not just nvim

# zoxide (smart directory jumping — also powers sesh's dir results)
eval "$(zoxide init zsh)"

### modal editing
# Three texts, three owners: zsh the line, tmux the scrollback, vim the file. Escape means one
# thing in all three — stop typing, start pointing. Only zsh knows which you mean, because only
# zsh knows if you have typed anything: empty line → the scrollback, so hand it to tmux.

ZVM_LINE_INIT_MODE=$ZVM_MODE_INSERT        # a fresh prompt is always ready to type
ZVM_VI_HIGHLIGHT_BACKGROUND=$subtle        # visual selection, in the shared palette
source /opt/homebrew/opt/zsh-vi-mode/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh

function _town_read() {
  if [ -z "$BUFFER" ] && [ -n "$TMUX" ]; then tmux copy-mode
  else zvm_select_vi_mode $ZVM_MODE_NORMAL; fi
}
zvm_define_widget _town_read

# zvm defers bindkeys until after its own init; ours has to wait too or it is overwritten.
function zvm_after_init() { zvm_bindkey viins '^[' _town_read }

# the prompt character carries the mode, so nothing moves when it changes. zvm's cursor says it too.
_town_mode=$active
function zvm_after_select_vi_mode() {
  case $ZVM_MODE in
    $ZVM_MODE_NORMAL) _town_mode=$accent ;;
    $ZVM_MODE_VISUAL|$ZVM_MODE_VISUAL_LINE) _town_mode=$subtle ;;
    *) _town_mode=$active ;;
  esac
  zle reset-prompt 2>/dev/null
}
