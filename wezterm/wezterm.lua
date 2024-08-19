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

config.window_decorations = "INTEGRATED_BUTTONS | RESIZE | MACOS_FORCE_ENABLE_SHADOW"
config.integrated_title_button_style = "Windows"

config.window_background_opacity = .995

config.window_frame = {
  border_left_width = '0.25cell',
  border_right_width = '0.25cell',
  border_bottom_height = '0.13cell',
  border_top_height = '0.13cell',
  border_left_color = '#3f3a39',
  border_right_color = '#3f3a39',
  border_bottom_color = '#3f3a39',
  border_top_color = '#3f3a39',
}

config.use_fancy_tab_bar = true

config.enable_tab_bar = false

return config
