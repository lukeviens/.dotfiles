local wezterm = require 'wezterm'
local config = wezterm.config_builder()


config.font = wezterm.font 'CaskaydiaCove NFM'
--config.color_scheme = 'Operator Mono Dark'
--config.color_scheme = 'Molokai (Gogh)'
--config.color_scheme = 'Afterglow (Gogh)'
--config.color_scheme = 'Arthur'
--config.color_scheme = 'Ashes (dark) (terminal.sexy)'
--config.color_scheme = 'Atelier Cave (base16)'
--config.color_scheme = 'Chalk (dark) (terminal.sexy)'

config.color_scheme = 'Darktooth (base16)'

config.window_background_opacity = 1

return config
