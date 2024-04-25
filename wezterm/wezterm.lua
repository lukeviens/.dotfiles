local wezterm = require 'wezterm'
local config = wezterm.config_builder()


config.font = wezterm.font 'CaskaydiaCove NFM'
config.color_scheme = 'Operator Mono Dark'

return config
