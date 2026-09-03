-- windows.lua — mac window management: directional focus, grow/shrink (edge), snap-to-half (cell),
-- maximize↔restore, the transport byte-injection (wez), and binding town's one keymap chord (⌃⏎,
-- dimmed inside the terminal). Windows float and are managed here in HS; town routes only the
-- cross-level `move` word forwarded from the terminal's own edge.
local M = {}
local sh = require("sh")

local HOME = os.getenv("HOME")

-- is the terminal frontmost? the one place "which terminal am I" is decided (mode + the app-watcher
-- both ask here). windows owns it because it owns the terminal transport.
function M.in_term()
  local f = hs.application.frontmostApplication()
  return f and f:name() == "WezTerm"
end

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
local function send_bytes(seq)   -- inject a raw escape sequence into the focused WezTerm pane
  local pane = WEZ .. " cli list-clients --format json"
    .. " | sed -n 's/.*\"focused_pane_id\":[[:space:]]*\\([0-9]*\\).*/\\1/p' | head -1"
  local cmd = "p=$(" .. pane .. "); [ -n \"$p\" ] && printf '" .. seq .. "' | "
    .. WEZ .. " cli send-text --no-paste --pane-id \"$p\""
  sh(cmd, nil, { WEZTERM_UNIX_SOCKET = WEZ_SOCK })
end

-- the transport manifest town generates (residents/transport.lua): (verb dir) → the tmux key HS
-- must inject. ONE source — so the byte here and the tmux bind can never drift. See town-motion-model.
local T = {}
do
  local f = io.open(HOME .. "/.cache/town/transport", "r")
  if f then
    for line in f:lines() do
      local verb, dir, key = line:match("^(%S+)%s+(%S+)%s+(%S+)$")
      if verb then T[verb] = T[verb] or {}; T[verb][dir] = key end
    end
    f:close()
  end
end

-- a tmux key name (M-… / M-C-… / M-%) → the printf octal bytes to inject: ESC for Meta, then the
-- base char (a C-x control byte, else the literal char) as \NNN octal so printf never meets a %.
local function keyBytes(key)
  local body = key:gsub("^M%-", "")
  local ctrl = body:match("^C%-(.)$")
  local b = ctrl and (ctrl:lower():byte() - 96) or body:byte()
  return ("\\033\\%03o"):format(b)
end

-- the ONE entry point mode.lua drives: inject the transport key for (verb, dir) into the terminal.
function M.wez(verb, dir)
  local key = T[verb] and T[verb][dir]
  if key then send_bytes(keyBytes(key)) end
end
function M.wez_zoom() send_bytes("\\033[13;5u") end   -- ⏎ → resize-pane -Z (the ⌃⏎ User0 key)

-- scroll the focused mac window a page (the `scroll` verb's mac path — a mac app, not the terminal).
function M.scroll(dir)
  local n = (dir == "d") and -12 or 12   -- lines ≈ a half-page; down = content up
  hs.eventtap.event.newScrollEvent({ 0, n }, {}, "line"):post()
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
function M.resize(d)
  local w = hs.window.focusedWindow(); if not w then return end
  local f = w:frame()
  if d == "l" then f.w = f.w + STEP
  elseif d == "h" then f.w = math.max(240, f.w - STEP)
  elseif d == "j" then f.h = f.h + STEP
  elseif d == "k" then f.h = math.max(160, f.h - STEP) end
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
-- `aware` chords go quiet in the terminal, where nvim/tmux own that key (and forward `move`
-- at their edge); everything else stays live everywhere.
function M.nav_mode()   -- exposed: the surface's app-watcher calls it the instant focus changes
  local inside = M.in_term()
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

  -- arrange the focused window — `max` maximizes ↔ restores (Caps ⏎ / ⇧⏎, and the ⌃⏎ chord).
  town.listen("arrange", function(w)
    if w.body.to == "max" then maximize() end
  end)

  M.nav_mode()   -- set the initial mode
  return M
end

function M.stop()   -- teardown + GC anchor (its upvalue keeps the chord hotkeys reachable)
  for _, hk in ipairs(townchords or {}) do pcall(function() hk:delete() end) end
end

return M
