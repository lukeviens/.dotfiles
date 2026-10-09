-- sh.lua — spawn `/bin/sh -c` async with HOME+PATH baked in (the env every town task needs). Pass
-- `cb` for output (function(exit, stdout, stderr)), `extra` to add env vars (e.g. the wezterm sock).
-- Fire-and-forget by default; returns the hs.task if a caller wants to hold it.
-- Every command is said, as a past `work` {where, ms}; residents/work.lua folds them. Async work
-- neither blocks nor errors, so nothing else counts it.
local town = require("town")
local HOME = os.getenv("HOME")
local PATH = "/opt/homebrew/bin:/usr/bin:/bin"

-- by call site, not command: osascript runs from four places at four costs, and a one-liner's
-- first token is as often `for` or an assignment as a binary.
local function where()
  local i = debug.getinfo(3, "Sl")
  if not i then return "?" end
  return (i.short_src:match("([^/]+)$") or i.short_src) .. ":" .. (i.currentline or 0)
end

return function(cmd, cb, extra)
  local env = { HOME = HOME, PATH = PATH }
  if extra then for k, v in pairs(extra) do env[k] = v end end
  local began, site = hs.timer.secondsSinceEpoch(), where()
  local t = hs.task.new("/bin/sh", function(code, out, err)
    town.talk("work", { where = site, ms = math.floor((hs.timer.secondsSinceEpoch() - began) * 1000 + 0.5) }, "past")
    if cb then cb(code, out, err) end
  end, { "-c", cmd })
  t:setEnvironment(env)
  t:start()
  return t
end
