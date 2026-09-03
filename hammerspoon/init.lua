-- ~/.config/hammerspoon/init.lua
-- HS as a town surface: it reports facts (the focused app), renders menus town shows,
-- and obeys intentions (focus a place). The thinking — pickers, favourites, actions —
-- lives in town's residents. HS keeps only what's mac's: the app/window lists, the
-- webview renderer, and the ⌃M leader that talks words.
--   theme.lua    the palette (same file wezterm reads)
--   picker.lua   a themed webview overlay — the renderer: {choices, onSelect, onFavourite}

local theme   = require("theme")
local picker  = require("picker")
local perf    = require("perf")
local windows = require("windows")   -- mac window management + chord-binding
local places  = require("places")    -- app/window lists, decorate, focus report + obey
local mode    = require("mode")      -- the Caps town-mode (modal + exclusive eventtap)
local sh      = require("sh")         -- spawn /bin/sh async with HOME+PATH baked in
local function color(hex) return { hex = hex, alpha = 1.0 } end

-- one in-theme alert style: always a bg fill + a palette stroke; the rest defaults
local function style(o)
  return {
    fillColor = color(theme.bg), strokeColor = color(o.stroke),
    textColor = color(o.text or theme.fg),
    strokeWidth = o.sw or 2, radius = o.radius or 8, textSize = o.size or 14,
  }
end

-- a small, in-theme toast (the raw hs.alert is huge and off-palette)
local function toast(msg)
  hs.alert.closeAll()
  hs.alert.show(msg, style{ stroke = theme.accent, sw = 1, size = 13 }, 0.7)
end

local HOME     = os.getenv("HOME")
local watchers = {}   -- anchor pathwatchers so they aren't garbage-collected

-- apps, windows, decorate, focus report + obey all live in places.lua (started below).
local last_raw = {}   -- the most recent pick's raw choices, so perf can replay a real one

-- ── town: HS reports facts and obeys intentions; town does the thinking. The bus — one
-- persistent, self-reconnecting socket to the square — lives in town.lua; here we just listen/talk.
-- (Started at the very bottom, after every listener below is registered.)
local town = require("town")

-- HS's theme applies to its own UI. Only the palette FACT — a future `theme` is the cycle
-- intention (Caps t), meant for the theme resident, not a palette to apply here.
local lastMode
town.listen("theme", function(w)
  if w.tense == "future" then return end
  local changed = false
  for k, v in pairs(w.body) do if theme[k] ~= v then theme[k] = v; changed = true end end
  if changed then
    toast("theme ↻")
    -- repaint any live interactive zsh prompts that registered themselves (see .zshrc): SIGUSR1
    -- fires their TRAPUSR1, which re-reads the palette and redraws. We only signal a pid that IS a
    -- live zsh (guards against PID reuse) and rm any stale registration as we pass it. Async.
    sh('d="$HOME/.cache/town/shells"; [ -d "$d" ] || exit 0; for f in "$d"/*; do [ -e "$f" ] || continue; ' ..
      'p=${f##*/}; case "$(ps -p "$p" -o comm= 2>/dev/null)" in *zsh) kill -USR1 "$p" 2>/dev/null;; *) rm -f "$f";; esac; done')
  end
  picker.theme(w.body)   -- recolour the live picker webview (Caps f)
  -- and flip the whole Mac: macOS light/dark follows the palette's mode (only when it changes,
  -- so dark→black or sun→light don't needlessly re-flip the whole system).
  if w.body.mode and w.body.mode ~= lastMode then
    lastMode = w.body.mode
    local dark = w.body.mode ~= "light"
    hs.task.new("/usr/bin/osascript", nil, { "-e",
      'tell application "System Events" to tell appearance preferences to set dark mode to ' .. tostring(dark) }):start()
    -- Claude Code follows too: flip it to the matching ANSI theme so it rides the terminal palette
    -- town themes. Atomic + preserves the rest of settings.json; no-op if jq or the file is absent.
    local ctheme = dark and "dark-ansi" or "light-ansi"
    sh('s="$HOME/.claude/settings.json"; command -v jq >/dev/null 2>&1 || exit 0; [ -f "$s" ] || exit 0; ' ..
      'tmp=$(mktemp) && jq --arg v "' .. ctheme .. '" \'.theme = $v\' "$s" > "$tmp" && mv "$tmp" "$s"')
  end
end)

-- HS renders any menu town shows and reports the choice (or favourite). It knows nothing of
-- what the menu is or what a pick means — town decides both. (mode.lua has its own `show`
-- listener to yield the keyboard, so nothing is forward-declared here.)
town.listen("show", function(w)
  last_raw = w.body.choices or {}
  picker.show({ placeholder = "go", choices = places.decorate(last_raw),
    onSelect    = function(c) town.talk("chose", { id = c.id }, "past") end,
    onFavourite = function(c, slot) town.talk("favourite", { slot = slot, id = c.id }, "future") end })
end)

-- perf: measuring is a word. `town talk future perf` runs the facet suite and diffs it
-- against the saved baseline; `perf what=baseline` saves the current run as the baseline.
-- Facets are the synchronous costs that freeze HS if they balloon; the verdict watches the tail.
local function perf_suite()
  local raw = (#last_raw > 0) and last_raw or (function()   -- replay a real pick, else synthesize one
    local r = {}
    for _, win in ipairs(places.list_windows()) do r[#r + 1] = { label = win.title, id = win.app, kind = "window", app = win.app } end
    if #r == 0 then for _, a in ipairs(places.list_apps()) do r[#r + 1] = { label = a.text, id = a.text, kind = "app", app = a.text } end end
    return r
  end)()
  local popts = { placeholder = "go", choices = places.decorate(raw), onSelect = function() end }
  return {
    { name = "apps.warm",         run = function() places.list_apps() end },
    { name = "apps.cold",         run = function() places.list_apps(true) end, reps = 5 },
    { name = "windows.warm",      run = function() places.list_windows() end },
    { name = "windows.cold",      run = function() places.list_windows(true) end, reps = 5 },
    { name = "icons.decorate",    run = function() places.decorate(raw) end },
    { name = "picker.open.delta", before = function() picker.show(popts) end,  -- repeat while up (spam path)
      run = function() picker.show(popts) end, after = function() picker.hide() end },
    { name = "picker.open.fresh", run = function() picker.hide(); picker.show(popts) end, reps = 3 },
  }
end

town.listen("perf", function(w)
  local ok, res = pcall(function()
    local now = perf.run(perf_suite())
    picker.hide()                                 -- the suite leaves it up; put it away
    local text, worst
    if w.body and w.body.what == "baseline" then
      perf.save(now); text = "baseline saved.\n\n" .. (perf.report(now, now))
    else
      text, worst = perf.report(now, perf.load())
    end
    perf.write(text)
    return worst or "baseline"
  end)
  if ok then toast("perf → " .. res)
  else perf.write("perf ERROR:\n" .. tostring(res)); toast("perf error (see report)") end
end)

-- windows + places register their own listeners (move/wiring/arrange; gather/place-obey) and
-- own their state. windows also sets the initial terminal-aware chord mode.
windows.start(town)
places.start(town)

-- eventful: report focus + set the nav mode the instant focus changes. No reconcile timer:
-- focus is pull-only and self-heals on the next switch. (Cross-cutting, so it lives here and
-- calls into both modules — places' focus report + windows' terminal-aware chord toggle.)
townwatch = hs.application.watcher.new(function(_, event)
  if event == hs.application.watcher.activated then
    places.report_front()
    windows.nav_mode()
  end
end)
townwatch:start()

-- town-mode: the Caps modal + its exclusive eventtap + the on-screen badge live in mode.lua.
-- It needs the terminal-glide (windows) and the window-cache warm-up (places) injected.
mode.start(town, windows, places.list_windows)

-- ── reload on save (nvim-style DX) — DEBOUNCED. A burst of saves (editing several files
-- at once) must coalesce into ONE reload: firing hs.reload() per-save interrupts a reload
-- mid-flight and strands HS before it re-registers this very watcher. Wait for the dust.
local reloadTimer
watchers[#watchers + 1] = hs.pathwatcher.new(HOME .. "/.config/hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      if reloadTimer then reloadTimer:stop() end
      reloadTimer = hs.timer.doAfter(0.5, hs.reload)   -- 0.5s after the LAST change, reload once
      return
    end
  end
end):start()

-- tear down the long-lived taps/watchers on reload or quit — otherwise each reload leaks
-- another eventtap/watcher and every keystroke gets processed N times (HS grinds to a crawl).
hs.shutdownCallback = function()
  mode.stop()      -- the Caps eventtap + badge
  windows.stop()   -- the chord hotkeys
  places.stop()    -- window.filter subscription + app-dir pathwatchers
  town.stop()      -- the bus: heartbeat + socket
  if townwatch then townwatch:stop() end   -- the cross-cutting app-activation watcher (orchestrator's)
  if townwarm then townwarm:stop() end     -- the 2s prewarm timer, if a reload beat it
  for _, pw in ipairs(watchers or {}) do pcall(function() pw:stop() end) end -- the reload pathwatcher
end

-- boot: connect to town (every listener above is now registered, so nothing misses the first
-- hint/wire), then pre-build the picker webview + warm its icon cache in the background so the
-- first ⌃M f / Caps f opens instantly instead of paying webview-creation + icon-encoding then.
town.start()
picker.build()
townwarm = hs.timer.doAfter(2, function() picker.prewarm(places.list_apps()) end)  -- global, or GC'd before it fires

hs.alert.show("hammerspoon: loaded", style{ stroke = theme.accent, text = theme.accent }, 1.2)
