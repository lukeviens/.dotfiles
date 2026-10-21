-- reach.lua — point at anything on screen. Caps ⇧F puts a letter on every clickable thing in the
-- frontmost window; type the letter and it is clicked.
--
-- nothing is named. an AX tree doesn't label its own buttons, so most come back called "button"
-- and telling them apart costs an ancestor walk each. a letter you can see needs no name.
local theme = require("theme")
local town = require("town")
local M = {}

local CLICKABLE = { AXButton = 1, AXLink = 1, AXCheckBox = 1, AXRadioButton = 1,
  AXPopUpButton = 1, AXMenuButton = 1, AXTabButton = 1, AXTextField = 1, AXComboBox = 1,
  AXTextArea = 1, AXSearchField = 1, AXSlider = 1, AXDisclosureTriangle = 1, AXToggle = 1 }
-- a web page nests far deeper than a native window, so the budget is time as well as size: a tree
-- we cannot finish is worth more half-walked than not at all.
local MAX_NODES, MAX_DEPTH, BUDGET = 25000, 60, 0.6
local KEYS = "asdfghjklqwertyuiopzxcvbnm"   -- home row first: the easiest letters are offered first

local overlay, tap, hints, typed

local function fail(msg)
  hs.alert.closeAll()
  hs.alert.show(msg, { fillColor = { hex = theme.bg, alpha = 1 }, strokeColor = { hex = theme.accent },
    textColor = { hex = theme.fg }, strokeWidth = 1, radius = 8, textSize = 13 }, 0.7)
  return false
end

-- n keys: single letters while they last, then pairs. 26 covers most windows; 676 covers any.
local function keysFor(n)
  local k, out = #KEYS, {}
  if n <= k then
    for i = 1, n do out[i] = KEYS:sub(i, i) end
    return out
  end
  for a = 1, k do
    for b = 1, k do
      if #out >= n then return out end
      out[#out + 1] = KEYS:sub(a, a) .. KEYS:sub(b, b)
    end
  end
  return out
end

-- every clickable with a frame you can actually see. Role and frame only — two reads, where
-- naming took six and then the ancestor walk on top.
local function gather(root, within)
  local found, nodes, until_ = {}, 0, hs.timer.secondsSinceEpoch() + BUDGET
  local function walk(el, depth)
    nodes = nodes + 1
    if depth > MAX_DEPTH or nodes > MAX_NODES then return end
    if nodes % 200 == 0 and hs.timer.secondsSinceEpoch() > until_ then return end
    if CLICKABLE[el:attributeValue("AXRole")] then
      local f = el:attributeValue("AXFrame")
      -- scrolled out of view, or collapsed to nothing: a letter there points at nothing
      if f and f.w > 2 and f.h > 2 and f.x + f.w > within.x and f.y + f.h > within.y
        and f.x < within.x + within.w and f.y < within.y + within.h then
        found[#found + 1] = { element = el, frame = f }
      end
    end
    for _, c in ipairs(el:attributeValue("AXChildren") or {}) do walk(c, depth + 1) end
  end
  walk(root, 0)
  return found
end

local PAD, SIZE = 3, 11
local function draw()
  local origin, els = overlay:frame(), {}
  for _, h in ipairs(hints) do
    if h.key:sub(1, #typed) == typed then
      local lit = #typed > 0
      local w = #h.key * 9 + PAD * 2
      local box = { x = h.frame.x - origin.x, y = h.frame.y - origin.y, w = w, h = SIZE + PAD * 2 }
      els[#els + 1] = { type = "rectangle", action = "fill", frame = box,
        roundedRectRadii = { xRadius = 3, yRadius = 3 },
        fillColor = { hex = lit and theme.active or theme.bg, alpha = 0.95 },
        strokeColor = { hex = theme.active }, strokeWidth = 1 }
      els[#els + 1] = { type = "text", text = h.key:upper(), frame = box,
        textColor = { hex = lit and theme.bg or theme.active },
        textSize = SIZE, textAlignment = "center" }
    end
  end
  overlay:replaceElements(table.unpack(els))
end

local function stop()
  if tap then tap:stop(); tap = nil end
  if overlay then overlay:delete(); overlay = nil end
  hints, typed = nil, nil
end

local function press(h)
  stop()
  -- a real click at the frame works everywhere; AXPress alone misses on Electron apps, whose
  -- custom components listen for a mouse event rather than the accessibility action.
  local ok, err = pcall(function()
    local f = h.frame
    if f then hs.eventtap.leftClick({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
    else h.element:performAction("AXPress") end
  end)
  if not ok then fail("reach: click failed — " .. tostring(err)) end
end

local function typedKey(e)
  local c = hs.keycodes.map[e:getKeyCode()]
  if c == "escape" then stop(); return true end
  if c == "delete" then typed = typed:sub(1, -2); draw(); return true end
  local ch = (e:getCharacters() or ""):lower()
  if not ch:match("^%l$") then stop(); return true end   -- anything else means you are done
  typed = typed .. ch
  local hit, alive = nil, 0
  for _, h in ipairs(hints) do
    if h.key:sub(1, #typed) == typed then alive = alive + 1; if h.key == typed then hit = h end end
  end
  if hit then press(hit) elseif alive == 0 then stop() else draw() end
  return true
end

function M.open()
  stop()
  local app = hs.application.frontmostApplication()
  local appEl = app and hs.axuielement.applicationElement(app)
  if not appEl then return fail("reach: no frontmost app") end
  appEl:setTimeout(0.15)
  -- Chromium apps (Chrome, Slack, Discord, VS Code) do not build their web content's AX tree
  -- unless a client asks. Without this the walk sees the toolbar and nothing in the page.
  pcall(function() appEl:setAttributeValue("AXManualAccessibility", true) end)
  local win = appEl:attributeValue("AXFocusedWindow") or appEl:attributeValue("AXMainWindow")
  if not win then return fail("reach: no window") end

  local screen = hs.screen.mainScreen():fullFrame()
  local began = hs.timer.secondsSinceEpoch()
  local found = gather(win, screen)
  if #found == 0 then                      -- the tree is built lazily; the first ask can beat it
    hs.timer.usleep(120000)
    found = gather(win, screen)
  end
  town.talk("work", { where = "reach:gather",
    ms = math.floor((hs.timer.secondsSinceEpoch() - began) * 1000 + 0.5), n = #found }, "past")
  if #found == 0 then return fail("reach: nothing to point at here") end

  local keys = keysFor(#found)
  hints, typed = {}, ""
  for i, f in ipairs(found) do hints[i] = { key = keys[i], frame = f.frame, element = f.element } end

  overlay = hs.canvas.new(screen)
  overlay:level(hs.canvas.windowLevels.overlay)
  overlay:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  overlay:show()
  draw()
  -- an eventtap, not a focused window: the overlay never takes focus, so the app underneath keeps
  -- it and the click lands where it would have anyway.
  tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, typedKey)
  tap:start()
  return true
end

M.stop = stop
return M
