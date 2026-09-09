-- chrome.lua — Google Chrome as a place source: gathers open tabs for the picker (places.lua folds
-- them into the universal list) and activates one by window id + in-window tab index.
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
  'set out to out & wid & (ASCII character 9) & i & (ASCII character 9) & (title of t) & (ASCII character 10)\n' ..
  'end repeat\n' ..
  'end repeat\n' ..
  'return out\n' ..
  'end tell'

function M.tabs(cb)
  if not hs.application.get("Google Chrome") then cb({}); return end
  sh("osascript -e '" .. LIST_AS .. "' 2>/dev/null", function(_, out)
    local places = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
      local wid, idx, title = line:match("^(%d+)\t(%d+)\t(.*)$")
      if wid then
        places[#places + 1] = { kind = "tab", app = "Google Chrome", title = title,
          winId = tonumber(wid), tabIndex = tonumber(idx) }
      end
    end
    cb(places)
  end)
end

function M.activate(winId, tabIndex)
  sh(("osascript -e 'tell application \"Google Chrome\"\n" ..
      "activate\n" ..
      "set index of (first window whose id is %d) to 1\n" ..
      "set active tab index of (first window whose id is %d) to %d\n" ..
      "end tell'"):format(winId, winId, tabIndex))
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
