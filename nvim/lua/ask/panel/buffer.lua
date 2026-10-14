-- Low-level primitives for writing into the transcript buffer -- shared by transcript.lua
-- (turns) and queue.lua (the pending-turn marker), both of which write into state.buf.
local M = {}

-- the transcript is read-only outside these writes -- nvim_buf_set_lines still enforces
-- `modifiable` for API calls, not just keymaps, so a write lifts it briefly.
function M.with_writable(state, fn)
	vim.bo[state.buf].modifiable = true
	fn()
	vim.bo[state.buf].modifiable = false
end

function M.scroll_to_end(state)
	local last = vim.api.nvim_buf_line_count(state.buf)
	pcall(vim.api.nvim_win_set_cursor, state.win, { last, 0 })
end

-- inserts only the new lines at the end -- rewriting the whole buffer collapses any extmark
-- anchored earlier in it (like a prior turn's question highlight) to the deletion boundary.
function M.append(state, lines)
	M.with_writable(state, function()
		local fresh = vim.api.nvim_buf_line_count(state.buf) == 1
			and vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] == ""
		vim.api.nvim_buf_set_lines(state.buf, fresh and 0 or -1, -1, false, lines)
	end)
	M.scroll_to_end(state)
	return vim.api.nvim_buf_line_count(state.buf)
end

return M
