-- windows.lua — mac window management: directional focus, half-screen snapping (½→⅔→⅓),
-- maximize↔restore, and binding town's keymap chords (dimming the `aware` ones inside the
-- terminal). Windows float and are managed here in HS; town routes only the cross-level `move`
-- word forwarded from the terminal's own edge.
local M = {}

local HOME = os.getenv("HOME")

local DIRS = { h = "West", j = "South", k = "North", l = "East" }
local function focus(dir)
  local w = hs.window.focusedWindow()
  if w and DIRS[dir] then w["focusWindow" .. DIRS[dir]](w) end
end

-- Nudge the FOCUSED WezTerm pane to move: send the exact bytes a physical ⌥dir would — ESC+dir,
-- i.e. Meta-dir — which tmux's `bind -n M-…` matches. (WezTerm consumes the ⌥ modifier itself and
-- only ever forwards these bytes, so there's no real keystroke to synthesize; a posted CGEvent
-- WezTerm ignores, but the bytes it can't tell from a real press.) This routes nvim splits, tmux
-- panes, and the mac-edge crossing all through the one tmux path. Async so it never blocks HS.
local WEZ = "/opt/homebrew/bin/wezterm"
local WEZ_SOCK = HOME .. "/.local/share/wezterm/default-org.wezfurlong.wezterm"  -- stable → live gui-sock
function M.wez_nav(d)   -- exposed: the Caps-mode's hjkl calls it while inside the terminal
  local pane = WEZ .. " cli list-clients --format json"
    .. " | sed -n 's/.*\"focused_pane_id\":[[:space:]]*\\([0-9]*\\).*/\\1/p' | head -1"
  local cmd = "p=$(" .. pane .. "); [ -n \"$p\" ] && printf '\\033" .. d .. "' | "
    .. WEZ .. " cli send-text --no-paste --pane-id \"$p\""
  local t = hs.task.new("/bin/sh", nil, { "-c", cmd })
  t:setEnvironment({ HOME = HOME, PATH = "/opt/homebrew/bin:/usr/bin:/bin", WEZTERM_UNIX_SOCKET = WEZ_SOCK })
  t:start()
end

-- snap the window to a fraction of a screen edge; the same edge again cycles ½ → ⅔ → ⅓.
local FRACS, snapAt = { 0.5, 2 / 3, 1 / 3 }, {}
local function snap(dir)
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

-- the whole mac keymap is declared in town's keys.lua; HS supplies these actions and binds
-- whatever town sends. "focus h"/"snap h" carry a direction; zoom/maximize don't.
local ACT = { focus = focus, zoom = maximize }   -- the only chord actions left (⌃hjkl, ⌃⏎)
local townchords, townnav = {}, {}   -- held (module-rooted via M.stop) or HS garbage-collects the hotkeys
-- `aware` chords go quiet in the terminal, where nvim/tmux own that key (and forward `move`
-- at their edge); everything else stays live everywhere.
function M.nav_mode()   -- exposed: the surface's app-watcher calls it the instant focus changes
  local front = hs.application.frontmostApplication()
  local inside = front and front:name() == "WezTerm"
  for _, hk in ipairs(townnav) do if inside then hk:disable() else hk:enable() end end
end

function M.start(town)
  town.listen("move", function(w) focus(w.body.dir) end)

  town.listen("wiring", function(w)
    for _, hk in ipairs(townchords) do hk:delete() end
    townchords, townnav = {}, {}
    for _, b in ipairs(w.body.binds or {}) do
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
  end)

  -- Caps hjkl / z arranges the focused window: halves reuse the snap cycle, z maximizes.
  town.listen("arrange", function(w)
    local halves = { left = "h", right = "l", top = "k", bottom = "j" }
    local dir = halves[w.body.to]
    if dir then snap(dir)
    elseif w.body.to == "max" then maximize()
    elseif w.body.to == "fullscreen" then
      local win = hs.window.focusedWindow(); if win then win:setFullScreen(not win:isFullScreen()) end
    end
  end)

  M.nav_mode()   -- set the initial mode
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalue keeps the chord hotkeys reachable)
  for _, hk in ipairs(townchords or {}) do pcall(function() hk:delete() end) end
end

return M
