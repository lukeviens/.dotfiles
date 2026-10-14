-- A message submitted while a turn is already running waits right there in the compose box --
-- the real draft, not a copy teleported into a separate float. Depth 1: pressing send again
-- while already queued is a no-op; the box already holds whatever's about to go out, and
-- editing it further is just editing it, the same as it always is.
local M = {}

function M.cancel_queued(state)
	state.queued = nil
end

function M.enqueue(state)
	state.queued = true
	vim.notify("ask: queued -- will send once the current turn finishes", vim.log.levels.INFO)
end

-- whatever's currently in the compose box, if still queued and non-empty by the time the
-- running turn finishes -- reflects any edits made while waiting, since the text never moved
-- anywhere else to be edited. nil if nothing was queued, or the box is empty (typed, then
-- cleared by hand -- that's how you cancel a queued send: there's nothing else to cancel).
function M.pop_queued(state)
	if not state.queued then return nil end
	state.queued = nil
	local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false), "\n"))
	vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
	return text ~= "" and text or nil
end

return M
