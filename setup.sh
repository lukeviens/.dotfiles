#!/bin/sh
# set up a mac from this repo. run again any time; every step is safe to repeat.
set -e
cd "$HOME/.config"

# tools (karabiner asks for your password: it installs a driver)
brew install rust tmux neovim zoxide k9s fzf ripgrep tree-sitter-cli
brew install --cask wezterm hammerspoon karabiner-elements font-caskaydia-mono-nerd-font

# shell: ~/.zshrc sources zsh/.zshrc
bash zsh/gen_.zshrc.sh

# hammerspoon reads its config from here, not ~/.hammerspoon
defaults write org.hammerspoon.Hammerspoon MJConfigFile "$HOME/.config/hammerspoon/init.lua"

# tmux: tpm in ~/.tmux, plugins in tmux/plugins
[ -d "$HOME/.tmux/plugins/tpm" ] || git clone -q https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
for p in tmux-plugins/tpm tmux-plugins/tmux-sensible tmux-plugins/tmux-resurrect \
         christoomey/vim-tmux-navigator sainnhe/tmux-fzf; do
  [ -d "tmux/plugins/${p#*/}" ] || git clone -q --depth 1 "https://github.com/$p" "tmux/plugins/${p#*/}"
done

# town: build, then boot once so it writes what the surfaces read
# (theme/colors, k9s/skins/luke.yaml, tmux/town-transport.conf)
(cd town && cargo build --release)
mkdir -p theme k9s/skins
town/target/release/town & sleep 2; kill $! 2>/dev/null || true

# nvim: plugins from the lockfile. parsers and language servers install on first open.
nvim --headless "+Lazy! restore" +qa

# hammerspoon boots town and owns the keyboard: grant it accessibility when asked
open -a Hammerspoon
