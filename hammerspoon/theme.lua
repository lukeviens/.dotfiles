-- theme.lua — the shared palette, read from ~/.config/theme/colors: the ONE substrate every
-- surface reads. The town theme resident owns that file (and cycles it via Caps t); no palette
-- is hardcoded here — the resident regenerates the file from its catalog if it ever goes missing.
local t = {}
local f = io.open(os.getenv("HOME") .. "/.config/theme/colors", "r")
if f then
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.+)$")
    if k and v then t[k] = v end
  end
  f:close()
end
return t
