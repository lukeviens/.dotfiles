local wezterm = require 'wezterm'
local config = wezterm.config_builder()


config.font = wezterm.font 'CaskaydiaCove Nerd Font Mono'
config.color_scheme = 'Gruvbox Dark (Gogh)'

return config
