-- sh.lua — spawn `/bin/sh -c` async with HOME+PATH baked in (the env every town task needs). Pass
-- `cb` for output (function(exit, stdout, stderr)), `extra` to add env vars (e.g. the wezterm sock).
-- Fire-and-forget by default; returns the hs.task if a caller wants to hold it.
local HOME = os.getenv("HOME")
local PATH = "/opt/homebrew/bin:/usr/bin:/bin"
return function(cmd, cb, extra)
  local env = { HOME = HOME, PATH = PATH }
  if extra then for k, v in pairs(extra) do env[k] = v end end
  local t = hs.task.new("/bin/sh", cb, { "-c", cmd })
  t:setEnvironment(env)
  t:start()
  return t
end
