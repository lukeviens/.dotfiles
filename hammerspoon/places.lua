-- places.lua — the facts HS reports and the places it enters. It gathers the app + window lists
-- (cached; icons resolve lazily), dresses town's raw choices with icons for the picker, reports
-- the focused thing as a present `place`, and obeys a future `place` by focusing that window.
local M = {}

local HOME = os.getenv("HOME")
local watchers = {}   -- anchor the app-dir pathwatchers (module-rooted via M.stop) so they live

-- ── apps — cached with icons; ~300 iconForFile calls shouldn't run per open ──
local APP_DIRS = {
  "/Applications", "/Applications/Utilities",
  "/System/Applications", "/System/Applications/Utilities",
  HOME .. "/Applications",
}
local app_cache
function M.list_apps(fresh)
  if fresh then app_cache = nil end          -- force a cold rebuild (the perf suite uses this)
  if app_cache then return app_cache end
  local seen, out = {}, {}
  for _, dir in ipairs(APP_DIRS) do
    if hs.fs.attributes(dir) then
      for file in hs.fs.dir(dir) do
        if file:match("%.app$") then
          local name = file:gsub("%.app$", "")
          if not seen[name] then
            seen[name] = true
            local path = dir .. "/" .. file
            out[#out + 1] = { text = name, icon = hs.image.iconForFile(path), iconKey = path, kind = "app" }
          end
        end
      end
    end
  end
  app_cache = out
  return out
end

-- ── windows — cached. one w:title() is an accessibility call (~2ms); querying every window on
-- each picker open was the lag. a window.filter invalidates the cache only when a window opens or
-- closes, so repeated opens are instant (titles can be a touch stale between structural changes —
-- fine for a picker). icons resolve at render. ──
local iconfb = {}   -- name → { image|false, key }: the AX/bundle icon lookup runs once per app, ever
local win_cache
local winfilter
function M.list_windows(fresh)
  if fresh then win_cache = nil end          -- force a cold rebuild (the perf suite uses this)
  if win_cache then return win_cache end
  local out = {}
  for _, w in ipairs(hs.window.orderedWindows()) do
    local title = w:title()
    if w:isStandard() and title ~= "" then
      local app = w:application()
      out[#out + 1] = { app = app and app:name() or "?", title = title }
    end
  end
  win_cache = out
  return out
end

-- Dress town's raw choices ({ label, id, kind, app, title }) with icons, ready for the picker.
-- An app's icon comes from the cached /Applications list (no work); anything else — a session,
-- a running app not in /Applications — is resolved once via AX/bundle and remembered in iconfb,
-- because those calls block for SECONDS under window-server load and must never run twice.
function M.decorate(raw)
  local byname = {}
  for _, a in ipairs(M.list_apps()) do byname[a.text] = a end
  local function icon(c)
    local name = (c.kind == "session") and "WezTerm" or c.app   -- sessions wear the terminal
    local a = name and byname[name]
    if a then return a.icon, a.iconKey end
    if not name then return end
    local hit = iconfb[name]
    if not hit then
      local app = hs.application.get(name)
      local bid = app and app:bundleID()
      hit = { bid and hs.image.imageFromAppBundle(bid) or false, bid }
      iconfb[name] = hit
    end
    return hit[1] or nil, hit[2]
  end
  local choices = {}
  for _, c in ipairs(raw or {}) do
    local ic, key = icon(c)
    choices[#choices + 1] = { text = c.label, id = c.id, icon = ic, iconKey = key }
  end
  return choices
end

-- the raw place lists town asks for (⌃M a / w / the universal picker's live half)
local function app_places()
  local out = {}
  for _, a in ipairs(M.list_apps()) do out[#out + 1] = { kind = "app", name = a.text } end
  return out
end
local function window_places()
  local out = {}
  for _, win in ipairs(M.list_windows()) do out[#out + 1] = { kind = "window", app = win.app, title = win.title } end
  return out
end

-- HS produces the focused thing as a present place — where you are now. For the terminal that's
-- the CURRENT tmux session (queried live), not the WezTerm window: it keeps the flip trail's idea
-- of "where you are" correct when you click into the terminal, and dedupes cleanly against a
-- session flip (same key) instead of scrambling the trail.
local TX = "/opt/homebrew/bin/tmux"
local lastapp
local town   -- set in M.start; report_front is also called by the surface's app-watcher
function M.report_front()
  local app = hs.application.frontmostApplication()
  local name = app and app:name()
  if not name or name == "Hammerspoon" or name == lastapp then return end
  lastapp = name
  if name == "WezTerm" then
    -- the attached client's session — NOT `display-message` (which answers for tmux's
    -- most-recently-active client, i.e. the wrong window). Queried ASYNC via hs.task: a blocking
    -- hs.execute here spawned a process on the UI thread on EVERY terminal focus — the exact
    -- per-event stall the persistent bus exists to prevent. Talk the place from the callback.
    local t = hs.task.new("/bin/sh", function(_, out)
      local s = out and out:match("[^\r\n]+")
      if s then town.talk("place", { kind = "session", name = s })
      else town.talk("place", { kind = "window", app = name }) end   -- no tmux → the window itself
    end, { "-c", TX .. " list-clients -F '#{client_session}' 2>/dev/null" })
    t:start()
  else
    town.talk("place", { kind = "window", app = name })
  end
end

-- tmux sessions, async (never a UI-thread spawn) — the terminal half of the picker's live list.
local function session_places(cb)
  local t = hs.task.new("/bin/sh", function(_, out)
    local places = {}
    for name in (out or ""):gmatch("[^\r\n]+") do places[#places + 1] = { kind = "session", name = name } end
    cb(places)
  end, { "-c", TX .. " list-sessions -F '#{session_name}' 2>/dev/null" })
  t:start()
end

function M.start(bus)
  town = bus

  -- app-dir pathwatchers: drop the app cache when /Applications changes (rebuilt lazily next open)
  for _, dir in ipairs({ "/Applications", HOME .. "/Applications" }) do
    if hs.fs.attributes(dir) then
      watchers[#watchers + 1] = hs.pathwatcher.new(dir, function() app_cache = nil end):start()
    end
  end

  -- window filter: invalidate the window cache only when a window opens or closes
  winfilter = hs.window.filter.new()
  winfilter:subscribe({ hs.window.filter.windowCreated, hs.window.filter.windowDestroyed },
    function() win_cache = nil end)

  -- town owns the pickers; the surface gathers the live app/window/session lists on request.
  town.listen("gather", function(w)
    local what = w.body.what
    if what == "apps" then town.talk("apps", { places = app_places() }, "past")
    elseif what == "windows" then town.talk("windows", { places = window_places() }, "past")
    elseif what == "sessions" then
      session_places(function(s) town.talk("sessions", { places = s }, "past") end)
    elseif what == "all" then                                      -- the universal picker's live half
      local all = window_places()
      for _, p in ipairs(app_places()) do all[#all + 1] = p end
      session_places(function(s)                                   -- sessions arrive async, then talk
        for _, p in ipairs(s) do all[#all + 1] = p end
        town.talk("everything", { places = all }, "past")
      end)
    end
  end)

  -- HS owns mac focus: enter a window the town means to (a future place), best-effort.
  town.listen("place", function(w)
    local p = w.body
    if w.tense ~= "future" or not (p.kind == "window" or p.kind == "app") then return end
    local a = p.app and hs.application.get(p.app)
    if not a then
      if p.app or p.name then hs.application.launchOrFocus(p.app or p.name) end
      return                                        -- not running → launch it
    end
    local wins, target = a:allWindows(), nil
    for _, win in ipairs(wins) do                   -- prefer the exact window if a title was saved
      if p.title and p.title ~= "" and win:title() == p.title then target = win; break end
    end
    target = target or wins[1]                       -- else the app's window (favourites save no title)
    if not target then
      a:activate()                                   -- running but no accessible window
    elseif target:isMinimized() then
      target:unminimize()                            -- pop it back out of the Dock, then focus
      hs.timer.doAfter(0.2, function() target:focus() end)   -- after the un-genie animation
    else
      target:focus()
    end
  end)

  return M
end

function M.stop()   -- teardown + GC anchor (its upvalues keep winfilter + the pathwatchers alive)
  if winfilter then pcall(function() winfilter:unsubscribeAll() end) end
  for _, pw in ipairs(watchers or {}) do pcall(function() pw:stop() end) end
end

return M
