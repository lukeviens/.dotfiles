-- tree.lua — one decision: action, direction, depth, frontmost surface → what happens, and where.
--
-- Places nest. A split is in a pane, in a session, in a mac window; a tab is in a mac window.
-- depth is steps up from the leaf, and there are three ways through:
--   point (hjkl)   among siblings
--   flip  (o/i)    the same siblings, by recency
--   depth (Caps)   one step up
--
-- Pure — no hs.* — so mode.lua executes it and town/tests/tree.rs sweeps it, nothing in between.
--
-- The branches below state the tree per surface. Give a place its parent and they derive.
local M = {}

local TABDIR = { h = "prev", k = "prev", j = "next", l = "next" }   -- point's middle rung: tmux windows
local STEP = { prev = -1, next = 1 }                                -- same reading, for Chrome's tab cycle

-- ctx = { inTerm, inVim, inChrome }. `verb` is the grabbed register for hjkl, or "flip"
-- for o/i. `d` may be nil when only `where` is wanted (a badge repaint).
--
-- flip names only the context (`at`); the keymap says which kind that context walks, and the
-- trail walks it. A surface that reports its places needs no branch here.
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
