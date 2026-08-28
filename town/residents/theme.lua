-- theme — the palette. Watches the shared colours file and talks it as the theme (every
-- surface listens and re-colours); a future `theme` word (Caps t) CYCLES a set of palettes
-- by writing the next one to that same file — the watch fan-out then re-colours HS, tmux,
-- and WezTerm together. One file is the whole substrate.
local COLORS = os.getenv("HOME") .. "/.config/theme/colors"

local skins = {   -- cycle order (Caps t): dark → sun → light → black → dark; the first is the default.
  -- `mode` (light|dark) is the single source surfaces use to flip macOS appearance / nvim bg.
  { name = "dark",  mode = "dark",  bg = "#1f1d20", fg = "#f8f8f2", subtle = "#878787", active = "#f92672", accent = "#66d9ef" },
  { name = "sun",   mode = "light", bg = "#fdf6e3", fg = "#586e75", subtle = "#93a1a1", active = "#cb4b16", accent = "#268bd2" },
  { name = "light", mode = "light", bg = "#faf8f3", fg = "#2d2a2e", subtle = "#9c9791", active = "#d6005c", accent = "#0e88b0" },
  { name = "black", mode = "dark",  bg = "#000000", fg = "#ffffff", subtle = "#5a5a5a", active = "#00ff9f", accent = "#00e5ff" },
}

-- a coherent RANDOM dark palette (Caps ⇧T): one base hue drives bg/fg/subtle/active, a
-- contrasting hue drives the accent — so it always reads as a real theme rather than noise.
math.randomseed(os.time())
local function hsl(h, s, l)   -- h 0-360, s/l 0-1 → #rrggbb
  local function f(n)
    local k = (n + h / 30) % 12
    local a = s * math.min(l, 1 - l)
    return l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
  end
  return string.format("#%02x%02x%02x",
    math.floor(f(0) * 255 + 0.5), math.floor(f(8) * 255 + 0.5), math.floor(f(4) * 255 + 0.5))
end

-- a full 16-colour base16 from the 5 palette values: a grey ramp bg→fg (base00-07) and 8 accents
-- walked round the hue wheel at this theme's saturation/lightness, rotated to its hue (base08-0F).
-- WezTerm feeds these to its ANSI palette and nvim to its generated scheme → one palette, everywhere.
local function hex2rgb(h)
  h = h:gsub("#", "")
  return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end
local function hex2hsl(hex)
  local r, g, b = hex2rgb(hex)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l = (mx + mn) / 2
  local h, s = 0, 0
  if mx ~= mn then
    local d = mx - mn
    s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    if mx == r then h = (g - b) / d + (g < b and 6 or 0)
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, s, l
end
local function lerp(a, b, t)
  local ar, ag, ab = hex2rgb(a)
  local br, bg, bb = hex2rgb(b)
  return string.format("#%02x%02x%02x",
    math.floor(ar + (br - ar) * t + 0.5),
    math.floor(ag + (bg - ag) * t + 0.5),
    math.floor(ab + (bb - ab) * t + 0.5))
end
local BASE_OFF = { [8] = 0, [9] = 25, [10] = 50, [11] = 120, [12] = 175, [13] = 210, [14] = 280, [15] = 15 }
local function base16(s)
  local baseH, aS = hex2hsl(s.active)
  aS = math.max(0.55, math.min(0.95, aS))
  local aL = (s.mode == "light") and 0.44 or 0.64
  local b = {}
  for i = 0, 7 do b[i] = lerp(s.bg, s.fg, i / 7) end
  b[3] = s.subtle
  for i = 8, 15 do b[i] = hsl((baseH + BASE_OFF[i]) % 360, aS, aL) end
  return b
end

local function random_skin()
  local function r(a, b) return math.random(a, b) / 100 end
  local h  = math.random(0, 359)                                              -- base hue
  local h2 = (h + ({ 30, 45, 60, 120, 150, 180, 210, 330 })[math.random(1, 8)]) % 360  -- accent harmony
  if math.random(1, 4) == 1 then                                             -- ~1 in 4 rolls light
    return { name = "random", mode = "light",
      bg = hsl(h, r(18, 45), r(92, 97)), fg = hsl(h, r(25, 60), r(16, 28)), subtle = hsl(h, 0.18, 0.55),
      active = hsl(h, r(60, 85), r(38, 50)), accent = hsl(h2, r(55, 82), r(40, 52)) }
  end
  return { name = "random", mode = "dark",
    bg = hsl(h, r(14, 38), r(5, 12)), fg = hsl(h, r(6, 20), r(88, 96)), subtle = hsl(h, 0.16, 0.46),
    active = hsl(h, r(62, 90), r(55, 68)), accent = hsl(h2, r(58, 85), r(55, 68)) }
end

local function current()   -- the skin the file holds now — by its name, else by matching bg
  local f = io.open(COLORS, "r"); if not f then return 1 end
  local p = palette(f:read("*a")); f:close()
  for i, s in ipairs(skins) do
    if s.name == p.name or (not p.name and s.bg == p.bg) then return i end
  end
  return 1
end

local function write(s)    -- write a palette to the shared file; the watch does the rest
  local f = io.open(COLORS, "w"); if not f then return end
  f:write("# shared palette\n")
  for _, k in ipairs({ "name", "mode", "bg", "fg", "subtle", "active", "accent" }) do
    f:write(k .. "=" .. s[k] .. "\n")
  end
  local b = base16(s)   -- + the derived 16-colour scheme, for WezTerm's ANSI + nvim's generator
  for i = 0, 15 do f:write(string.format("base%02X=%s\n", i, b[i])) end
  f:close()
end

-- single source of truth: if the shared file is ever missing, regenerate it from the catalog,
-- so every surface can just read the file (no hardcoded fallbacks anywhere else).
local have = io.open(COLORS, "r")
if have then have:close() else write(skins[1]) end

return {
  watch  = { colors = COLORS },
  listen = { "colors", "theme" },
  talk   = function(w)
    if w.kind == "colors" then
      return fact("theme", palette(w.body))   -- file changed → broadcast the palette
    elseif w.kind == "theme" and w.tense == "future" then
      if w.body.to == "random" then write(random_skin())  -- Caps ⇧T → a fresh random palette
      else write(skins[current() % #skins + 1]) end        -- Caps t → the next palette, wrapping
    end
  end,
}
