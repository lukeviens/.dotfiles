-- reach.lua — search-and-click over the frontmost window's AX tree (Caps ⇧F): gather every
-- labeled clickable element, hand the list to the picker, click whatever you pick. Entirely
-- local — AX elements can't cross the word-bus, and a clicked button has no life past its page.
local picker = require("picker")
local theme = require("theme")
local M = {}

-- a false return is silent otherwise — indistinguishable from the feature being broken.
local function fail(msg)
  hs.alert.closeAll()
  hs.alert.show(msg, { fillColor = { hex = theme.bg, alpha = 1 }, strokeColor = { hex = theme.accent },
    textColor = { hex = theme.fg }, strokeWidth = 1, radius = 8, textSize = 13 }, 0.7)
  return false
end

local CLICKABLE = { AXButton = 1, AXLink = 1, AXCheckBox = 1, AXRadioButton = 1,
  AXPopUpButton = 1, AXMenuButton = 1, AXTabButton = 1, AXTextField = 1, AXComboBox = 1 }
-- bounds the walk itself, independent of how many clickables turn up — a deeply-nested tree
-- must not be able to run away just because it keeps nesting containers.
local MAX_NODES, MAX_DEPTH = 4000, 20

local function label(el)
  local t = el:attributeValue("AXTitle");       if t and t ~= "" then return t end
  local d = el:attributeValue("AXDescription"); if d and d ~= "" then return d end
  local h = el:attributeValue("AXHelp");        if h and h ~= "" then return h end
  local v = el:attributeValue("AXValue");       if type(v) == "string" and v ~= "" then return v end
end

-- nearest bit of context for a label that collides with another ("React", "View", ...): walk up
-- a few ancestors, take the first parent description or sibling static text that differs.
local function context(el)
  local node = el
  for _ = 1, 4 do
    node = node:attributeValue("AXParent")
    if not node then return nil end
    local d = node:attributeValue("AXDescription")
    if d and d ~= "" then return d end
    for _, sib in ipairs(node:attributeValue("AXChildren") or {}) do
      if sib ~= el and sib:attributeValue("AXRole") == "AXStaticText" then
        local v = sib:attributeValue("AXValue")
        if type(v) == "string" and v ~= "" then return v end
      end
    end
  end
end

local function gather(root)
  local found, nodes = {}, 0
  local function walk(el, depth)
    nodes = nodes + 1
    if depth > MAX_DEPTH or nodes > MAX_NODES then return end
    if CLICKABLE[el:attributeValue("AXRole")] then
      local lbl = label(el)
      if lbl then found[#found + 1] = { text = lbl, element = el } end
    end
    for _, c in ipairs(el:attributeValue("AXChildren") or {}) do walk(c, depth + 1) end
  end
  walk(root, 0)
  return found
end

-- exact-label collisions only get the (costlier) ancestor walk — the common case, a unique
-- label, pays nothing beyond the gather above.
local function disambiguate(items)
  local counts, seen = {}, {}
  for _, it in ipairs(items) do counts[it.text] = (counts[it.text] or 0) + 1 end
  for _, it in ipairs(items) do
    if counts[it.text] > 1 then
      local ctx = context(it.element)
      seen[it.text] = (seen[it.text] or 0) + 1
      it.text = ctx and (it.text .. " — " .. ctx) or (it.text .. " (" .. seen[it.text] .. ")")
    end
  end
  return items
end

function M.open()
  local app = hs.application.frontmostApplication()
  local appEl = app and hs.axuielement.applicationElement(app)
  if not appEl then return fail("reach: no frontmost app") end
  appEl:setTimeout(0.15)   -- on the application element — the level that propagates to descendants
  local win = appEl:attributeValue("AXFocusedWindow") or appEl:attributeValue("AXMainWindow")
  if not win then return fail("reach: no window") end

  local choices = disambiguate(gather(win))
  if #choices == 0 then return fail("reach: nothing clickable here") end
  picker.show({ choices = choices, onSelect = function(c)
    app:activate()   -- the picker's webview stole focus; reclaim it before clicking anything
    -- a real click at the element's frame works everywhere; AXPress alone misses on Electron
    -- apps (their custom components listen for a mouse event, not the accessibility action) —
    -- so AXPress is only the fallback for something with no frame to click.
    local ok, err = pcall(function()
      local f = c.element:attributeValue("AXFrame")
      if f then hs.eventtap.leftClick({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
      else c.element:performAction("AXPress") end
    end)
    fail(ok and ("reach: clicked " .. c.text) or ("reach: click failed — " .. tostring(err)))
  end, onCancel = function() app:activate() end })
  return true
end

return M
