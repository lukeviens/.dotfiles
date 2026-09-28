-- keys.lua — the keymap as town wrote it: ~/.cache/town/keys, one tab-separated line per item
-- (residents/keys.lua via lib's keymap). `hint <at> <keys> <label>` are the ? card's items for a
-- surface; `bind <key> <act> [aware]` the chords this surface binds itself. Read on demand.
local M = {}
local PATH = os.getenv("HOME") .. "/.cache/town/keys"

local function lines()
  local out, f = {}, io.open(PATH, "r")
  if not f then return out end
  for l in f:lines() do
    local t = {}
    for field in (l .. "\t"):gmatch("([^\t]*)\t") do t[#t + 1] = field end
    out[#out + 1] = t
  end
  f:close()
  return out
end

function M.hints(at)
  local items = {}
  for _, t in ipairs(lines()) do
    if t[1] == "hint" and t[2] == at then items[#items + 1] = { keys = t[3], label = t[4] } end
  end
  return items
end

function M.binds()
  local binds = {}
  for _, t in ipairs(lines()) do
    if t[1] == "bind" then binds[#binds + 1] = { key = t[2], act = t[3], aware = t[4] == "aware" } end
  end
  return binds
end

return M
