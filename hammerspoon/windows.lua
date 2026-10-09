-- windows.lua — mac window management: directional focus, grow/shrink (edge), snap-to-half (cell),
-- maximize↔restore, and binding town's one keymap chord (⌃⏎, dimmed inside the terminal). Windows
-- float and are managed here in HS; town routes `move` (Caps hjkl's outermost rung) and `arrange`;
-- `vim` tells the chords when the terminal owns the key. Motions inside the terminal are not HS's
-- any more — town says them to tmux over the connection it holds.
local M = {}

local HOME = os.getenv("HOME")
local town                -- set in M.start

-- is the terminal frontmost? the one place "which terminal am I" is decided (mode + the app-watcher
-- both ask here). windows owns it because it owns the terminal transport.
function M.in_term()
  local f = hs.application.frontmostApplication()
  return f and f:name() == "WezTerm"
end

-- is the focused tmux pane running vim? pushed by tmux's after-select-pane hook and nvim's own
-- VimEnter/VimLeave — word bodies are strings over the wire, so an explicit compare, not truthy.
local vimActive = false
function M.in_vim() return vimActive end

local DIRS = { h = "West", j = "South", k = "North", l = "East" }
local function focus(dir)
  local w = hs.window.focusedWindow()
  if w and DIRS[dir] then w["focusWindow" .. DIRS[dir]](w, nil, true, true) end
end

-- the middle rung, in a terminal: WezTerm's own fullscreen (edge-to-edge, no macOS Space, no
-- animation) — distinct from maximize(), and faster than the OS-level AXFullScreen toggle since
-- it skips the Spaces transition entirely. A real synthetic keystroke, not a byte injection: the
-- ⌘⏎ binding is a native WezTerm action (see wezterm.lua) and only fires on an actual key event.
function M.fullscreen()
  hs.eventtap.keyStroke({ "cmd" }, "return", 0)
end

-- scroll the focused mac window a page (the `scroll` verb's mac path — a mac app, not the terminal).
-- A scroll event has no notion of "focus" — the OS routes it by the event's own location, which
-- defaults to wherever the cursor physically is. Target the focused window's own frame instead,
-- so scrolling follows keyboard focus like everything else in Caps-mode, not the mouse.
function M.scroll(dir)
  local n = (dir == "d") and -12 or 12   -- lines ≈ a half-page; down = content up
  local ev = hs.eventtap.event.newScrollEvent({ 0, n }, {}, "line")
  local w = hs.window.focusedWindow()
  if w then
    local f = w:frame()
    ev:location({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
  end
  ev:post()
end

-- maximize ↔ restore the focused mac window.
local restoreTo = {}
local function maximize()
  local w = hs.window.focusedWindow(); if not w then return end
  local id, sf, f = w:id(), w:screen():frame(), w:frame()
  local maxed = math.abs(f.x - sf.x) < 2 and math.abs(f.y - sf.y) < 2
            and math.abs(f.w - sf.w) < 2 and math.abs(f.h - sf.h) < 2
  if maxed then                                    -- already full → restore (if we have one)
    if restoreTo[id] then w:setFrame(restoreTo[id]) end
    restoreTo[id] = nil
  else                                             -- otherwise maximize, remembering where we were
    restoreTo[id] = f
    w:setFrame(sf)
  end
end

-- grow/shrink the focused mac window (top-left anchored) — the `edge` register's mac path (Caps e + hjkl).
local STEP = 60
function M.resize(dir)
  local w = hs.window.focusedWindow(); if not w then return end
  local f = w:frame()
  if dir == "l" then f.w = f.w + STEP
  elseif dir == "h" then f.w = math.max(240, f.w - STEP)
  elseif dir == "j" then f.h = f.h + STEP
  elseif dir == "k" then f.h = math.max(160, f.h - STEP) end
  w:setFrame(f)
end

-- snap the focused window to a screen half — the `cell` register's mac path (Caps c + hjkl):
-- "position the tile." Same direction again cycles ½ → ⅔ → ⅓. This is the Rectangle-style tiling;
-- cell means swap-pane in the terminal, snap-to-region on the floating mac.
local FRACS, snapAt = { 0.5, 2 / 3, 1 / 3 }, {}
function M.snap(dir)
  local w = hs.window.focusedWindow(); if not w then return end
  local s, id = w:screen():frame(), w:id()
  local step = (snapAt[id] and snapAt[id].dir == dir) and snapAt[id].step % #FRACS + 1 or 1
  snapAt[id] = { dir = dir, step = step }
  local f, r = FRACS[step], { x = s.x, y = s.y, w = s.w, h = s.h }
  if dir == "h" then r.w = s.w * f
  elseif dir == "l" then r.w = s.w * f; r.x = s.x + s.w - r.w
  elseif dir == "k" then r.h = s.h * f
  elseif dir == "j" then r.h = s.h * f; r.y = s.y + s.h - r.h end
  w:setFrame(r)
end

-- town's keymap declares the one remaining direct chord (⌃⏎ zoom); HS supplies the action and
-- binds it. zoom/maximize carry no direction.
local ACT = { zoom = maximize }   -- the only direct chord left: ⌃⏎ (mac max; tmux zooms the pane)
local townchords, townnav = {}, {}   -- held (module-rooted via M.stop) or HS garbage-collects the hotkeys
local keyswatch                      -- rebinds the chords when town rewrites ~/.cache/town/keys
-- `aware` chords go quiet in the terminal, where nvim/tmux own that key; the rest stay live.
function M.nav_mode()   -- exposed: the surface's app-watcher calls it the instant focus changes
  local inside = M.in_term()
  for _, hk in ipairs(townnav) do if inside then hk:disable() else hk:enable() end end
end

function M.start(bus)
  town = bus
  town.listen("move", function(w) focus(w.body.dir) end)
  town.listen("vim", function(w) vimActive = (w.body.active == "1") end)

  -- the chords the surface binds itself, from the keymap's substrate — rebound whenever town rewrites it
  local function wire()
    for _, hk in ipairs(townchords) do hk:delete() end
    townchords, townnav = {}, {}
    for _, b in ipairs(require("keys").binds()) do
      local mods = {}
      for tok in b.key:gmatch("%S+") do mods[#mods + 1] = tok end
      local key = table.remove(mods)                 -- last token is the key; the rest are mods
      local verb, arg = b.act:match("^(%S+)%s*(.*)$")
      local fn = ACT[verb]
      if fn then
        local hk = hs.hotkey.new(mods, key, function() fn(arg) end)
        townchords[#townchords + 1] = hk             -- held from GC
        if b.aware then townnav[#townnav + 1] = hk else hk:enable() end   -- aware → off in the terminal
      end
    end
    M.nav_mode()
  end
  wire()
  keyswatch = hs.pathwatcher.new(HOME .. "/.cache/town/keys", wire):start()

  -- arrange the focused window — `max` maximizes ↔ restores (Caps ⏎ / ⇧⏎, and the ⌃⏎ chord).
  town.listen("arrange", function(w)
    if w.body.to == "max" then maximize() end
  end)

  M.nav_mode()   -- set the initial mode
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalue keeps the chord hotkeys reachable)
  for _, hk in ipairs(townchords or {}) do pcall(function() hk:delete() end) end
  if keyswatch then pcall(function() keyswatch:stop() end) end
end

return M
