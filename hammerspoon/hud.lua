-- hud.lua — the on-screen chrome for town-mode: the corner badge (which register you're in + how
-- far OUT, coloured per register) and the on-demand `?` reference card. Pure rendering — mode hands
-- it the state (register, depth, the hint items); hud owns the canvases + layout.
local theme = require("theme")
local M = {}

-- the badge: a small overlay canvas (NOT the menu bar), same corner every time — recomputed
-- against the CURRENT primaryScreen on every show, so a resolution/arrangement change since the
-- last show can't leave it parked at a stale, now-wrong position.
local BADGE_W, BADGE_H = 126, 30
local function badgeFrame()
  local s = hs.screen.primaryScreen():frame()
  return { x = s.x + s.w - BADGE_W - 12, y = s.y + 12, w = BADGE_W, h = BADGE_H }
end
local badge = hs.canvas.new(badgeFrame())
badge:appendElements(
  { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 8, yRadius = 8 },
    fillColor = { hex = theme.bg, alpha = 0.92 }, strokeColor = { hex = theme.active }, strokeWidth = 1.5 },
  { type = "text", text = "◆ point", textColor = { hex = theme.active }, textSize = 13,
    textAlignment = "center", frame = { x = 0, y = 6, w = 126, h = 20 } })
badge:level(hs.canvas.windowLevels.overlay)

-- each register wears its own palette hue (base16 slots, so it follows every theme): point = accent
-- (navigating), edge = base09 (warm — pushing walls), cell = base0B (green — carrying a tile). You
-- read the mode by colour at a glance; `where` — nvim, tmux, chrome, mac window, ... — is mode's
-- call (it owns every surface predicate), hud just renders whatever string it's handed.
local REGCOLOR = { point = theme.accent, edge = theme.base09 or theme.active, cell = theme.base0B or theme.active }
function M.badge(reg, where)
  local col = REGCOLOR[reg] or theme.active
  badge[1].strokeColor = { hex = col }
  badge[2].text = "◆ " .. reg .. (where and (" · " .. where) or "")
  badge[2].textColor = { hex = col }
end
function M.showBadge() badge:frame(badgeFrame()); badge:show() end

-- the `?` reference card: a themed canvas built LIVE from the hint items (which town derives from
-- the keymap — keys.lua is the one doc). Rebuilt each open so it reflects the current map + palette.
local card
function M.hideCard()
  if card then pcall(function() card:delete() end); card = nil end
end
function M.cardShown() return card ~= nil end
function M.showCard(items)
  M.hideCard()
  items = items or {}
  if #items == 0 then return end
  local ncols = (#items > 7) and 2 or 1
  local rows  = math.ceil(#items / ncols)
  local PAD, TITLE, ROW, FOOT = 22, 40, 26, 30      -- paddings + title/row/footer bands
  local KEYW, GAP, LBLW = 82, 12, 150               -- key column (right-aligned) | gap | label column
  local colW = KEYW + GAP + LBLW
  local W, H = PAD * 2 + colW * ncols, PAD + TITLE + rows * ROW + FOOT
  local scr = hs.screen.primaryScreen():frame()
  local c = hs.canvas.new({ x = scr.x + (scr.w - W) / 2, y = scr.y + (scr.h - H) / 2, w = W, h = H })
  c:appendElements(
    { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 14, yRadius = 14 },
      fillColor = { hex = theme.bg, alpha = 0.97 }, strokeColor = { hex = theme.active }, strokeWidth = 1.5 },
    { type = "text", text = "◆ town", textColor = { hex = theme.accent }, textSize = 15,
      textFont = "Menlo-Bold", textAlignment = "left", frame = { x = PAD, y = PAD - 2, w = W - PAD * 2, h = 24 } })
  for i, it in ipairs(items) do
    local col, r = math.floor((i - 1) / rows), (i - 1) % rows   -- fill column-major
    local x, y = PAD + col * colW, PAD + TITLE + r * ROW
    c:appendElements(
      { type = "text", text = it.keys, textColor = { hex = theme.accent }, textSize = 13,
        textFont = "Menlo", textAlignment = "right", frame = { x = x, y = y, w = KEYW, h = ROW } },
      { type = "text", text = it.label, textColor = { hex = theme.fg }, textSize = 13,
        textFont = "Menlo", textAlignment = "left", frame = { x = x + KEYW + GAP, y = y, w = LBLW, h = ROW } })
  end
  c:appendElements(
    { type = "text", text = "esc  ·  ? closes", textColor = { hex = theme.subtle }, textSize = 12,
      textFont = "Menlo", textAlignment = "left", frame = { x = PAD, y = H - FOOT + 6, w = W - PAD * 2, h = 20 } })
  c:level(hs.canvas.windowLevels.overlay)
  c:show()
  card = c
end

function M.reset()   -- hide all chrome (every mode exit lands here)
  badge:hide()
  M.hideCard()
end

function M.stop()   -- teardown + GC anchor (its upvalue keeps the badge canvas reachable)
  if badge then pcall(function() badge:delete() end) end
end

return M
