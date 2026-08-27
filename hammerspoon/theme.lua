-- theme.lua — the shared palette. THE SAME FILE wezterm reads. one substrate:
-- edit ~/.config/theme/colors once, and everything downstream re-themes.
local t = { bg = "#1f1d20", fg = "#f8f8f2", subtle = "#878787", active = "#f92672", accent = "#66d9ef" }
local f = io.open(os.getenv("HOME") .. "/.config/theme/colors", "r")
if f then
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.+)$")
    if k and v then t[k] = v end
  end
  f:close()
end
return t
