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
precmd() { vcs_info; source "$HOME/.config/theme/colors" 2>/dev/null }

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
PROMPT='%F{$active}${vcs_info_msg_0_}%f %F{$subtle}%n@%m%f %F{$fg}%1~%f %F{$active}%#%f '

export PATH="/opt/homebrew/bin:$PATH"

# zoxide (smart directory jumping — also powers sesh's dir results)
eval "$(zoxide init zsh)"
