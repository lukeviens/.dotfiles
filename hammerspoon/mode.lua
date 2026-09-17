-- mode.lua — town-mode: a modal editor for the tiled desktop. Caps (→ F18 via Karabiner) is the
-- DEPTH axis — tap to enter at the inner layer, tap again to pop out toward the mac window. HOLD is
-- momentary (exits on release); esc also exits, and stays open otherwise. Inside, keys are
-- swallowed EXCLUSIVELY so nothing else can steal them. hjkl moves the current register
-- (point/edge/cell) at the current depth, against the innermost surface; %/" split. See
-- town-motion-model in the notes.
local M = {}

local leader, modeOn = hs.hotkey.modal.new(), false
local usedHold = false
local register = "point"             -- what hjkl grabs: point (cursor) | edge (wall) | cell (tile)
-- how far OUT: 0 = inner (pane/split); in any terminal pane, 1 = a middle rung whose meaning is the
-- register's own (see ladder.plan); DMAX = the mac window. DMAX is recomputed on every Caps tap
-- (below): 2 rungs in the terminal, else 1 — same shape it's always been outside a terminal pane.
local depth, DMAX = 0, 1
local townhint                       -- the key menu, from town's keys.lua
local townmodetap                    -- the exclusive-mode eventtap (held; M.stop roots it from GC)

-- the on-screen chrome (the corner badge + the `?` reference card) lives in hud.lua; mode hands
-- it the current register/depth and the hint items, and it renders.
local hud = require("hud")
local chrome = require("chrome")   -- Chrome's own depth-0 rung: cycling its tabs (see ladder.plan)
local ladder = require("ladder")   -- the one decision: register+depth+surface → what hjkl does
local menunav = require("menunav")   -- drives an open mac menu (leader m) purely via AX, no keys
local reach = require("reach")       -- search-and-click any labeled on-screen element (leader ⇧F)

function M.leave()
  if modeOn then leader:exit() end
end

-- windows: the window module (glide + resize). warm: places.list_windows (cache warm-up).
function M.start(town, windows, warm)
  -- the leader hint is town's: keys.lua decides both what the keys do and what they say.
  town.listen("hints", function(w) townhint = w.body.items; if hud.cardShown() then hud.showCard(townhint) end end)
  -- a picker taking the keyboard yields the mode. Its OWN show listener — the bus fans `show` out
  -- to both this and the picker glue independently, so no forward-declared leaveMode is needed.
  town.listen("show", function() M.leave() end)

  -- Caps m opens the mac menu bar via AX (menunav — no synthetic keys, this system UI layer
  -- ignores those). LOCAL, not town-routed: a town round-trip is just async enough that hjkl
  -- pressed right after m could fire before `inMenu` flips, landing in the ladder instead (this
  -- was a real, confirmed bug) — same reasoning as split/scrollKey already being local-only.
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
    if not townhint then town.talk("hint", { at = "leader" }, "future") end
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
  -- ⇧F: fuzzy-search & click any labeled on-screen element. Deferred a tick — leaving the modal
  -- from inside its own key dispatch is asking for trouble (same reason plain `f` only leaves
  -- async, via town's round trip).
  leader:bind({ "shift" }, "f", function()
    usedHold = true
    hs.timer.doAfter(0, function() M.leave(); reach.open() end)
  end)
  -- Caps ⏎ zooms the INNER thing: the tmux pane in the terminal (HS routes it), else maximize ↔
  -- restore the mac window (through town). Caps ⇧⏎ skips the pane check and always goes straight
  -- to that same mac maximize (see keys.lua) — same action, just without the inner detour.
  leader:bind({}, "return", function()
    usedHold = true
    if inMenu then menunav.select(); inMenu = false; hud.badge(register, locate(depth))
    elseif depth == 0 and inTerm() then windows.wez_zoom()   -- inner: zoom the pane
    else onKey("return") end                                 -- outer/mac: maximize the window
  end)

  -- REGISTER: what hjkl grabs (the mesh element). point = the cursor (0D, default) → navigate;
  -- edge = a wall (1D) → resize; cell = a tile (2D) → swap. e/c arm edge/cell; the same key again,
  -- or any exit, returns to point. Only hjkl reads the register; the badge shows it.
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

  -- hjkl moves the grabbed element against the innermost surface — ladder.plan decides what that
  -- means (which surface owns depth 0, whether there's a middle rung, what the outer rung is);
  -- this just executes whatever it says.
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

  -- % / " split the focused cell (left/right, top/bottom) at the current layer — a structure op,
  -- orthogonal to the register. Terminal → tmux split-window; mac tiling split comes with depth.
  local function split(dir)   -- % = lr, " = tb
    return function()
      usedHold = true
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
      usedHold = true
      if inTerm() then windows.wez("scroll", dir) else windows.scroll(dir) end
    end
  end
  leader:bind({}, "d", scrollKey("d"))
  leader:bind({}, "u", scrollKey("u"))

  -- Caps o / i flip back / forward: in a vim pane it's nvim's jumplist (the transport defers there);
  -- in a shell pane the town trail (defer's fallback); in a mac app, the trail directly through town.
  local function flip(press)
    return function()
      usedHold = true
      if inTerm() then windows.wez("flip", press) else onKey(press) end
    end
  end
  leader:bind({}, "o", flip("o"))
  leader:bind({}, "i", flip("i"))
  leader:bind({ "shift" }, "return", function() onKey("S-return") end)
  leader:bind({ "shift" }, "t", function() onKey("T") end)   -- ⇧T → random theme
  leader:bind({ "shift" }, "/", function()   -- ? toggles the derived key card
    usedHold = true
    if hud.cardShown() then hud.hideCard()
    else town.talk("hint", { at = "leader" }, "future"); hud.showCard(townhint) end   -- pull fresh, re-render on arrival
  end)
  leader:bind({}, "escape", function()
    if inMenu then menunav.cancel(); inMenu = false; hud.badge(register, locate(depth))
    else M.leave() end
  end)

  -- Caps (→ F18 via Karabiner) is the DEPTH axis. First press enters at the inner layer (⇧ enters
  -- at the top); each further TAP pops out one layer (wrapping), so hjkl/registers act on the pane
  -- (or split), then — in any terminal pane — a middle rung (tmux windows for point, the tmux pane
  -- itself for edge in a vim split), then the mac window. HOLD is momentary — a hold that used keys
  -- exits on release. esc exits; otherwise the mode stays open.
  townmodetap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, function(e)
    if e:getKeyCode() ~= hs.keycodes.map.f18 then
      -- exclusive mode: while it's open, swallow every keyDown that ISN'T a town-mode key
      -- (modifier chords, and any unbound key) so nothing else on the machine responds.
      -- town keys — plain a-z/0-9/// return/escape, or a shift combo (hjkl/return///t/f and 5/'
      -- for % ") — fall through to the modal below.
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
      -- a hold that used keys → momentary, exit on release; EXCEPT mid-menu-nav, which needs
      -- several more keystrokes (hjkl, return) and would otherwise exit right after the very
      -- `Caps m` chord that opened it, orphaning the real (still open) menu with nothing tracking
      -- it — confirmed live as the actual cause of the menu desyncing between sessions.
      if usedHold and not inMenu then M.leave() end
      -- a clean tap (entry or depth pop) leaves the mode open; esc / a picker close it
    end
    return true                         -- consume F18
  end)
  townmodetap:start()
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalues keep the eventtap + badge + modal reachable)
  if townmodetap then townmodetap:stop() end
  hud.stop()
end

return M
