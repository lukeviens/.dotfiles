-- time — how long the town takes. Every word carries `at`. An intent opens a wait; the next fact
-- of that kind whose body fits closes it, and the gap is the answer's time. Gaps fold into the
-- present `time` (median, max, n per kind). `slow`: one gap far outside its kind's past, or a
-- kind's median well above the last open's. A future `time` is the hand microbench (HS runs it).
local KEEP, EVERY = 64, 20          -- gaps kept per kind; the fold is talked every EVERY gaps
local ODD, FLOOR = 5, 100           -- slow: over ODD × the kind's median, and at least FLOOR ms
local DRIFT, AT = 3, 16             -- regress: at AT gaps, median over DRIFT × the last open's
local STALE = 5000                  -- an intent unanswered this long is forgotten, not measured
local OPEN = 8                      -- open intents kept per kind (a fact closes the newest it fits)
local waits, kinds = {}, {}         -- kind → open intents {at, body}, oldest first; kind → ring of gaps
local was = present("time") or {}   -- the last open's fold
local seen = 0

local function fits(intent, fact)   -- every scalar key they share agrees
  if type(intent) ~= "table" or type(fact) ~= "table" then return true end
  for k, v in pairs(intent) do
    if type(v) ~= "table" and fact[k] ~= nil and fact[k] ~= v then return false end
  end
  return true
end

local function median(t)
  local s = {}
  for i, v in ipairs(t) do s[i] = v end
  table.sort(s)
  return s[(#s + 1) // 2] or 0
end

local function fold()
  local out = {}
  for k, a in pairs(kinds) do
    local mx = 0
    for _, v in ipairs(a.t) do if v > mx then mx = v end end
    out[k] = { med = median(a.t), max = mx, n = a.n }
  end
  return out
end

return {
  listen = { "*" },
  talk = function(w)
    if not w.at then return end
    local k = w.kind
    if w.tense == "future" then
      if type(w.body) ~= "table" or next(w.body) == nil then return end   -- an empty wish (a ping) is nothing to become
      local q = waits[k] or {}; waits[k] = q
      q[#q + 1] = { at = w.at, body = w.body }
      if #q > OPEN then table.remove(q, 1) end
      return
    end
    if w.tense ~= "present" then return end
    local q = waits[k]
    if not q then return end
    local gap
    for i = #q, 1, -1 do                          -- newest first; stale ones fall away as we pass
      if w.at - q[i].at > STALE then table.remove(q, i)
      elseif fits(q[i].body, w.body) then gap = w.at - q[i].at; table.remove(q, i); break end
    end
    if not gap or gap < 0 then return end

    -- the row: the word's kind, and the body's own kind when it has one (place session · place window)
    if type(w.body) == "table" and type(w.body.kind) == "string" then k = k .. " " .. w.body.kind end
    local a = kinds[k]
    if not a then a = { t = {}, i = 0, n = 0 }; kinds[k] = a end
    a.n = a.n + 1; a.i = a.i % KEEP + 1; a.t[a.i] = gap
    seen = seen + 1
    local med = median(a.t)
    if a.n > AT // 2 and gap >= FLOOR and gap > ODD * med then
      return event("slow", { kind = k, ms = gap, med = med })
    end
    local old = was[k]
    if old and a.n == AT and med >= FLOOR and med > DRIFT * old.med then   -- once per kind per open
      return event("slow", { kind = k, ms = med, med = old.med, regress = true })
    end
    if seen < 5 or seen % EVERY == 0 then return fact("time", fold()) end   -- early folds land fast
  end,
}
