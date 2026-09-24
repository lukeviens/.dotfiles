-- place — one recent-place history, with a cursor per depth's kind. The universal
-- trail still serves callers that ask to walk all places; window and session flips
-- do not move each other's cursor.
local function id(p)
  local id = (p.kind or "") .. ":" .. (p.app or p.name or "")
  if p.kind == "window" then return id .. ":" .. tostring(p.winId or p.title or "") end
  return id
end

local all = trail("place", id)
local byKind = {}
local active = all
local function kindTrail(kind)
  if not byKind[kind] then byKind[kind] = trail("place", id) end
  return byKind[kind]
end

return {
  listen = { "place" },
  talk = function(w)
    local b = w.body or {}
    if w.tense == "future" then
      if tonumber(b.step) then
        active = b.kind and kindTrail(b.kind) or all
        return active.talk(w)
      end
      return -- a named future place is for its surface to enter
    end
    local whole = all.talk(w)
    local kind = b.kind and kindTrail(b.kind)
    local part = kind and kind.talk(w)
    if active == all then return whole end
    if active == kind then return part end
  end,
}
