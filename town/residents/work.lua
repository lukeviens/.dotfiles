-- work — what the machine was made to do. A past `work` {where, ms} per command, named by
-- the call site; folded into the present `work` (med, max, n per site), with `slow` for one far
-- outside its site's history. time.lua measures the gap between wanting and having; this, the cost.
local KEEP, EVERY = 64, 20          -- spawns kept per site; the fold is talked every EVERY
local ODD, FLOOR = 5, 250           -- slow: over ODD × the site's median, and at least FLOOR ms
local AT = 8                        -- no verdict until a site has this much history
local sites = {}
local seen = 0

local function median(t)
  local s = {}
  for i, v in ipairs(t) do s[i] = v end
  table.sort(s)
  return s[(#s + 1) // 2] or 0
end

local function fold()
  local out = {}
  for k, a in pairs(sites) do
    local mx = 0
    for _, v in ipairs(a.t) do if v > mx then mx = v end end
    out[k] = { med = median(a.t), max = mx, n = a.n }
  end
  return out
end

return react {
  on({ kind = "work", tense = "past" }, function(w)
    local b = w.body or {}
    local ms, site = tonumber(b.ms), b.where
    if not ms or not site then return end
    local a = sites[site]
    if not a then a = { t = {}, i = 0, n = 0 }; sites[site] = a end
    a.n = a.n + 1; a.i = a.i % KEEP + 1; a.t[a.i] = ms
    seen = seen + 1
    local med = median(a.t)
    if a.n > AT and ms >= FLOOR and ms > ODD * med then
      return event("slow", { kind = "spawn " .. site, ms = ms, med = med })
    end
    if seen < 5 or seen % EVERY == 0 then return fact("work", fold()) end
  end),
}
