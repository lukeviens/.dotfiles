# >>> Tmux passthrough support <<<
if [ -n "$TMUX" ]; then
  # ensure tmux allows escape sequences to pass through
  printf '\033Ptmux;\033\033]7;file://%s%s\033\\\033\\' "$(hostname)" "$PWD"
fi

export K9S_CONFIG_DIR="$HOME/.config/k9s"

### prompt bar

# colours (from shared theme)
source "$HOME/.config/theme/colors"

# vcs info
autoload -Uz vcs_info
precmd() { vcs_info }

# only show git branch
zstyle ':vcs_info:git:*' formats '%b'

# allow var substitution in prompt
setopt PROMPT_SUBST

# prompt
PROMPT='%F{$active}${vcs_info_msg_0_}%f %n@%m %1~ %# '

export PATH="/opt/homebrew/bin:$PATH"

# zoxide (smart directory jumping — also powers sesh's dir results)
eval "$(zoxide init zsh)"
