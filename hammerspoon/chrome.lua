-- chrome.lua — Chrome as a place source: report the active tab, obey a future one. Both halves,
-- so tabs ride the same trail as everything else and the tree needs no Chrome branch.
--
-- A tab is named by Chrome's `id` — stable across reordering and across windows. `tabIndex` is a
-- position to set, never an identity.
local sh = require("sh")
local M = {}

-- skipped entirely if Chrome isn't running — a bare `tell application` would launch it otherwise.
-- (ASCII character 9/10, not `tab`/`linefeed` — those bareword constants resolve to Chrome's own
-- dictionary terms inside its `tell` block, so `&`-ing them in stringifies to the literal words.)
local LIST_AS = 'tell application "Google Chrome"\n' ..
  'set out to ""\n' ..
  'repeat with w in windows\n' ..
  'set wid to id of w\n' ..
  'set i to 0\n' ..
  'repeat with t in tabs of w\n' ..
  'set i to i + 1\n' ..
  'set out to out & wid & (ASCII character 9) & (id of t) & (ASCII character 9) & i & (ASCII character 9) & (title of t) & (ASCII character 10)\n' ..
  'end repeat\n' ..
  'end repeat\n' ..
  'return out\n' ..
  'end tell'

function M.tabs(cb)
  if not hs.application.get("Google Chrome") then cb({}); return end
  sh("osascript -e '" .. LIST_AS .. "' 2>/dev/null", function(_, out)
    local places = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
      local wid, tid, idx, title = line:match("^(%d+)\t(%d+)\t(%d+)\t(.*)$")
      if wid then
        places[#places + 1] = { kind = "tab", app = "Google Chrome", title = title,
          winId = tonumber(wid), tabId = tonumber(tid), tabIndex = tonumber(idx) }
      end
    end
    cb(places)
  end)
end

-- the front window's active tab, as a place. Empty when Chrome has no window.
local ACTIVE_AS = 'tell application "Google Chrome"\n' ..
  'if (count of windows) is 0 then return ""\n' ..
  'set w to front window\n' ..
  'set t to active tab of w\n' ..
  'return (id of w) & (ASCII character 9) & (id of t) & (ASCII character 9) ' ..
  '& (active tab index of w) & (ASCII character 9) & (title of t)\n' ..
  'end tell'

function M.active(cb)
  if not hs.application.get("Google Chrome") then cb(nil); return end
  sh("osascript -e '" .. ACTIVE_AS .. "' 2>/dev/null", function(_, out)
    local wid, tid, idx, title = (out or ""):match("^(%d+)\t(%d+)\t(%d+)\t([^\r\n]*)")
    if not wid then cb(nil); return end
    cb({ kind = "tab", app = "Google Chrome", title = title,
         winId = tonumber(wid), tabId = tonumber(tid), tabIndex = tonumber(idx) })
  end)
end

-- enter a tab by id, so a tab that moved is still the same place. onMissing fires when no tab
-- carries that id: the trail drops it and walks on, as places.lua does for a closed window.
-- `as integer` — Chrome returns `id` as TEXT, so a bare `id of t is 123` is false for every tab.
-- A `whose id is …` filter coerces; a comparison inside a repeat does not.
local FIND_AS = 'tell application "Google Chrome"\n' ..
  'repeat with w in windows\n' ..
  'set i to 0\n' ..
  'repeat with t in tabs of w\n' ..
  'set i to i + 1\n' ..
  'if ((id of t) as integer) is %d then\n' ..
  'set index of w to 1\n' ..
  'set active tab index of w to i\n' ..
  'activate\n' ..
  'return "ok"\n' ..
  'end if\n' ..
  'end repeat\n' ..
  'end repeat\n' ..
  'return ""\n' ..
  'end tell'

-- a place logged before tabs carried an id: window + position, best-effort.
local AT_AS = 'tell application "Google Chrome"\n' ..
  'activate\n' ..
  'set index of (first window whose id is %d) to 1\n' ..
  'set active tab index of (first window whose id is %d) to %d\n' ..
  'end tell'

function M.activate(p, onMissing)
  if not hs.application.get("Google Chrome") then return end
  if p.tabId then
    sh(("osascript -e '" .. FIND_AS .. "' 2>/dev/null"):format(p.tabId), function(_, out)
      if not (out or ""):match("ok") and onMissing then onMissing() end
    end)
  elseif p.winId and p.tabIndex then
    sh(("osascript -e '" .. AT_AS .. "' 2>/dev/null"):format(p.winId, p.winId, p.tabIndex))
  end
end

function M.in_chrome()
  local f = hs.application.frontmostApplication()
  return f and f:name() == "Google Chrome"
end

-- Caps hjkl's depth-0 rung in Chrome: cycle the front window's active tab, wrapping.
function M.cycleTab(step)
  sh(("osascript -e 'tell application \"Google Chrome\"\n" ..
      "set w to front window\n" ..
      "set n to count of tabs of w\n" ..
      "set i to active tab index of w\n" ..
      "set i to ((i - 1 %+d + n) mod n) + 1\n" ..
      "set active tab index of w to i\n" ..
      "end tell'"):format(step))
end

return M
