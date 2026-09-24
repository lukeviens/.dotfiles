-- mode.lua — town-mode: a modal editor for the tiled desktop. Caps (→ F18) taps through DEPTH
-- (inner pane → mac window); a HOLD is momentary. Keys are swallowed exclusively while open. hjkl
-- moves the current register (point/edge/cell) at the current depth. See town-motion-model.
local M = {}

local leader, modeOn = hs.hotkey.modal.new(), false
local usedHold = false
local register = "point"             -- what hjkl grabs: point (cursor) | edge (wall) | cell (tile)
local depth, DMAX = 0, 1             -- how far out; DMAX is 2 in a terminal (a middle rung), else 1
local keys = require("keys")         -- the keymap as town wrote it (~/.cache/town/keys)
local townmodetap                    -- the exclusive-mode eventtap (held; M.stop roots it from GC)

-- the on-screen chrome (the corner badge + the `?` reference card) lives in hud.lua; mode hands
-- it the current register/depth and the hint items, and it renders.
local hud = require("hud")
local time = require("time")         -- the ? card's second page: town's pace as a table
local chrome = require("chrome")   -- Chrome's own depth-0 rung: cycling its tabs (see ladder.plan)
local ladder = require("ladder")   -- the one decision: register+depth+surface → what hjkl does
local menunav = require("menunav")   -- drives an open mac menu (leader m) purely via AX, no keys
local reach = require("reach")       -- search-and-click any labeled on-screen element (leader ⇧F)

function M.leave()
  if modeOn then leader:exit() end
end

function M.start(town, windows, warm)
  town.listen("menu", function(w) if w.tense == "future" and w.body.choices then M.leave() end end)

  -- Caps m opens the mac menu bar (AX, no synthetic keys). Local, not town-routed: a round-trip
  -- is slow enough that hjkl right after m could land before `inMenu` flips (a confirmed bug).
  local inMenu = false
  local inTerm = windows.in_term   -- "am I in the terminal?" — decided in windows (it owns the transport)
  local inVim = windows.in_vim     -- "is that pane running vim?" — also windows' (it owns the transport)
  local MAC = { edge = windows.resize, cell = windows.snap }   -- ladder.plan's "mac" act, by register
  local function ctx() return { inTerm = inTerm(), inVim = inVim(), inChrome = chrome.in_chrome() } end

  -- where hjkl would currently land, for the badge — ladder.plan with no direction, just the label.
  local function locate(atDepth)
    local p = ladder.plan(register, nil, atDepth, DMAX, ctx())
    return p and p.where
  end

  function leader:entered()
    modeOn = true
    hs.timer.doAfter(0, warm)   -- warm the window cache while you decide
    hud.badge("point", locate(depth))
    hud.showBadge()
  end
  function leader:exited()
    modeOn = false
    usedHold, register, depth, inMenu = false, "point", 0, false   -- the one convergence point: EVERY exit
    hud.reset()                                                    -- (esc, picker, leave) lands here clean.
  end

  -- a mode key reports to town and KEEPS the mode open (chain-friendly). the mode leaves on a
  -- momentary Caps-release, esc, or a picker opening — a Caps TAP pops depth, not out.
  local function onKey(press)
    usedHold = true
    town.talk("key", { at = "leader", press = press }, "past")
  end
  for c in ("abfgnpqrstvwxyz0123456789/"):gmatch(".") do   -- hjkl + e/c + d/u + o/i + %/" + m handled below
    leader:bind({}, c, function() onKey(c) end)
  end
  leader:bind({}, "m", function()
    usedHold = true
    inMenu = menunav.open()
    if inMenu then hud.badge("menu") else hud.badge(register, locate(depth)) end
  end)
  -- ⇧F: fuzzy-search & click any labeled element. Deferred a tick — leaving the modal from inside
  -- its own key dispatch is asking for trouble.
  leader:bind({ "shift" }, "f", function()
    usedHold = true
    hs.timer.doAfter(0, function() M.leave(); reach.open() end)
  end)
  -- Caps ⏎: pane zoom (inner) → wezterm fullscreen (middle) → mac maximize (outer). ⇧⏎ always
  -- goes straight to mac maximize.
  leader:bind({}, "return", function()
    usedHold = true
    if inMenu then menunav.select(); inMenu = false; hud.badge(register, locate(depth))
    elseif inTerm() and depth == 0 then windows.wez("zoom", "z")  -- inner: zoom the pane
    elseif inTerm() and depth == 1 then M.leave(); windows.fullscreen()  -- middle: leave first, or our
    -- own exclusive tap (still swallowing while modeOn) eats the synthetic ⌘⏎ before WezTerm sees it
    else onKey("return") end                                       -- outer, or no terminal: mac maximize
  end)

  -- register: what hjkl grabs — point (cursor), edge (wall/resize), cell (tile/swap). e/c arm
  -- edge/cell; the same key again, or any exit, returns to point.
  local function arm(reg)
    return function()
      usedHold = true
      register = (register == reg) and "point" or reg
      hud.badge(register, locate(depth))   -- point / edge / cell — same vocabulary, each its own hue
    end
  end
  leader:bind({}, "e", arm("edge"))
  leader:bind({}, "c", arm("cell"))
  leader:bind({ "shift" }, "e", arm("edge"))   -- Shift is meaningless on an arm key, so ⇧e = e:
  leader:bind({ "shift" }, "c", arm("cell"))   -- you can roll Caps+⇧+c+hjkl for e.g. cell-out in one motion

  -- hjkl moves the grabbed element; ladder.plan decides what that means at this depth/surface.
  local MENUNAV = { h = menunav.left, j = menunav.down, k = menunav.up, l = menunav.right }
  local function doMotion(d, atDepth)
    if inMenu then MENUNAV[d](); return end
    local p = ladder.plan(register, d, atDepth, DMAX, ctx())
    if not p then return end
    if p.act == "wez" then windows.wez(p.verb, p.dir)
    elseif p.act == "chrome-cycle" then chrome.cycleTab(p.step)
    elseif p.act == "mac" then MAC[p.reg](p.dir)
    elseif p.act == "onkey" then onKey(p.dir) end
  end
  for _, d in ipairs({ "h", "j", "k", "l" }) do
    local function inner() usedHold = true; doMotion(d, depth) end
    local function outer() usedHold = true; doMotion(d, DMAX) end
    leader:bind({}, d, inner, nil, inner)           -- hjkl: the current layer (press + hold-repeat)
    leader:bind({ "shift" }, d, outer, nil, outer)  -- ⇧hjkl: the SAME motion at the OUTERMOST layer (Shift always means all the way out, here too)
  end

  -- % / " split the focused cell — a structure op, orthogonal to the register.
  local function split(dir)   -- % = lr, " = tb
    return function()
      usedHold = true
      if depth == 0 and inTerm() then windows.wez("split", dir) end  -- inner only (mac split later)
    end
  end
  leader:bind({ "shift" }, "5", split("lr"))   -- % → split left/right
  leader:bind({ "shift" }, "'", split("tb"))   -- " → split top/bottom

  -- Caps d/u: page down/up. Scrolls whatever you're looking at — register- and depth-independent,
  -- like split.
  local function scrollKey(dir)
    return function()
      usedHold = true
      if inTerm() then windows.wez("scroll", dir) else windows.scroll(dir) end
    end
  end
  leader:bind({}, "d", scrollKey("d"))
  leader:bind({}, "u", scrollKey("u"))

  -- Caps o/i walks the occupant at this depth. tmux decides whether its inner pane is
  -- vim (buffers) or a shell (sessions); one rung out names sessions directly.
  local function flip(press)
    usedHold = true
    local p = ladder.plan("flip", press, depth, DMAX, ctx())
    if p.act == "wez" then windows.wez(p.verb, p.dir)
    elseif p.act == "chrome-cycle" then chrome.cycleTab(p.step)
    else town.talk("key", { at = p.at, press = p.dir }, "past") end
  end
  leader:bind({}, "o", function() flip("o") end)
  leader:bind({}, "i", function() flip("i") end)
  leader:bind({ "shift" }, "return", function() onKey("S-return") end)
  leader:bind({ "shift" }, "t", function() onKey("T") end)   -- ⇧T → random theme
  leader:bind({ "shift" }, "/", function()   -- ? toggles the derived key card
    usedHold = true
    if hud.cardShown("time") then hud.hideCard()
    elseif hud.cardShown("keys") then hud.showTable(time.card())                       -- second page: the pace
    else hud.showCard(keys.hints("leader")) end   -- read on the press: town may have rewritten it
  end)
  leader:bind({}, "escape", function()
    if inMenu then menunav.cancel(); inMenu = false; hud.badge(register, locate(depth))
    else M.leave() end
  end)

  -- Caps is the depth axis: each tap pops out one layer (wraps), ⇧ jumps to the top. A hold that
  -- used keys exits on release; a clean tap or esc otherwise.
  townmodetap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, function(e)
    if e:getKeyCode() ~= hs.keycodes.map.f18 then
      -- exclusive: swallow every keyDown that isn't a town-mode key, so nothing else responds.
      if modeOn and e:getType() == hs.eventtap.event.types.keyDown then
        local f, c = e:getFlags(), hs.keycodes.map[e:getKeyCode()]
        local modekey   -- is this a town-mode key (falls through to the modal), or noise to swallow?
        if f.cmd or f.ctrl or f.alt or f.fn then modekey = false
        elseif f.shift then modekey = (c == "h" or c == "j" or c == "k" or c == "l" or c == "return" or c == "/" or c == "t" or c == "f" or c == "5" or c == "'" or c == "c" or c == "e")   -- …5/' → % "; c/e = roll-arm a register with Shift held; f = reach
        else modekey = c ~= nil and (c:match("^%l$") or c:match("^%d$") or c == "/" or c == "return" or c == "escape") end
        if not modekey then return true end
      end
      return false
    end
    if e:getType() == hs.eventtap.event.types.keyDown then
      if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1 then return true end -- Caps held auto-repeats; ignore
      usedHold = false
      DMAX = inTerm() and 2 or 1   -- recomputed on every tap: any terminal pane gets the middle rung
      local shifted = e:getFlags().shift
      if not modeOn then
        depth = shifted and DMAX or 0   -- enter: inner, or ⇧ = straight to the top
        leader:enter()                  -- entered() paints the badge at this depth
      else
        depth = shifted and DMAX or (depth + 1) % (DMAX + 1)   -- tap pops out one layer (wraps); ⇧ = top
        hud.badge(register, locate(depth))   -- repaint the depth marker; stay in the mode
      end
    else                                -- Caps released
      -- a hold that used keys exits on release, except mid-menu-nav (Caps m opening a menu is
      -- itself a "used key" hold — exiting right then would orphan the still-open menu).
      if usedHold and not inMenu then M.leave() end
    end
    return true                         -- consume F18
  end)
  townmodetap:start()
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalues keep the eventtap + badge + modal reachable)
  if modeOn then leader:exit() end
  if townmodetap then townmodetap:stop() end
  hud.stop()
end

return M
