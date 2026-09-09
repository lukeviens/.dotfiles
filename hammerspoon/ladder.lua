-- ladder.lua — the depth ladder's one decision: given a register, a direction, a depth, and which
-- surface is frontmost, what should hjkl do and where is that. Pure (no hs.* calls) so it's the
-- single source of truth mode.lua executes against AND what town/tests/ladder.rs sweeps directly —
-- no separate doMotion/locate to keep in sync.
local M = {}

local TABDIR = { h = "prev", k = "prev", j = "next", l = "next" }   -- point's middle rung: tmux windows
local STEP = { prev = -1, next = 1 }                                -- same reading, for Chrome's tab cycle

-- ctx = { inTerm, inVim, inChrome }. `d` may be nil when only `where` is wanted (a badge repaint
-- with no motion pending) — nothing below needs it except the direction/step for an actual `act`.
function M.plan(register, d, atDepth, DMAX, ctx)
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
