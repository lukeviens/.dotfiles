#!/bin/sh
# set up a mac from this repo. safe to re-run: nothing here reinstalls what is already there.
set -e
cd "$(dirname "$0")"
REPO=$(pwd)

# formulae and casks, only if missing. `brew install --cask` on something already installed is a
# REINSTALL, and reinstalling karabiner tears down its driver and launchd services — i.e. the
# keyboard — halfway through, asking for sudo as it goes.
for f in rust tmux neovim zoxide k9s fzf ripgrep tree-sitter-cli jq zsh-vi-mode; do
  brew list --formula "$f" >/dev/null 2>&1 || brew install "$f"
done
for c in wezterm@nightly hammerspoon karabiner-elements font-caskaydia-mono-nerd-font; do
  brew list --cask "$c" >/dev/null 2>&1 || brew install --cask "$c"
done

# shell: ~/.zshrc sources zsh/.zshrc
bash zsh/gen_.zshrc.sh

# hammerspoon reads its config from here, not ~/.hammerspoon
defaults write org.hammerspoon.Hammerspoon MJConfigFile "$REPO/hammerspoon/init.lua"

# tmux plugins live where tpm looks for them (~/.tmux/plugins), which is what tmux.conf runs.
mkdir -p "$HOME/.tmux/plugins"
for p in tmux-plugins/tpm tmux-plugins/tmux-sensible tmux-plugins/tmux-resurrect \
         christoomey/vim-tmux-navigator sainnhe/tmux-fzf; do
  d="$HOME/.tmux/plugins/${p#*/}"
  [ -d "$d" ] || git clone -q --depth 1 "https://github.com/$p" "$d"
done

# town: build it, then let launchd own it. starting the job writes what the surfaces read
# (theme/colors, k9s/skins/luke.yaml, tmux/town-transport.conf) as the residents load.
mkdir -p theme k9s/skins
(cd town && cargo build --release)
sh launchd/town

# nvim: plugins from the lockfile. parsers and language servers install on first open.
nvim --headless "+Lazy! restore" +qa

# hammerspoon owns the keyboard: grant it accessibility when asked
open -a Hammerspoon
