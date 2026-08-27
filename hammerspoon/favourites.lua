-- favourites.lua — persistent number slots (the favourites store). PURE storage:
-- slot -> opaque target table. init.lua owns what a target means (KINDS) and how
-- to activate it. Persisted as visible JSON so you can inspect/edit it by hand.
local M = {}
local PATH = os.getenv("HOME") .. "/.config/hammerspoon/favourites.json"

-- Slot keys normalize to an integer string. JSON numbers arrive as Lua floats
-- (slot 1 → "1.0"), so without this a write ("1.0") and a read ("1") mismatch.
local function key(s)
  local n = tonumber(s)
  n = n and math.tointeger(n)
  return n and tostring(n) or tostring(s)
end

local raw   = hs.json.read(PATH) or {}
local slots = {}
for k, v in pairs(raw) do slots[key(k)] = v end   -- migrate any legacy "1.0" keys

local function save() hs.json.write(slots, PATH, true, true) end   -- prettyprint, replace

function M.set(slot, target) slots[key(slot)] = target; save() end
function M.get(slot)         return slots[key(slot)] end
function M.clear(slot)       slots[key(slot)] = nil; save() end

return M
