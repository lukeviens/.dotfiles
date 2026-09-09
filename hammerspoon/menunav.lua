-- menunav.lua — drive a real mac menu (leader m) entirely through the Accessibility API: AXPress to
-- open, AXSelected to move the highlight, AXPress/AXCancel to pick or dismiss. No synthetic key
-- events — confirmed live: this system UI layer silently ignores hs.eventtap.keyStroke, both for
-- the ⌃F2/Fn-N system shortcuts that were supposed to open it and for arrow keys once it's open.
local M = {}

local topItems, topIdx = nil, nil
local frames = {}   -- stack of {items, idx}; frames[1] is the currently open top-level menu's list

local function children(el) return el and el:attributeValue("AXChildren") or {} end
local function frame() return frames[#frames] end
local function current() local f = frame(); return f and f.items[f.idx] end

-- the next/previous item whose title isn't blank (menu separators are titleless AXMenuItems).
local function skip(items, from, dir)
  local n = #items
  if n == 0 then return from end
  local i = from
  for _ = 1, n do
    i = ((i - 1 + dir) % n) + 1
    if items[i]:attributeValue("AXTitle") ~= "" then return i end
  end
  return from
end

local function highlight()
  local it = current()
  if it then it:setAttributeValue("AXSelected", true) end
end

-- an item's own submenu, if it has one (recursive: same item→AXMenu→AXChildren shape as the menu
-- bar itself), so drilling into a nested `>` item works exactly like opening a top-level one.
local function submenuItems(item)
  local sub = children(item)[1]
  return sub and children(sub)
end

local function openTop(i)
  topIdx = i
  topItems[i]:performAction("AXPress")
  local items = submenuItems(topItems[i]) or {}
  frames = { { items = items, idx = skip(items, 0, 1) } }
  highlight()
end

function M.open()
  local app = hs.application.frontmostApplication()
  local bar = app and hs.axuielement.applicationElement(app):attributeValue("AXMenuBar")
  topItems = bar and children(bar)
  if not topItems or #topItems == 0 then return false end
  openTop(1)
  return true
end

-- h: back out of a submenu one level, or — already at the top level — the previous menu bar item.
-- (The vacated popout can be left visually open — AXCancel here closed the WHOLE menu instead of
-- just one level, desyncing it from `frames`; not worth it until there's a level-scoped action.)
function M.left()
  if #frames > 1 then table.remove(frames); highlight()
  elseif topItems then openTop(((topIdx - 2) % #topItems) + 1) end
end

-- l: descend into the highlighted item's submenu if it has one, else the next menu bar item.
function M.right()
  local it = current()
  local kids = it and submenuItems(it)
  if kids and #kids > 0 then
    it:performAction("AXPress")
    frames[#frames + 1] = { items = kids, idx = skip(kids, 0, 1) }
    highlight()
  elseif topItems then openTop(topIdx % #topItems + 1) end
end

function M.down() local f = frame(); if f then f.idx = skip(f.items, f.idx, 1); highlight() end end
function M.up()   local f = frame(); if f then f.idx = skip(f.items, f.idx, -1); highlight() end end

function M.select() local it = current(); if it then it:performAction("AXPress") end end
function M.cancel()  local it = current(); if it then it:performAction("AXCancel") end end

return M
