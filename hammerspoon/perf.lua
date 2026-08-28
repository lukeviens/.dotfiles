-- perf.lua — time named facets: the synchronous work that freezes HS when it blocks. Take a
-- baseline, change something, diff. The freeze we chased was a TAIL event (median fine, max
-- ~3s), so the verdict watches MAX, not the average. Measuring is a word ("perf"); the
-- report lands in a file you can read from a shell.
--
--   town talk future perf                 run the suite, diff against the baseline
--   town talk future perf what=baseline   capture the current run AS the baseline

local M = {}
local HOME   = os.getenv("HOME")
local BASE   = HOME .. "/.cache/town/perf-base.json"
local REPORT = HOME .. "/.cache/town/perf-report.txt"

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

return M
