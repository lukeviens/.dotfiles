-- k9s — recolour the k9s skin on the theme. k9s mostly uses `default` (so it follows the
-- terminal/WezTerm bg for free); only the crumb/title bg and the header fg are palette
-- colours, so we just re-write those. k9s hot-reloads its skin file on change.
local SKIN = os.getenv("HOME") .. "/.config/k9s/skins/luke.yaml"
local COLORS = os.getenv("HOME") .. "/.config/theme/colors"   -- read for the boot self-heal

local TEMPLATE = [[
# Auto-written by town on theme change (Caps t). Colours from ~/.config/theme/colors.
k9s:
  frame:
    crumbs:
      bgColor: "%BG%"
    title:
      bgColor: "%BG%"
    header:
      bgColor: default
      fgColor: "%FG%"
  views:
    charts:
      bgColor: default
    table:
      bgColor: default
      header:
        bgColor: default
        fgColor: "%FG%"
    xray:
      bgColor: default
    logs:
      bgColor: default
    yaml:
      bgColor: default
  body:
    bgColor: default
  prompt:
    bgColor: default
  info:
    bgColor: default
  dialog:
    bgColor: default
]]

local function write_skin(bg, fg)
  emit(SKIN, (TEMPLATE:gsub("%%BG%%", bg):gsub("%%FG%%", fg)))
end

-- self-heal: the skin is generated + git-ignored, so a fresh clone lacks it. write it from the
-- current palette if missing, so k9s is themed before the first Caps-t.
heal(SKIN, function()
  local c = palette(slurp(COLORS) or "")
  if c.bg and c.fg then return (TEMPLATE:gsub("%%BG%%", c.bg):gsub("%%FG%%", c.fg)) end
end)

return react {
  on("theme", function(w) if w.body.bg then write_skin(w.body.bg, w.body.fg) end end),
}
