-- lib — the composition vocabulary. Loaded before the residents, so they can be
-- written as intentions, maps, and trails rather than raw folds.

-- the three tenses, one constructor each, so no resident hand-types a `tense` string (a typo'd
-- tense silently deserializes to nothing). intent = future, fact = present, event = past.
-- (`label` on intent is hint-only, ignored when talked.)
function intent(kind, body, label) return { kind = kind, tense = "future",  body = body, label = label } end
function fact(kind, body)          return { kind = kind, tense = "present", body = body } end
function event(kind, body)         return { kind = kind, tense = "past",    body = body } end

-- palette(text): parse the shared colours file (key=value, # comments) into a table. theme + k9s
-- both use this; other surfaces parse it in their own runtimes.
function palette(text)
  local c = {}
  for line in text:gmatch("[^\r\n]+") do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k and v and v ~= "" then c[k] = v end
  end
  return c
end

-- file helpers for the "surface reads a substrate town writes" shape (theme, k9s): read a whole file
-- (nil if absent), write one best-effort, and regenerate a git-ignored file from make() if missing.
function slurp(path)
  local f = io.open(path, "r"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
function emit(path, text)
  local f = io.open(path, "w"); if not f then return end
  f:write(text); f:close()
end
function heal(path, make)
  if not slurp(path) then local t = make(); if t then emit(path, t) end end
end

-- bins: absolute paths to the CLIs the connector residents shell out to — one source per binary,
-- this runtime. (The Hammerspoon surface keeps its own copy; it's a separate process.)
bins = { tmux = "/opt/homebrew/bin/tmux", nvim = "/opt/homebrew/bin/nvim" }

function pick(what)    return intent("menu", { what = what }, what) end   -- the menu should show `what`
-- a place named relatively: `step` along the trail of one kind (or all, when kind is nil) —
-- back is +1, forward −1; `slot` a favourite. The trail / favourites resolve it to a place by
-- name, which its surface enters. A verb is a noun in the future tense.
local function flip(step, kind) return intent("place", { step = step, kind = kind }, kind and ("flip " .. kind .. "s") or "flip") end
function back(kind)    return flip(1, kind)  end
function forward(kind) return flip(-1, kind) end
function jump(slot)    return intent("place", { slot = slot }, "favourites") end
function grep()        return intent("grep", nil, "grep") end
-- retheme: cycle the palette (or `to = "random"`). The theme resident writes the next skin to the
-- shared colours file; every surface re-colours off that one file. (A future `theme` — an intent.)
function retheme(to, label) return intent("theme", { to = to or "next" }, label or "theme") end

-- aware: a key the surface binds directly to its own action (a chord, for speed — not routed as a
-- word per press); context-aware — the surface disables it wherever the terminal
-- wants that key (nvim/tmux own ⌃⏎ there).
function aware(name) return { act = name, aware = true } end

-- surface: a key the surface handles entirely on its own (a local mode or gesture, not a routed
-- word) — declared here ONLY so it shows on the ? card. keeps the map the whole doc even for keys
-- whose mechanism lives in the surface (e.g. HS's resize sub-mode, hjkl glide inside the terminal).
function surface(label) return { surface = true, label = label } end

-- move: shift focus one window in a direction. the surface obeys.
function move(dir) return intent("move", { dir = dir }, "point") end

-- arrange: position the focused window — `to` is "max" (maximize ↔ restore, fill the
-- screen). the surface owns the geometry.
function arrange(to, label) return intent("arrange", { to = to }, label) end

-- keymap: "<where> <key>" → an intention. Surfaces report keys as `key {at, press}`. The map
-- itself is written as a substrate the surfaces read (see below) — the ? card and the chords a
-- surface binds directly derive from the one table, so the card is the map.
function keymap(map)
  local function hint(at)
    local by, order = {}, {}
    for k, intent in pairs(map) do
      local a, press = k:match("^(%S+) (.+)$")
      if a == at and intent.label then
        if not by[intent.label] then by[intent.label] = {}; order[#order + 1] = intent.label end
        table.insert(by[intent.label], press)
      end
    end
    local items = {}
    for _, lbl in ipairs(order) do
      local ks = by[lbl]; table.sort(ks)
      local keys = (#ks >= 3 and ks[1]:match("%d")) and (ks[1] .. "–" .. ks[#ks]) or table.concat(ks, " ")
      items[#items + 1] = { keys = keys, label = lbl }
    end
    table.sort(items, function(x, y) return x.keys < y.keys end)
    return items
  end

  local function wiring()   -- the chords a surface binds directly (act/aware entries)
    local out = {}
    for k, v in pairs(map) do
      if v.act then out[#out + 1] = { key = k, act = v.act, aware = v.aware } end
    end
    return out
  end

  -- the map as a substrate the surface reads (~/.cache/town/keys), like the transport manifest:
  -- one line per item, tab-separated. `hint <at> <keys> <label>` for the ? card; `bind <key>
  -- <act> [aware]` for the chords a surface binds itself. Written at load; the surface reads it.
  local lines = {}
  for _, it in ipairs(hint("leader")) do lines[#lines + 1] = table.concat({ "hint", "leader", it.keys, it.label }, "\t") end
  for _, b in ipairs(wiring()) do
    lines[#lines + 1] = table.concat({ "bind", b.key, b.act, b.aware and "aware" or "" }, "\t")
  end
  emit(os.getenv("HOME") .. "/.cache/town/keys", table.concat(lines, "\n") .. "\n")

  return {
    listen = { "key" },
    talk = function(w)
      local v = map[(w.body.at or "") .. " " .. (w.body.press or "")]
      if v and not v.act and not v.surface then return v end   -- acts/surface keys are handled at the surface
    end,
  }
end

-- on: a talk clause — match a word by kind, tense, and what it goes by; run act(w). A word can name
-- its referent by a field (a future place by `step`, by `slot`, by name) — `by = "step"` is a
-- word that has one; `by = { kind = "session" }` a word whose fields are these.
--   on("colors", fn)  ·  on({ kind = "place", tense = "future", by = "slot" }, fn)
function on(spec, act)
  if type(spec) == "string" then spec = { kind = spec } end
  local by = spec.by
  return {
    kind = spec.kind,
    match = function(w)
      if spec.kind and w.kind ~= spec.kind then return false end
      if spec.tense and (w.tense or "present") ~= spec.tense then return false end
      if by then
        local b = w.body
        if type(b) ~= "table" then return false end
        if type(by) == "string" then return b[by] ~= nil end
        for k, v in pairs(by) do if b[k] ~= v then return false end end
      end
      return true
    end,
    act = act,
  }
end

-- react: a resident from `on` clauses. `listen` is derived from the clause kinds; `talk` runs the
-- first matching clause. Add `watch` (or other fields) to the returned table after, if needed.
function react(list)
  local listen, seen = {}, {}
  for _, c in ipairs(list) do
    if c.kind and not seen[c.kind] then seen[c.kind] = true; listen[#listen + 1] = c.kind end
  end
  return {
    listen = listen,
    talk = function(w)
      for _, c in ipairs(list) do if c.match(w) then return c.act(w) end end
    end,
  }
end

-- when(kind, action): react to a kind. `action` is a word to talk, or a fn of the word returning one.
function when(kind, action)
  return react { on(kind, type(action) == "function" and action or function() return action end) }
end

-- trail: recent places of one kind, walked like ⌘-tab. A present `over` fact promotes that place
-- to the front (deduped by `id`) and homes the cursor; a future `over` with a `step` moves the
-- cursor and talks a future `over` by name for the surface to enter; a past `over` is a place
-- that is no more. A flip's own echo — the surface reporting back the focus we just caused —
-- arrives as a present fact whose key matches the cursor (`seen[at]`); that case is ignored so
-- only a genuinely different focus reorders the list.
function trail(over, id)
  local seen, at = {}, 1
  local last            -- the flip in flight {dir, of}: if it lands on a place that's gone, it carries on
  local function key(p) return p and id(p) end
  local function flip(dir, of)
    local i = at + dir
    while seen[i] and of and seen[i].kind ~= of do i = i + dir end
    if seen[i] then
      at = i; last = { dir = dir, of = of }         -- move the cursor only — never reorder
      return intent(over, seen[i])
    end
  end
  return {
    listen = { over },
    talk = function(w)
      local b = w.body or {}
      if w.tense == "future" then
        -- a relative name (`step`) is ours to resolve; a place by name is for its surface
        local step = tonumber(b.step)
        if step then return flip(step, b.kind) end
      elseif w.tense == "present" then
        if seen[at] and key(b) == key(seen[at]) then return end  -- our flip's own echo — hold the cursor
        for i, p in ipairs(seen) do if key(p) == key(b) then table.remove(seen, i); break end end
        table.insert(seen, 1, b); at = 1          -- a different focus → promote to front, cursor home
      else
        -- past: a place that is no more (its surface said so). drop it; if it's where the cursor
        -- just landed, the press that got there hasn't happened yet — carry the flip on past it.
        local k = key(b)
        for i, p in ipairs(seen) do
          if key(p) == k then
            table.remove(seen, i)
            if i == at and last then
              at = (last.dir == 1) and i - 1 or i
              return flip(last.dir, last.of)
            end
            if i < at then at = at - 1 end
            if at < 1 then at = 1 end
            break
          end
        end
      end
    end,
  }
end
