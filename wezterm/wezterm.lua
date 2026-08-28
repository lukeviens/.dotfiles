local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- shared theme colors (~/.config/theme/colors)
local function load_theme()   -- read the one shared palette; the town resident keeps it present
  local t = {}
  local f = io.open(os.getenv("HOME") .. "/.config/theme/colors", "r")
  if f then
    for line in f:lines() do
      local key, val = line:match("^([%w_]+)=(.+)$")
      if key and val then t[key] = val end
    end
    f:close()
  end
  return t
end

local theme = load_theme()

-- re-theme live when the shared palette changes (wezterm re-reads on reload)
wezterm.add_to_config_reload_watch_list(os.getenv("HOME") .. "/.config/theme/colors")

config.font = wezterm.font 'CaskaydiaMono Nerd Font Mono'
config.color_scheme = 'Darktooth (base16)'

config.window_decorations = "INTEGRATED_BUTTONS | RESIZE | MACOS_FORCE_ENABLE_SHADOW"
config.integrated_title_button_style = "Windows"

config.window_background_opacity = .995

config.window_frame = {
  border_left_width = '0.25cell',
  border_right_width = '0.25cell',
  border_bottom_height = '0.13cell',
  border_top_height = '0.25cell',
  border_left_color = theme.bg,
  border_right_color = theme.bg,
  border_bottom_color = theme.bg,
  border_top_color = theme.bg,
}

-- tab bar styling
-- named DARK themes keep their curated color_scheme (Darktooth) ANSI + cursor; random rolls and
-- light themes use the theme-derived base16 ANSI, so the whole terminal follows those.
local gen_ansi = (theme.name == "random" or theme.mode == "light") and theme.base00
config.colors = {
  background = theme.bg,
  foreground = theme.fg,
  ansi = gen_ansi and { theme.base00, theme.base08, theme.base0B, theme.base0A, theme.base0D, theme.base0E, theme.base0C, theme.base05 } or nil,
  brights = gen_ansi and { theme.base03, theme.base08, theme.base0B, theme.base0A, theme.base0D, theme.base0E, theme.base0C, theme.base07 } or nil,
  tab_bar = {
    background = theme.bg,

    active_tab = {
      bg_color = theme.bg,
      fg_color = theme.active,
      intensity = "Bold",
      underline = "None",
      italic = false,
      strikethrough = false,
    },

    inactive_tab = {
      bg_color = theme.bg,
      fg_color = theme.subtle,
    },

    inactive_tab_hover = {
      bg_color = theme.bg,
      fg_color = theme.fg,
      italic = true,
    },

    new_tab = {
      bg_color = theme.bg,
      fg_color = theme.fg,
    },

    new_tab_hover = {
      bg_color = theme.bg,
      fg_color = theme.active,
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
    {Background={Color=theme.bg}}, {Foreground={Color=theme.active}}, {Attribute={Intensity="Bold"}},
    {Text=" 󰕰  "..session_name.." "},
    "ResetAttributes",
    {Foreground={Color=theme.subtle}}, {Text=""},
    {Foreground={Color=theme.fg}}, {Text=" "..username.."@"..hostname.." • "..local_ip.." "},
    {Foreground={Color=theme.subtle}}, {Text=" "},
  })

  local right = wezterm.format({
    {Foreground={Color=theme.accent}}, {Text="󰥔 "..date.."  "},
    {Foreground={Color=theme.fg}}, {Text="⏱ "..time.."  "},
  })

  window:set_left_status(left)
  window:set_right_status(right)
end)

-- tab bar prefs
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.show_tab_index_in_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

-- send Ctrl+Enter as a distinct sequence so tmux can bind it (level-aware ⌃⏎ zoom)
config.keys = {
  { key = 'Enter', mods = 'CTRL', action = wezterm.action.SendString('\x1b[13;5u') },
  -- ⌥hjkl → legacy Meta bytes (ESC+letter), which tmux's `bind -n M-…` matches. (Other ⌥
  -- keys still compose their special chars — only these four are intercepted.)
  { key = 'h', mods = 'ALT', action = wezterm.action.SendString('\x1bh') },
  { key = 'j', mods = 'ALT', action = wezterm.action.SendString('\x1bj') },
  { key = 'k', mods = 'ALT', action = wezterm.action.SendString('\x1bk') },
  { key = 'l', mods = 'ALT', action = wezterm.action.SendString('\x1bl') },
}

return config
