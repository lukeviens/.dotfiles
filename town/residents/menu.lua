-- menu — one noun, three tenses. Future by `what`: wished for; answered at once from the `places`
-- index with a future by `choices`, which the surface shows — and again when the surface refreshes
-- the index under it. Present: it's up. Past { id?, slot? }: how it ended — go there, pin it, or
-- nothing. Recent places come from town's own past. Every choice also carries `uses` — times
-- you've picked exactly that place — so a fuzzy tie in the picker breaks by habit, not alphabet
-- ("we" → WezTerm, not Weather); kept in a file, not a present fact — nothing else reads it.
local USAGE = os.getenv("HOME") .. "/.cache/town/usage"
local shown = {}
local wanted            -- the `what` of the menu currently wished for, or nil

local function label(p)
  if p.kind == "session" then return p.name .. "  ·  session" end
  if p.kind == "tab" then return p.title .. "  ·  tab" end
  if p.kind == "window" and p.title and p.title ~= "" then return p.app .. " — " .. p.title end
  return p.app or p.name or "?"
end

local function pkey(p)               -- identity: titled windows differ by title; a
  if p.kind == "window" then         -- titleless window is just "the app", so it folds
    local t = p.title                -- into the app entry. others by name.
    if t and t ~= "" then return "window:" .. (p.app or "") .. ":" .. t end
    return "app:" .. (p.app or "")
  end
  if p.kind == "tab" then return "tab:" .. tostring(p.winId) .. ":" .. tostring(p.tabIndex) end
  return (p.kind or "") .. ":" .. (p.app or p.name or "")
end

local function loadUsage()          -- pkey -> times chosen, from the tab-separated usage file
  local t = {}
  for line in (slurp(USAGE) or ""):gmatch("[^\r\n]+") do
    local k, n = line:match("^(.-)\t(%d+)$")
    if k then t[k] = tonumber(n) end
  end
  return t
end

local function bump(p)              -- one more pick of p — read, increment, rewrite whole file
  local t = loadUsage()
  local k = pkey(p):gsub("\t", " ")
  t[k] = (t[k] or 0) + 1
  local lines = {}
  for key, n in pairs(t) do lines[#lines + 1] = key .. "\t" .. n .. "\n" end
  emit(USAGE, table.concat(lines))
end

local function menu(places)          -- remember them; the menu by its choices: labels + an icon hint
  shown = places
  local usage = loadUsage()
  local choices = {}
  for i, p in ipairs(places) do
    choices[i] = { id = tostring(i), label = label(p), app = p.app or p.name, kind = p.kind,
      uses = usage[pkey(p)] or 0 }
  end
  return intent("menu", { choices = choices })
end

local function recent(places)        -- most-recent-first (everywhere() dedups by pkey)
  local out = {}
  for i = #places, 1, -1 do out[#out + 1] = places[i] end
  return out
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

local function select(what, places)  -- the index, cut to `what`; `all` puts town's recent places in front
  if what == "all" then return everywhere(places) end
  local kind = ({ apps = "app", windows = "window", sessions = "session" })[what]
  local out = {}
  for _, p in ipairs(places or {}) do if p.kind == kind then out[#out + 1] = p end end
  return out
end

return react {
  on({ kind = "menu", tense = "future", by = "what" }, function(w)
    wanted = w.body.what
    local index = present("places")
    if index and index.places then return menu(select(wanted, index.places)) end   -- else the refresh answers
  end),
  on({ kind = "places", tense = "present" }, function(w)
    if wanted then return menu(select(wanted, (w.body or {}).places)) end
  end),
  on({ kind = "menu", tense = "past" }, function(w)
    wanted = nil
    local p = shown[tonumber(w.body.id)]
    if not p then return end
    if w.body.slot then return intent("favourites", { slot = w.body.slot, place = p }) end
    bump(p)
    return intent("place", p)
  end),
}
