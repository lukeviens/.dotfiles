-- reach.lua — search-and-click over the frontmost window's AX tree (Caps ⇧F): gather every
-- labeled clickable element, hand the list to the picker, click whatever you pick. Entirely
-- local — AX elements can't cross the word-bus, and a clicked button has no life past its page.
local picker = require("picker")
local theme = require("theme")
local town = require("town")
local M = {}

-- a false return is silent otherwise — indistinguishable from the feature being broken.
local function fail(msg)
  hs.alert.closeAll()
  hs.alert.show(msg, { fillColor = { hex = theme.bg, alpha = 1 }, strokeColor = { hex = theme.accent },
    textColor = { hex = theme.fg }, strokeWidth = 1, radius = 8, textSize = 13 }, 0.7)
  return false
end

local CLICKABLE = { AXButton = 1, AXLink = 1, AXCheckBox = 1, AXRadioButton = 1,
  AXPopUpButton = 1, AXMenuButton = 1, AXTabButton = 1, AXTextField = 1, AXComboBox = 1,
  AXTextArea = 1, AXSearchField = 1, AXSlider = 1, AXDisclosureTriangle = 1, AXToggle = 1 }
-- bounds the walk, independent of how many clickables turn up. A web page nests far deeper than
-- a native window, so the budget is time as well as size: a tree we cannot finish is worth more
-- half-walked than not at all.
local MAX_NODES, MAX_DEPTH, BUDGET = 25000, 60, 0.6

local LIMIT = 70   -- a text area's value is its whole content; a label is not a document
local function said(x) return type(x) == "string" and x ~= "" and x:gsub("%s+", " "):sub(1, LIMIT) end

-- in the order a thing is most stably named. Placeholder before value: a chat box is "Message
-- #general" until you type in it, and then it would otherwise rename itself to your draft.
local function label(el)
  return said(el:attributeValue("AXTitle"))
    or said(el:attributeValue("AXDescription"))
    or said(el:attributeValue("AXPlaceholderValue"))
    or said(el:attributeValue("AXHelp"))
    or said(el:attributeValue("AXValue"))
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
  local found, nodes, until_ = {}, 0, hs.timer.secondsSinceEpoch() + BUDGET
  local function walk(el, depth)
    nodes = nodes + 1
    if depth > MAX_DEPTH or nodes > MAX_NODES then return end
    if nodes % 200 == 0 and hs.timer.secondsSinceEpoch() > until_ then return end
    local role = el:attributeValue("AXRole")
    if CLICKABLE[role] then
      -- nothing names it, so say what it is: unreachable is worse than ugly, and `disambiguate`
      -- will pin the nearby text onto it below.
      local lbl = label(el)
        or said(el:attributeValue("AXRoleDescription"))
        or (role and role:gsub("^AX", ""):lower())
      found[#found + 1] = { text = lbl or "?", element = el }
    end
    for _, c in ipairs(el:attributeValue("AXChildren") or {}) do walk(c, depth + 1) end
  end
  walk(root, 0)
  return found
end

-- exact-label collisions only get the (costlier) ancestor walk — a unique label pays nothing.
-- The walk is several AX calls per element, so it is bounded twice: a big collision group is not
-- worth naming one at a time, and the pass as a whole gets the same budget the gather has. Without
-- both, a page where three hundred things are all called "button" took twenty seconds.
local GROUP = 12
local function disambiguate(items)
  local counts, seen = {}, {}
  for _, it in ipairs(items) do counts[it.text] = (counts[it.text] or 0) + 1 end
  local until_ = hs.timer.secondsSinceEpoch() + BUDGET
  for _, it in ipairs(items) do
    if counts[it.text] > 1 then
      seen[it.text] = (seen[it.text] or 0) + 1
      local ctx
      if counts[it.text] <= GROUP and hs.timer.secondsSinceEpoch() < until_ then
        ctx = context(it.element)
      end
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
  -- Chromium apps (Chrome, Slack, Discord, VS Code) do not build their web content's AX tree
  -- unless a client asks. Without this the walk sees the toolbar and nothing in the page, which
  -- is why a link has never been reachable in a browser.
  pcall(function() appEl:setAttributeValue("AXManualAccessibility", true) end)
  local win = appEl:attributeValue("AXFocusedWindow") or appEl:attributeValue("AXMainWindow")
  if not win then return fail("reach: no window") end

  -- each phase says what it cost, so residents/work.lua folds it like any other work
  local function took(since) return math.floor((hs.timer.secondsSinceEpoch() - since) * 1000 + 0.5) end
  local t0 = hs.timer.secondsSinceEpoch()
  local found = gather(win)
  town.talk("work", { where = "reach:gather", ms = took(t0), n = #found }, "past")

  -- the tree is built lazily: the first ask in a Chromium app can arrive after we have walked
  if #found == 0 then
    hs.timer.usleep(120000)
    found = gather(win)
  end
  local t1 = hs.timer.secondsSinceEpoch()
  local choices = disambiguate(found)
  town.talk("work", { where = "reach:name", ms = took(t1) }, "past")
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
