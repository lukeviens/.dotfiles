-- mode.lua — town-mode: a modal editor for the tiled desktop. Caps (→ F18 via Karabiner) is the
-- DEPTH axis — tap to enter at the inner layer, tap again to pop out toward the mac window. HOLD is
-- momentary (exits on release); esc/idle also exit. Inside, keys are swallowed EXCLUSIVELY so
-- nothing else can steal them. hjkl moves the current register (point/edge/cell) at the current
-- depth, against the innermost surface; %/" split. See town-motion-model in the notes.
local M = {}

local IDLE = 8          -- seconds of no keys before the mode auto-exits (a safety net)

local leader, idleTimer, modeOn = hs.hotkey.modal.new(), nil, false
local usedHold = false
local register = "point"             -- what hjkl grabs: point (cursor) | edge (wall) | cell (tile)
local depth, DMAX = 0, 1             -- how far OUT: 0 = inner (terminal pane), 1 = mac window (top)
local townhint                       -- the key menu, from town's keys.lua
local townmodetap                    -- the exclusive-mode eventtap (held; M.stop roots it from GC)

-- the on-screen chrome (the corner badge + the `?` reference card) lives in chrome.lua; mode hands
-- it the current register/depth and the hint items, and it renders.
local chrome = require("chrome")

local function armIdle()   -- (re)start the idle safety timer on entry and each key
  if idleTimer then idleTimer:stop() end
  idleTimer = hs.timer.doAfter(IDLE, function() M.leave() end)  -- via leave, so state stays coherent
end
function M.leave()
  if modeOn then leader:exit() end
end

-- windows: the window module (glide + resize). warm: places.list_windows (cache warm-up).
function M.start(town, windows, warm)
  -- the leader hint is town's: keys.lua decides both what the keys do and what they say.
  town.listen("hints", function(w) townhint = w.body.items; if chrome.cardShown() then chrome.showCard(townhint) end end)
  -- a picker taking the keyboard yields the mode. Its OWN show listener — the bus fans `show` out
  -- to both this and the picker glue independently, so no forward-declared leaveMode is needed.
  town.listen("show", function() M.leave() end)

  function leader:entered()
    modeOn = true
    hs.timer.doAfter(0, warm)   -- warm the window cache while you decide
    if not townhint then town.talk("hint", { at = "leader" }, "future") end
    chrome.badge("point", depth)
    chrome.showBadge()
    armIdle()
  end
  function leader:exited()
    modeOn = false
    usedHold, register, depth = false, "point", 0        -- the single convergence point: EVERY exit
    chrome.reset()                                       -- (idle, esc, picker, leave) lands here clean.
    if idleTimer then idleTimer:stop(); idleTimer = nil end
  end

  -- a mode key reports to town and KEEPS the mode open (chain-friendly). the mode leaves on a
  -- momentary Caps-release, esc, a picker opening, or going idle — a Caps TAP pops depth, not out.
  local function onKey(press)
    usedHold = true
    armIdle()
    town.talk("key", { at = "leader", press = press }, "past")
  end
  local inTerm = windows.in_term   -- "am I in the terminal?" — decided in windows (it owns the transport)
  for c in ("abfgimnopqrstvwxyz0123456789/"):gmatch(".") do   -- hjkl + e/c + d/u + %/" handled below
    leader:bind({}, c, function() onKey(c) end)
  end
  -- Caps ⏎ zooms the INNER thing: the tmux pane in the terminal (HS routes it), else maximize ↔
  -- restore the mac window (through town). Caps ⇧⏎ is the OUTER thing — the whole window big —
  -- always the mac window, so it just talks the key (see keys.lua).
  leader:bind({}, "return", function()
    usedHold = true; armIdle()
    if depth == 0 and inTerm() then windows.wez_zoom()   -- inner: zoom the pane
    else onKey("return") end                             -- outer/mac: maximize the window
  end)

  -- REGISTER: what hjkl grabs (the mesh element). point = the cursor (0D, default) → navigate;
  -- edge = a wall (1D) → resize; cell = a tile (2D) → swap. e/c arm edge/cell; the same key again,
  -- or any exit, returns to point. Only hjkl reads the register; the badge shows it.
  local function arm(reg)
    return function()
      usedHold = true; armIdle()
      register = (register == reg) and "point" or reg
      chrome.badge(register, depth)   -- point / edge / cell — same vocabulary, each its own hue
    end
  end
  leader:bind({}, "e", arm("edge"))
  leader:bind({}, "c", arm("cell"))
  leader:bind({ "shift" }, "e", arm("edge"))   -- Shift is meaningless on an arm key, so ⇧e = e:
  leader:bind({ "shift" }, "c", arm("cell"))   -- you can roll Caps+⇧+c+hjkl for e.g. cell-out in one motion

  -- hjkl moves the grabbed element against the innermost surface. In the terminal, windows.wez
  -- injects the Meta byte the transport table binds (point→select, edge→resize, cell→swap) so
  -- nvim/tmux own it and cross back to mac at the edge. In a mac app, point focuses through town
  -- and edge resizes the window; cell on mac isn't wired yet (tiling comes with the depth work).
  local MAC = { edge = windows.resize, cell = windows.snap }   -- mac verb paths; point → town-move
  -- run the register's motion at a given depth: inner + terminal injects the transport byte; else it
  -- acts on the mac window (edge resizes, point focuses through town). depth 0 = pane, 1 = window.
  local function doMotion(d, atDepth)
    if atDepth == 0 and inTerm() then windows.wez(register, d)
    elseif MAC[register] then MAC[register](d)
    elseif register == "point" then onKey(d) end
  end
  for _, d in ipairs({ "h", "j", "k", "l" }) do
    local function inner() usedHold = true; armIdle(); doMotion(d, depth) end
    local function outer() usedHold = true; armIdle(); doMotion(d, math.min(depth + 1, DMAX)) end
    leader:bind({}, d, inner, nil, inner)           -- hjkl: the current layer (press + hold-repeat)
    leader:bind({ "shift" }, d, outer, nil, outer)  -- ⇧hjkl: the SAME motion one layer OUT (Shift = outward)
  end

  -- % / " split the focused cell (left/right, top/bottom) at the current layer — a structure op,
  -- orthogonal to the register. Terminal → tmux split-window; mac tiling split comes with depth.
  local function split(dir)   -- % = lr, " = tb
    return function()
      usedHold = true; armIdle()
      if depth == 0 and inTerm() then windows.wez("split", dir) end  -- inner only (mac split later)
    end
  end
  leader:bind({ "shift" }, "5", split("lr"))   -- % → split left/right
  leader:bind({ "shift" }, "'", split("tb"))   -- " → split top/bottom

  -- Caps d / u : page down / up. You always scroll the content you're LOOKING at, so this ignores
  -- depth (unlike motion): in the terminal → the pane (vim C-f/C-b, else copy-mode); a mac app →
  -- the window. Register-independent, like split. (Depth-gating it scrolled the terminal via a mac
  -- event at outer depth — janky; scrolling isn't a layer motion.)
  local function scrollKey(dir)
    return function()
      usedHold = true; armIdle()
      if inTerm() then windows.wez("scroll", dir) else windows.scroll(dir) end
    end
  end
  leader:bind({}, "d", scrollKey("d"))
  leader:bind({}, "u", scrollKey("u"))
  leader:bind({ "shift" }, "return", function() onKey("S-return") end)
  leader:bind({ "shift" }, "t", function() onKey("T") end)   -- ⇧T → random theme
  leader:bind({ "shift" }, "/", function()   -- ? toggles the derived key card
    usedHold = true; armIdle()
    if chrome.cardShown() then chrome.hideCard()
    else town.talk("hint", { at = "leader" }, "future"); chrome.showCard(townhint) end   -- pull fresh, re-render on arrival
  end)
  leader:bind({}, "escape", function() M.leave() end)

  -- Caps (→ F18 via Karabiner) is the DEPTH axis. First press enters at the inner layer (⇧ enters
  -- at the top); each further TAP pops out one layer (wrapping), so hjkl/registers act on the pane,
  -- then the mac window. HOLD is momentary — a hold that used keys exits on release. esc/idle exit.
  townmodetap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, function(e)
    if e:getKeyCode() ~= hs.keycodes.map.f18 then
      -- exclusive mode: while it's open, swallow every keyDown that ISN'T a town-mode key
      -- (modifier chords, and any unbound key) so nothing else on the machine responds.
      -- town keys — plain a-z/0-9/// return/escape, or a shift combo (hjkl/return///t and 5/'
      -- for % ") — fall through to the modal below.
      if modeOn and e:getType() == hs.eventtap.event.types.keyDown then
        local f, c = e:getFlags(), hs.keycodes.map[e:getKeyCode()]
        local modekey   -- is this a town-mode key (falls through to the modal), or noise to swallow?
        if f.cmd or f.ctrl or f.alt or f.fn then modekey = false
        elseif f.shift then modekey = (c == "h" or c == "j" or c == "k" or c == "l" or c == "return" or c == "/" or c == "t" or c == "5" or c == "'" or c == "c" or c == "e")   -- …5/' → % "; c/e = roll-arm a register with Shift held
        else modekey = c ~= nil and (c:match("^%l$") or c:match("^%d$") or c == "/" or c == "return" or c == "escape") end
        if not modekey then return true end
      end
      return false
    end
    if e:getType() == hs.eventtap.event.types.keyDown then
      if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1 then return true end -- Caps held auto-repeats; ignore
      usedHold = false
      local shifted = e:getFlags().shift
      if not modeOn then
        depth = shifted and DMAX or 0   -- enter: inner, or ⇧ = straight to the top
        leader:enter()                  -- entered() paints the badge at this depth
      else
        depth = shifted and DMAX or (depth + 1) % (DMAX + 1)   -- tap pops out one layer (wraps); ⇧ = top
        chrome.badge(register, depth)   -- repaint the depth marker; stay in the mode
      end
    else                                -- Caps released
      if usedHold then M.leave() end    -- a hold that used keys → momentary, exit on release
      -- a clean tap (entry or depth pop) leaves the mode open; esc / idle / a picker close it
    end
    return true                         -- consume F18
  end)
  townmodetap:start()
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalues keep the eventtap + badge + modal reachable)
  if townmodetap then townmodetap:stop() end
  chrome.stop()
end

return M
