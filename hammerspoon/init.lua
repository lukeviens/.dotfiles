-- ~/.config/hammerspoon/init.lua
-- HS as a town surface: it reports facts (the focused app), renders menus town shows, and obeys
-- intentions (focus a place). The thinking lives in town's residents. HS keeps what's mac's:
--   town.lua     the bus — one socket to the square; listen/talk
--   theme.lua    the palette, and what a new one does to the mac
--   picker.lua   the menu renderer (a themed webview); reports the choice
--   places.lua   app/window lists, the focus fact, obeying a future place
--   windows.lua  mac window motion + the transport into the terminal
--   mode.lua     the Caps modal: depth, registers, the exclusive eventtap
--   hud.lua      chrome: badge, toast, the ? card and its table page
--   time.lua     town's pace as a table; the hand microbench
-- This file only wires them and boots.

local town    = require("town")
local theme   = require("theme")
local picker  = require("picker")
local places  = require("places")
local windows = require("windows")
local mode    = require("mode")
local hud     = require("hud")
local time    = require("time")
local sh      = require("sh")

local HOME = os.getenv("HOME")
local watchers, townwatch, wakewatch, townwarm = {}, nil, nil, nil

-- every listener registers before the bus connects (bottom), so nothing misses the first words
theme.start(town, { sh = sh, hud = hud, picker = picker })
picker.start(town, places.decorate)
time.start(town, { places = places, picker = picker, hud = hud })
windows.start(town)
places.start(town)
mode.start(town, windows, places.list_windows)

-- focus changed → report it, and set the terminal-aware chord mode. Pull-only; no reconcile timer.
townwatch = hs.application.watcher.new(function(_, event)
  if event == hs.application.watcher.activated then
    places.report_front()
    windows.nav_mode()
  end
end)
townwatch:start()

-- waking (lid, unlock, resume) drops any UI left over from before sleep
wakewatch = hs.caffeinate.watcher.new(function(event)
  local W = hs.caffeinate.watcher
  if event == W.screensDidWake or event == W.systemDidWake or event == W.screensDidUnlock then
    picker.hide()
    mode.leave()
  end
end)
wakewatch:start()

-- reload on save, debounced: a burst of saves is one reload (a reload mid-reload strands HS)
local reloadTimer
watchers[#watchers + 1] = hs.pathwatcher.new(HOME .. "/.config/hammerspoon/", function(files)
  for _, f in ipairs(files) do
    if f:match("%.lua$") then
      if reloadTimer then reloadTimer:stop() end
      reloadTimer = hs.timer.doAfter(0.5, hs.reload)
      return
    end
  end
end):start()

-- tear down every long-lived tap and watcher on reload or quit, or each reload leaks one more
hs.shutdownCallback = function()
  mode.stop(); windows.stop(); places.stop(); picker.stop(); town.stop()
  if townwatch then townwatch:stop() end
  if wakewatch then wakewatch:stop() end
  if townwarm then townwarm:stop() end
  for _, pw in ipairs(watchers) do pcall(function() pw:stop() end) end
end

-- boot: join the square, pre-build the picker, warm its icons in the background
town.start()
picker.build()
townwarm = hs.timer.doAfter(2, function() picker.prewarm(places.list_apps()) end)

hs.alert.show("hammerspoon: loaded", hud.style{ stroke = theme.accent, text = theme.accent }, 1.2)
