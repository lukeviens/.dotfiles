local wezterm = require 'wezterm'
local config = wezterm.config_builder()


config.font = wezterm.font 'CaskaydiaCove NFM'
config.color_scheme = 'tokyonight_night'

return config
