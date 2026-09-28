-- time.lua — HS's side of town's time. Two things:
--   the fold: residents/time.lua talks the present `time` (per kind: median, max, n of the gap
--     from intent to fact). It becomes the ? card's second page — a table, slowest first, a mark
--     on any kind that said `slow` in the last ten minutes.
--   the microbench: `town talk future time` runs named facets (the synchronous work that
--     freezes HS when it blooms) and diffs against a saved baseline; `time what=baseline` saves.
--     For when a `slow` points somewhere and you want it in parts.

local M = {}
local HOME   = os.getenv("HOME")
local BASE   = HOME .. "/.cache/town/time-base.json"
local REPORT = HOME .. "/.cache/town/time-report.txt"

local function ns() return hs.timer.absoluteTime() end

-- run a facet: before() once, then run() `reps` times; return min/med/max in ms.
local function measure(f)
  if f.before then f.before() end
  local t, reps = {}, f.reps or 25
  for i = 1, reps do local a = ns(); f.run(); t[i] = (ns() - a) / 1e6 end
  if f.after then f.after() end
  table.sort(t)
  return { min = t[1], med = t[(#t + 1) // 2], max = t[#t] }
end

-- a suite is an ordered list of { name=, run=fn, before?=fn, after?=fn, reps?=n }.
function M.run(suite)
  local out = {}
  for _, f in ipairs(suite) do out[f.name] = measure(f) end
  return out
end

function M.save(results)
  local ok, j = pcall(hs.json.encode, results, true)
  local h = ok and io.open(BASE, "w")
  if h then h:write(j); h:close() end
end
function M.load()
  local h = io.open(BASE, "r"); if not h then return nil end
  local s = h:read("*a"); h:close()
  local ok, r = pcall(hs.json.decode, s)
  return ok and r or nil
end

-- write the report where a shell can read it; return the path.
function M.write(text)
  local h = io.open(REPORT, "w"); if h then h:write(text); h:close() end
  return REPORT
end

-- a report: min/med/max now vs the baseline's MEDIAN, verdict on the median. Median is the
-- robust signal — the freeze we chased showed a ~10x median jump, and median doesn't cry wolf
-- on the AX-timing noise that rattles a facet's max. `tol` is the factor the median may rise
-- before it's a regression; `floor` ignores sub-ms wobble on tiny facets. max is shown for the eye.
function M.report(now, base, tol, floor)
  tol, floor = tol or 1.8, floor or 5
  local names = {}
  for n in pairs(now) do names[#names + 1] = n end
  table.sort(names)
  local L = { string.format("%-20s %8s %8s %8s %10s  %s", "facet", "min", "med", "max", "base med", "verdict") }
  local worst = "ok"
  for _, n in ipairs(names) do
    local r, b = now[n], base and base[n] and base[n].med
    local verdict
    if not b then verdict = "—"
    elseif r.med > b * tol and r.med - b > floor then verdict = string.format("REGRESS x%.1f", r.med / b); worst = "regress"
    elseif b > r.med * tol and b - r.med > floor then verdict = string.format("improved x%.1f", b / r.med)
    else verdict = "ok" end
    L[#L + 1] = string.format("%-20s %8.2f %8.2f %8.2f %10s  %s",
      n, r.min, r.med, r.max, b and string.format("%.2f", b) or "—", verdict)
  end
  return table.concat(L, "\n"), worst
end


-- ── the fold → the table ─────────────────────────────────────────────────────────────────────
local fold, slowed = {}, {}   -- the latest present `time`; kind → when it last said `slow`
function M.card()
  local rows = {}
  for kind, a in pairs(fold) do rows[#rows + 1] = { kind = kind, med = a.med or 0, max = a.max or 0, n = a.n or 0 } end
  table.sort(rows, function(x, y) return x.max > y.max end)
  local out = {}
  for _, r in ipairs(rows) do
    out[#out + 1] = { r.kind, math.floor(r.med), math.floor(r.max), math.floor(r.n),
      mark = (slowed[r.kind] and os.time() - slowed[r.kind] < 600) and "!" or nil }
  end
  if #out == 0 then out[1] = { "—", "", "", "" } end
  return { page = "time", title = "◆ time   from wanting to having, ms", foot = "?  ·  esc closes",
    head = { "kind", "median", "max", "n" }, widths = { 150, 64, 64, 40 }, rows = out }
end

-- ── the microbench suite: what the surface does synchronously when town asks it to ──────────
local function suite(places, picker)
  local raw = picker.last_raw()
  if #raw == 0 then                                  -- no real pick yet: synthesize one
    raw = {}
    for _, win in ipairs(places.list_windows()) do raw[#raw + 1] = { label = win.title, id = win.app, kind = "window", app = win.app } end
    if #raw == 0 then for _, a in ipairs(places.list_apps()) do raw[#raw + 1] = { label = a.text, id = a.text, kind = "app", app = a.text } end end
  end
  local popts = { placeholder = "go", choices = places.decorate(raw), onSelect = function() end }
  return {
    { name = "apps.warm",         run = function() places.list_apps() end },
    { name = "apps.cold",         run = function() places.list_apps(true) end, reps = 5 },
    { name = "windows.warm",      run = function() places.list_windows() end },
    { name = "windows.cold",      run = function() places.list_windows(true) end, reps = 5 },
    { name = "icons.decorate",    run = function() places.decorate(raw) end },
    { name = "picker.open.delta", before = function() picker.show(popts) end,
      run = function() picker.show(popts) end, after = function() picker.hide() end },
    { name = "picker.open.fresh", run = function() picker.hide(); picker.show(popts) end, reps = 3 },
    { name = "picker.hide.only",  before = function() picker.show(popts) end, run = function() picker.hide() end, reps = 3 },
    { name = "picker.show.only",  before = function() picker.hide() end, run = function() picker.show(popts) end, reps = 3 },
    { name = "windows.ordered",   run = function() hs.window.orderedWindows() end, reps = 5 },
    { name = "windows.filter",    run = function() hs.window.filter.default:getWindows() end, reps = 5 },
  }
end

function M.start(town, d)   -- d = { places, picker, hud }
  town.listen("slow", function(w) slowed[(w.body or {}).kind or "?"] = os.time() end)
  town.listen("time", function(w)
    if w.tense == "present" then
      fold = w.body or {}
      if d.hud.cardShown("time") then d.hud.showTable(M.card()) end
      return
    end
    if w.tense ~= "future" then return end
    local ok, res = pcall(function()
      local now = M.run(suite(d.places, d.picker))
      d.picker.hide()                               -- the suite leaves it up; put it away
      local text, worst
      if w.body and w.body.what == "baseline" then
        M.save(now); text = "baseline saved.\n\n" .. (M.report(now, now))
      else
        text, worst = M.report(now, M.load())
      end
      M.write(text)
      return worst or "baseline"
    end)
    if ok then d.hud.toast("time → " .. res)
    else M.write("time ERROR:\n" .. tostring(res)); d.hud.toast("time error (see report)") end
  end)
end

return M
