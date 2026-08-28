-- mode.lua — town-mode. Caps (→ F18 via Karabiner) opens a modal you can TAP (sticky — stays
-- until you tap again or esc) or HOLD (momentary — exits the instant you release Caps). Plain
-- keys inside, swallowed EXCLUSIVELY so nothing on the OS/apps can steal them; keys keep the mode
-- open so you can chain. Each key reports to town as a `key` fact; hjkl glides across surfaces.
local theme = require("theme")
local M = {}

local IDLE = 8          -- seconds of no keys before the mode auto-exits (a safety net)
-- one in-theme alert for the on-demand key menu (`?`) — same shape the surface's `style` builds.
local ALERT = { fillColor = { hex = theme.bg, alpha = 1.0 }, strokeColor = { hex = theme.active, alpha = 1.0 },
                textColor = { hex = theme.fg, alpha = 1.0 }, strokeWidth = 2, radius = 10, textSize = 16 }

local leader, idleTimer, modeOn = hs.hotkey.modal.new(), nil, false
local sticky, usedHold, wasSticky = false, false, false
local townhint                       -- the key menu, from town's keys.lua
local townmodetap                    -- the exclusive-mode eventtap (held; M.stop roots it from GC)

-- a small floating badge (an overlay canvas, NOT the menu bar) that shows you're in the mode —
-- subtle, same spot every time. the full key menu is on-demand via `?`.
local bscr = hs.screen.primaryScreen():frame()
local townbadge = hs.canvas.new({ x = bscr.x + bscr.w - 138, y = bscr.y + 12, w = 126, h = 30 })
townbadge:appendElements(
  { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 8, yRadius = 8 },
    fillColor = { hex = theme.bg, alpha = 0.92 }, strokeColor = { hex = theme.active }, strokeWidth = 1.5 },
  { type = "text", text = "◆ town-mode", textColor = { hex = theme.active }, textSize = 13,
    textAlignment = "center", frame = { x = 0, y = 6, w = 126, h = 20 } })
townbadge:level(hs.canvas.windowLevels.overlay)

local function armIdle()   -- (re)start the idle safety timer on entry and each key
  if idleTimer then idleTimer:stop() end
  idleTimer = hs.timer.doAfter(IDLE, function() M.leave() end)  -- via leave, so state stays coherent
end
function M.leave()
  if modeOn then leader:exit() end
end

-- glide: windows.wez_nav (terminal pane motion). warm: places.list_windows (cache warm-up).
function M.start(town, glide, warm)
  -- the leader hint is town's: keys.lua decides both what the keys do and what they say.
  town.listen("hints", function(w) townhint = w.body.items end)
  -- a picker taking the keyboard yields the mode. Its OWN show listener — the bus fans `show` out
  -- to both this and the picker glue independently, so no forward-declared leaveMode is needed.
  town.listen("show", function() M.leave() end)

  function leader:entered()
    modeOn = true
    hs.timer.doAfter(0, warm)   -- warm the window cache while you decide
    if not townhint then town.talk("hint", { at = "leader" }, "future") end
    townbadge:show()
    armIdle()
  end
  function leader:exited()
    modeOn = false
    sticky, usedHold = false, false   -- the single convergence point: EVERY exit (idle, esc,
    townbadge:hide()                  -- picker, leave) lands here with coherent state.
    hs.alert.closeAll()
    if idleTimer then idleTimer:stop(); idleTimer = nil end
  end

  -- a mode key reports to town and KEEPS the mode open (chain-friendly). the mode leaves on
  -- Caps-release (hold), a Caps-tap toggle, esc, a picker opening, or going idle.
  local function onKey(press)
    usedHold = true
    armIdle()
    town.talk("key", { at = "leader", press = press }, "past")
  end
  for c in ("abcdefgimnopqrstuvwxyz0123456789/"):gmatch(".") do   -- hjkl handled below (they glide)
    leader:bind({}, c, function() onKey(c) end)
  end
  leader:bind({}, "return", function() onKey("return") end)

  -- Caps hjkl GLIDES like the old ⌃hjkl: in a mac app, focus the window that way (through town,
  -- as ever); in the terminal, nudge the focused WezTerm pane with the Meta bytes tmux expects
  -- (windows.wez_nav) so nvim/tmux own the pane motion and cross back to mac at their edge. One
  -- motion, everywhere. (Directional focus in a mac app is a no-op if no window sits that way.)
  for _, d in ipairs({ "h", "j", "k", "l" }) do
    leader:bind({}, d, function()
      usedHold = true; armIdle()
      local front = hs.application.frontmostApplication()
      if front and front:name() == "WezTerm" then
        glide(d)                                        -- terminal: bytes to tmux/nvim
      else
        onKey(d)                                        -- a mac app: town routes it to focus
      end
    end)
    leader:bind({ "shift" }, d, function() onKey(d:upper()) end)   -- ⇧hjkl snap
  end
  leader:bind({ "shift" }, "return", function() onKey("S-return") end)
  leader:bind({ "shift" }, "t", function() onKey("T") end)   -- ⇧T → random theme
  leader:bind({ "shift" }, "/", function()   -- ? shows the full key menu on demand
    usedHold = true; armIdle()
    hs.alert.closeAll()
    local m = ""
    for _, it in ipairs(townhint or {}) do m = m .. "  " .. it.keys .. "   " .. it.label .. "\n" end
    hs.alert.show(m .. "\n  esc   cancel", ALERT, 5)
  end)
  leader:bind({}, "escape", function() M.leave() end)

  -- Caps (→ F18 via Karabiner): TAP toggles sticky, HOLD is momentary (exits on release).
  townmodetap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, function(e)
    if e:getKeyCode() ~= hs.keycodes.map.f18 then
      -- exclusive mode: while it's open, swallow every keyDown that ISN'T a town-mode key
      -- (modifier chords, and any unbound key) so nothing else on the machine responds.
      -- town keys — plain a-z/0-9/// return/escape, or shift+hjkl/return/// — fall through
      -- to the modal below.
      if modeOn and e:getType() == hs.eventtap.event.types.keyDown then
        local f, c = e:getFlags(), hs.keycodes.map[e:getKeyCode()]
        local modekey   -- is this a town-mode key (falls through to the modal), or noise to swallow?
        if f.cmd or f.ctrl or f.alt or f.fn then modekey = false
        elseif f.shift then modekey = (c == "h" or c == "j" or c == "k" or c == "l" or c == "return" or c == "/" or c == "t")
        else modekey = c ~= nil and (c:match("^%l$") or c:match("^%d$") or c == "/" or c == "return" or c == "escape") end
        if not modekey then return true end
      end
      return false
    end
    if e:getType() == hs.eventtap.event.types.keyDown then
      if e:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1 then return true end -- Caps held auto-repeats; ignore
      wasSticky = modeOn and sticky   -- was it already toggled-on before this press?
      usedHold = false
      if not modeOn then leader:enter() end
    else                              -- Caps released
      if usedHold or wasSticky then M.leave()   -- held + used, or a tap while sticky → leave
      elseif modeOn then sticky = true end         -- a clean tap from off → sticky, stay
      -- (if modeOn is already false here, the mode was torn down mid-hold, e.g. by idle — do nothing)
    end
    return true                       -- consume F18
  end)
  townmodetap:start()
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalues keep the eventtap + badge + modal reachable)
  if townmodetap then townmodetap:stop() end
  if townbadge then pcall(function() townbadge:delete() end) end
end

return M
