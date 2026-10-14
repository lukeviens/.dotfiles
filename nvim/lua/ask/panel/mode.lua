-- The one place a mode takes over state.win: swap buffer, focus it, apply keymaps. Diff is the
-- only mode an external RPC call can trigger with focus anywhere -- memory/help are always
-- entered from inside the panel already.
local keymap = require("ask.panel.keymap")
local M = {}

-- winbar: an optional hint shown in state.win for as long as this mode is active. diff uses
-- this (see diff.lua) -- ? is blocked mid-review, with nowhere sane for the full help screen to
-- return to, so the keys need to stay visible some other way.
function M.enter(state, name, buf, actions, winbar)
	state.mode = name
	-- which of diff/discuss was actually showing, for M.exit to return to -- both equally
	-- leave state.diff set, and help/memory_view can interrupt either one now.
	if state.diff and (name == "diff" or name == "discuss") then state.diff.active_view = name end
	vim.api.nvim_win_set_buf(state.win, buf)
	vim.api.nvim_set_current_win(state.win)
	vim.wo[state.win].winbar = winbar or ""
	keymap.apply(name, buf, actions)
end

-- back to whatever was underneath. A pending review (help/memory_view interrupted it --
-- finish_change already nils state.diff before calling this on its own exit) returns to
-- whichever of diff/discuss was showing; otherwise back to the transcript.
function M.exit(state)
	local d = state.diff
	if d then
		if d.active_view == "discuss" and d.discuss_buf then
			state.mode = "discuss"
			if vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_set_buf(state.win, d.discuss_buf) end
			return
		end
		state.mode = "diff"
		if vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_win_set_buf(state.win, d.target_buf)
			vim.wo[state.win].winbar = keymap.winbar_hint("diff")
		end
		return
	end
	state.mode = "chat"
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_set_buf(state.win, state.buf)
		vim.wo[state.win].winbar = ""
	end
end

-- a read-only markdown page in state.win; help and the memory view are each just this. Its
-- buffer wipes itself once left, so nothing needs to track it. q/<Esc> return to chat.
function M.show_page(state, name, lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	M.enter(state, name, buf, { close = function() M.exit(state) end })
end

return M
