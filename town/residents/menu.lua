-- menu — the UI as words. A `pick` becomes a `show`; a `chose` becomes going there;
-- a `favourite` pins the choice. town decides what to show and what a pick means; the surface
-- renders labels, reports ids, and gathers the live lists (apps/windows/sessions) on request.
-- Recent places come from town's own past. Every choice is a place, so choosing one is just
-- `place`(future) — which the owning surface obeys.
local shown = {}

local function label(p)
  if p.kind == "session" then return p.name .. "  ·  session" end
  if p.kind == "window" and p.title and p.title ~= "" then return p.app .. " — " .. p.title end
  return p.app or p.name or "?"
end

local function menu(places)          -- remember them; show labels + an icon hint (app/kind)
  shown = places
  local choices = {}
  for i, p in ipairs(places) do
    choices[i] = { id = tostring(i), label = label(p), app = p.app or p.name, kind = p.kind }
  end
  return intent("show", { choices = choices })
end

local function recent(places)        -- most-recent-first (everywhere() dedups by pkey)
  local out = {}
  for i = #places, 1, -1 do out[#out + 1] = places[i] end
  return out
end

local function pkey(p)               -- identity: titled windows differ by title; a
  if p.kind == "window" then         -- titleless window is just "the app", so it folds
    local t = p.title                -- into the app entry. others by name.
    if t and t ~= "" then return "window:" .. (p.app or "") .. ":" .. t end
    return "app:" .. (p.app or "")
  end
  return (p.kind or "") .. ":" .. (p.app or p.name or "")
end

-- the universal list: town's recent places first (where you go), then the surface's live
-- windows, apps, and sessions — deduped, order kept. one search over everything.
local function everywhere(live)
  local all = {}
  for _, p in ipairs(recent(past("place"))) do all[#all + 1] = p end
  for _, p in ipairs(live or {}) do all[#all + 1] = p end
  local out, seen = {}, {}
  for _, p in ipairs(all) do
    local k = pkey(p)
    if not seen[k] then seen[k] = true; out[#out + 1] = p end
  end
  return out
end

return react {
  on("pick", function(w) return intent("gather", { what = w.body.what }) end),   -- ask the surface
  on("apps", function(w) return menu(w.body.places or {}) end),       -- the surface gathered them
  on("windows", function(w) return menu(w.body.places or {}) end),
  on("sessions", function(w) return menu(w.body.places or {}) end),
  on("everything", function(w) return menu(everywhere(w.body.places)) end),  -- live list + town's places & sessions
  on("chose", function(w)
    local p = shown[tonumber(w.body.id)]
    if p then return intent("place", p) end
  end),
  on("favourite", function(w)
    local p = shown[tonumber(w.body.id)]
    if p then return intent("save", { slot = w.body.slot, place = p }) end
  end),
}
