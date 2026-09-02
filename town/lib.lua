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

-- bins: absolute paths to the CLIs the connector residents shell out to — one source per binary,
-- this runtime. (The Hammerspoon surface keeps its own copy; it's a separate process.)
bins = { tmux = "/opt/homebrew/bin/tmux", nvim = "/opt/homebrew/bin/nvim" }

function pick(what)    return intent("pick", { what = what }, what) end
-- back/forward: flip through the trail of one kind (or all, when kind is nil).
local function flip(way, kind) return intent(way, { kind = kind }, kind and ("flip " .. kind .. "s") or "flip") end
function back(kind)    return flip("back", kind)    end
function forward(kind) return flip("forward", kind) end
function jump(slot)    return intent("jump", { slot = slot }, "favourites") end
function grep()        return intent("grep", nil, "grep") end
-- retheme: cycle the palette (or `to = "random"`). The theme resident writes the next skin to the
-- shared colours file; every surface re-colours off that one file. (A future `theme` — an intent.)
function retheme(to, label) return intent("theme", { to = to or "next" }, label or "theme") end

-- act: a key the surface binds directly to one of its own actions (a chord, bound at
-- the surface for speed — not routed as a word on every press). always-on everywhere.
function act(name) return { act = name } end

-- aware: like act, but context-aware — the surface disables it wherever the terminal
-- wants that key (nvim/tmux own ⌃hjkl / ⌃⏎ there) and forwards `move` at its edge.
function aware(name) return { act = name, aware = true } end

-- move: shift focus one window in a direction. the surface obeys; the terminal's
-- edge-crossing talks the same word, so focus is one vocabulary everywhere.
function move(dir) return intent("move", { dir = dir }, "focus") end

-- arrange: position the focused window — `to` is a half (left/right/top/bottom),
-- "max" (maximize ↔ restore), or "fullscreen" (native). the surface owns the geometry.
function arrange(to, label) return intent("arrange", { to = to }, label) end

-- keymap: "<where> <key>" → an intention. Surfaces report keys as `key {at, press}`.
-- Also answers a `hint {at}` with the menu for that surface — so the hint is the map.
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

  return {
    listen = { "key", "hint", "wire" },
    talk = function(w)
      if w.kind == "hint" then
        return event("hints", { at = w.body.at, items = hint(w.body.at or "leader") })
      elseif w.kind == "wire" then
        return event("wiring", { binds = wiring() })
      end
      local v = map[(w.body.at or "") .. " " .. (w.body.press or "")]
      if v and not v.act then return v end   -- acts are bound directly, never routed here
    end,
  }
end

-- on: a talk clause — match a word by kind (+ optional tense / body predicate), run act(w).
--   on("colors", fn)  ·  on({ kind = "place", tense = "future", where = fn(body) }, fn)
function on(spec, act)
  if type(spec) == "string" then spec = { kind = spec } end
  return {
    kind = spec.kind,
    match = function(w)
      if spec.kind and w.kind ~= spec.kind then return false end
      if spec.tense and (w.tense or "present") ~= spec.tense then return false end
      if spec.where and not spec.where(w.body) then return false end
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

-- trail: the recent places of a kind, walked — like ⌘-tab / vim `:bnext`. A present fact of
-- `over` promotes that place to the front (most-recent-first, deduped by `id`) and homes the
-- cursor; back/forward flip a cursor through the list of one kind, talking a future `over` for
-- its surface to enter. The walk moves the cursor ONLY — it never reorders. The list reorders
-- solely on a genuinely DIFFERENT present focus, so it stays a plain stack of pointers.
--
-- The catch: a flip focuses a real window/session, and the surface reports that focus straight
-- back as a present fact — the flip's own echo. No surface-side guard can catch all of it (the
-- tmux client-session-changed hook talks the session echo from another process). So the trail
-- drops it where every echo converges: a present fact whose key equals the place the cursor is
-- already parked on (`seen[at]`) IS the echo of what we just flipped to — ignore it. A genuine
-- focus of a different place still reorders. Doubled-echo-proof (both copies match `seen[at]`),
-- and it needs no state beyond the cursor the walk already keeps.
function trail(over, id)
  local seen, at = {}, 1
  local function key(p) return p and id(p) end
  return {
    listen = { over, "back", "forward" },
    talk = function(w)
      if w.kind == over then
        if w.tense ~= "present" then return end        -- only facts extend the trail
        if seen[at] and key(w.body) == key(seen[at]) then return end  -- our flip's own echo — hold the cursor
        for i, p in ipairs(seen) do if key(p) == key(w.body) then table.remove(seen, i); break end end
        table.insert(seen, 1, w.body); at = 1          -- a different focus → promote to front, cursor home
      else
        local of = w.body and w.body.kind
        local dir = (w.kind == "back") and 1 or -1
        local i = at + dir
        while seen[i] and of and seen[i].kind ~= of do i = i + dir end
        if seen[i] then
          at = i                                        -- move the cursor only — never reorder
          return intent(over, seen[i])
        end
      end
    end,
  }
end
