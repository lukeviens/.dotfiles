local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- TODO: make this into program instead of garbage script
-- add theme engine to custom styles

--config.font = wezterm.font 'CaskaydiaCove NFM'
config.font = wezterm.font 'CaskaydiaMono Nerd Font Mono'

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

--local COLOR_BG       = "#1d2021"
local COLOR_BG         = "#19181a"
local COLOR_FG         = "#f8f8f2"
local COLOR_SUBTLE     = "#878787"
local COLOR_ACTIVE_BG  = "#19181a"
local COLOR_ACTIVE_FG  = "#f92672"
local COLOR_ACCENT     = "#66d9ef"


config.window_frame = {
  border_left_width = '0.25cell',
  border_right_width = '0.25cell',
  border_bottom_height = '0.13cell',
  border_top_height = '0.25cell',
  border_left_color = COLOR_BG,
  border_right_color = COLOR_BG,
  border_bottom_color = COLOR_BG,
  border_top_color = COLOR_BG,
}

-- tab bar styling
config.colors = {
  background = COLOR_BG,
  foreground = "c5c5b5",
  tab_bar = {
    background = COLOR_BG,

    active_tab = {
      bg_color = COLOR_ACTIVE_BG,
      fg_color = COLOR_ACTIVE_FG,
      intensity = "Bold",
      underline = "None",
      italic = false,
      strikethrough = false,
    },

    inactive_tab = {
      bg_color = COLOR_BG,
      fg_color = COLOR_SUBTLE,
    },

    inactive_tab_hover = {
      bg_color = COLOR_BG,
      fg_color = COLOR_FG,
      italic = true,
    },

    new_tab = {
      bg_color = COLOR_BG,
      fg_color = COLOR_FG,
    },

    new_tab_hover = {
      bg_color = COLOR_BG,
      fg_color = COLOR_ACTIVE_FG,
    },
  },
}

local function safe_read(cmd)
  local handle = io.popen(cmd)
  local result = handle and handle:read("*a") or "?"
  if handle then handle:close() end
  return result:gsub("%s+", "")
end

local hostname = safe_read("hostname")
local local_ip = safe_read("ipconfig getifaddr en0")
local username = os.getenv("USER")

-- status bar
wezterm.on("update-status", function(window, pane)
  local time = wezterm.strftime("%H:%M")
  local date = wezterm.strftime("%a %b %-d")
  local session_name = pane:get_foreground_process_name():match("[^/]+$") or "shell"

  local left = wezterm.format({
    {Background={Color=COLOR_ACTIVE_BG}}, {Foreground={Color=COLOR_ACTIVE_FG}}, {Attribute={Intensity="Bold"}},
    {Text=" 󰕰  "..session_name.." "},
    "ResetAttributes",
    {Foreground={Color=COLOR_SUBTLE}}, {Text=""},
    {Foreground={Color=COLOR_FG}}, {Text=" "..username.."@"..hostname.." • "..local_ip.." "},
    {Foreground={Color=COLOR_SUBTLE}}, {Text=" "},
  })

  local right = wezterm.format({
    {Foreground={Color=COLOR_ACCENT}}, {Text="󰥔 "..date.."  "},
    {Foreground={Color=COLOR_FG}}, {Text="⏱ "..time.."  "},
  })

  window:set_left_status(left)
  window:set_right_status(right)
end)

-- tab bar prefs
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.show_tab_index_in_tab_bar = true 
config.hide_tab_bar_if_only_one_tab = false

return config

