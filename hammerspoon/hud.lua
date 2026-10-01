-- hud.lua — the on-screen chrome for town-mode: the corner badge (which register you're in + how
-- far OUT, coloured per register) and the on-demand `?` reference card. Pure rendering — mode hands
-- it the state (register, depth, the hint items); hud owns the canvases + layout.
local theme = require("theme")
local M = {}

local function color(hex)
  return { hex = hex, alpha = 1.0 }
end
-- one in-theme alert style: a bg fill + a palette stroke; the rest defaults
function M.style(o)
  return {
    fillColor = color(theme.bg),
    strokeColor = color(o.stroke),
    textColor = color(o.text or theme.fg),
    strokeWidth = o.sw or 2,
    radius = o.radius or 8,
    textSize = o.size or 14,
  }
end

-- a small, in-theme toast (the raw hs.alert is huge and off-palette)
function M.toast(msg, secs)
  hs.alert.closeAll()
  hs.alert.show(msg, M.style({ stroke = theme.accent, sw = 1, size = 13 }), secs or 0.7)
end

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
  {
    type = "rectangle",
    action = "fill",
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
    fillColor = { hex = theme.bg, alpha = 0.92 },
    strokeColor = { hex = theme.active },
    strokeWidth = 1.5,
  },
  {
    type = "text",
    text = "◆ point",
    textColor = { hex = theme.active },
    textSize = 13,
    textAlignment = "center",
    frame = { x = 0, y = 6, w = 126, h = 20 },
  }
)
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

function M.showBadge()
  badge:frame(badgeFrame())
  badge:show()
end

-- the `?` reference card: a themed canvas built LIVE from the hint items (which town derives from
-- the keymap — keys.lua is the one doc). Rebuilt each open so it reflects the current map + palette.
local card
local page -- which card is up: "keys" | "time" | nil
function M.hideCard()
  page = nil
  if card then
    pcall(function()
      card:delete()
    end)
    card = nil
  end
end

function M.cardShown(which)
  return card ~= nil and (which == nil or page == which)
end

local PAD, TITLE, ROW, FOOT = 22, 40, 26, 30 -- paddings + title/row/footer bands
-- the card's frame: a rounded panel centred on the primary screen with a title and a footer.
-- returns the canvas; the caller appends rows and shows it.
local function frame(W, H, title, foot)
  local scr = hs.screen.primaryScreen():frame()
  local c = hs.canvas.new({ x = scr.x + (scr.w - W) / 2, y = scr.y + (scr.h - H) / 2, w = W, h = H })
  c:appendElements(
    {
      type = "rectangle",
      action = "fill",
      roundedRectRadii = { xRadius = 14, yRadius = 14 },
      fillColor = { hex = theme.bg, alpha = 0.97 },
      strokeColor = { hex = theme.active },
      strokeWidth = 1.5,
    },
    {
      type = "text",
      text = title,
      textColor = { hex = theme.accent },
      textSize = 15,
      textFont = "Menlo-Bold",
      textAlignment = "left",
      frame = { x = PAD, y = PAD - 2, w = W - PAD * 2, h = 24 },
    },
    {
      type = "text",
      text = foot,
      textColor = { hex = theme.subtle },
      textSize = 12,
      textFont = "Menlo",
      textAlignment = "left",
      frame = { x = PAD, y = H - FOOT + 6, w = W - PAD * 2, h = 20 },
    }
  )
  c:level(hs.canvas.windowLevels.overlay)
  return c
end
local function up(c, which)
  M.hideCard()
  c:show()
  card, page = c, which
end

-- the key card: { keys, label } items, key column right-aligned, two columns past seven rows.
function M.showCard(items)
  items = items or {}
  if #items == 0 then
    return
  end
  local ncols = (#items > 7) and 2 or 1
  local rows = math.ceil(#items / ncols)
  local KEYW, GAP, LBLW = 82, 12, 150
  local colW = KEYW + GAP + LBLW
  local W, H = PAD * 2 + colW * ncols, PAD + TITLE + rows * ROW + FOOT
  local c = frame(W, H, "◆ town", "?  time  ·  esc closes")
  for i, it in ipairs(items) do
    local col, r = math.floor((i - 1) / rows), (i - 1) % rows -- fill column-major
    local x, y = PAD + col * colW, PAD + TITLE + r * ROW
    c:appendElements(
      {
        type = "text",
        text = it.keys,
        textColor = { hex = theme.accent },
        textSize = 13,
        textFont = "Menlo",
        textAlignment = "right",
        frame = { x = x, y = y, w = KEYW, h = ROW },
      },
      {
        type = "text",
        text = it.label,
        textColor = { hex = theme.fg },
        textSize = 13,
        textFont = "Menlo",
        textAlignment = "left",
        frame = { x = x + KEYW + GAP, y = y, w = LBLW, h = ROW },
      }
    )
  end
  up(c, "keys")
end

-- a table card: t = { page, title, foot, head = {…}, rows = {{…, mark=?}}, widths = {…} (px) }.
-- Each cell is its own text element: the first column left-aligned, the rest right; the head in
-- the subtle colour, a row's `mark` (e.g. "!") after it in the active colour.
function M.showTable(t)
  local GAP, MARKW = 18, 24
  local W = PAD * 2 + MARKW
  for _, w in ipairs(t.widths) do
    W = W + w + GAP
  end
  local H = PAD + TITLE + (#t.rows + 1) * ROW + FOOT
  local c = frame(W, H, t.title, t.foot)
  local function cells(row, y, colour, font)
    local x = PAD
    for i, w in ipairs(t.widths) do
      c:appendElements({
        type = "text",
        text = tostring(row[i] or ""),
        textColor = { hex = colour },
        textSize = 13,
        textFont = font,
        textAlignment = (i == 1) and "left" or "right",
        frame = { x = x, y = y, w = w, h = ROW },
      })
      x = x + w + GAP
    end
    if row.mark then
      c:appendElements({
        type = "text",
        text = row.mark,
        textColor = { hex = theme.active },
        textSize = 13,
        textFont = "Menlo-Bold",
        textAlignment = "left",
        frame = { x = x, y = y, w = MARKW, h = ROW },
      })
    end
  end
  cells(t.head, PAD + TITLE, theme.subtle, "Menlo")
  for i, r in ipairs(t.rows) do
    cells(r, PAD + TITLE + i * ROW, theme.fg, "Menlo")
  end
  up(c, t.page)
end

function M.reset() -- hide all chrome (every mode exit lands here)
  badge:hide()
  M.hideCard()
end

function M.stop() -- teardown + GC anchor (its upvalue keeps the badge canvas reachable)
  if badge then
    pcall(function()
      badge:delete()
    end)
  end
  -- an open card at reload time was never cleaned up here — its window leaked at the OS level
  -- on every reload that caught it open (this repo reloads on every file save), each one left
  -- behind as a stray overlay window macOS kept trying and failing to focus. See hideCard().
  M.hideCard()
end

return M
