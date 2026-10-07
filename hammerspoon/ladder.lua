-- ladder.lua — the depth ladder's one decision: given an action, direction, depth, and which
-- surface is frontmost, what should happen and where. Pure (no hs.* calls) so it's the
-- single source of truth mode.lua executes against AND what town/tests/ladder.rs sweeps directly —
-- no separate doMotion/locate to keep in sync.
local M = {}

local TABDIR = { h = "prev", k = "prev", j = "next", l = "next" }   -- point's middle rung: tmux windows
local STEP = { prev = -1, next = 1 }                                -- same reading, for Chrome's tab cycle

-- ctx = { inTerm, inVim, inChrome }. `verb` is the grabbed register for hjkl, or "flip"
-- for o/i. `d` may be nil when only `where` is wanted (a badge repaint).
--
-- flip (o/i) means ONE thing everywhere: walk the trail of places at this depth, most-recent
-- first. So the ladder only names WHICH context the key is reported as (`at`); the keymap says
-- which kind of place that context walks, and town's trail does the walking. A surface that
-- reports its places needs no branch here — that's the test of whether a new one slots in.
function M.plan(verb, d, atDepth, DMAX, ctx)
  if verb == "flip" then
    if ctx.inTerm and atDepth == 0 then
      return { act = "wez", verb = "flip", dir = d }
    elseif ctx.inTerm and atDepth < DMAX then
      return { act = "onkey", at = "tmux", dir = d }
    elseif ctx.inChrome and atDepth == 0 then
      return { act = "onkey", at = "chrome", dir = d }
    else
      return { act = "onkey", at = "leader", dir = d }
    end
  end
  local register = verb
  if atDepth == 0 and ctx.inTerm then
    local where = (register == "cell") and "tmux" or (ctx.inVim and "nvim" or "tmux")
    return { act = "wez", verb = register, dir = d, where = where }
  elseif register == "point" and atDepth == 0 and ctx.inChrome then
    return { act = "chrome-cycle", step = STEP[TABDIR[d]], where = "chrome" }
  elseif register == "point" and atDepth < DMAX and ctx.inTerm then
    return { act = "wez", verb = "tab", dir = TABDIR[d], where = "tmux tabs" }
  elseif register == "edge" and atDepth < DMAX and ctx.inTerm and ctx.inVim then
    return { act = "wez", verb = "edge-pane", dir = d, where = "tmux pane" }
  elseif register == "edge" or register == "cell" then
    return { act = "mac", reg = register, dir = d, where = "mac window" }
  elseif register == "point" then
    return { act = "onkey", dir = d, where = "mac window" }
  end
end

return M
