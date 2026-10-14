-- Turn rendering: the question's blockquote, its growing answer, and the compose box's
-- content/highlight.
local M = {}
local buffer = require("ask.panel.buffer")

local HL_NS = vim.api.nvim_create_namespace("ask_question")

-- the blockquote marker alone reads too similar to the answer below it -- color makes whose
-- turn it is obvious at a glance, and the compose box uses the same group so it already looks
-- like how it'll render once sent. Links to Title so it holds up across colorschemes; priority
-- 200 beats render-markdown's own blockquote highlight (140) on the same line.
function M.ensure_highlight()
	if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "AskQuestion" })) then
		vim.api.nvim_set_hl(0, "AskQuestion", { link = "Title", default = true })
	end
end

-- start1/end1: 1-indexed, inclusive -- a multi-line question (<S-CR>) highlights as one block.
function M.highlight_question(bufnr, start1, end1)
	vim.api.nvim_buf_set_extmark(bufnr, HL_NS, start1 - 1, 0, {
		end_row = end1,
		hl_group = "AskQuestion",
		hl_eol = true,
		priority = 200,
	})
end

-- repaints the whole compose box every edit -- cheap at this size, simpler than diffing
-- changed lines.
function M.recolor_compose(state)
	vim.api.nvim_buf_clear_namespace(state.input_buf, HL_NS, 0, -1)
	M.highlight_question(state.input_buf, 1, vim.api.nvim_buf_line_count(state.input_buf))
end

-- A turn: the blockquoted question plus its growing answer. turn:update(text) replaces
-- exactly the answer's current region, never "to the end" -- robust to whatever gets appended
-- after it, including repeated calls as a streamed answer grows.
function M.start_turn(state, label)
	local lines = {}
	if vim.api.nvim_buf_line_count(state.buf) > 1 then vim.list_extend(lines, { "---", "" }) end
	local before_question = #lines
	local quoted = {}
	for _, l in ipairs(vim.split(label, "\n", { plain = true })) do
		quoted[#quoted + 1] = "> " .. l
	end
	vim.list_extend(lines, quoted)
	vim.list_extend(lines, { "", "*Asking...*", "" })
	local end_line = buffer.append(state, lines)
	local question_start = end_line - #lines + 1 + before_question
	M.highlight_question(state.buf, question_start, question_start + #quoted - 1)

	local start_line, count = end_line - 1, 2
	local turn = {}
	function turn:update(text)
		local render_lines = vim.split(text, "\n", { plain = true })
		render_lines[#render_lines + 1] = ""
		buffer.with_writable(state, function()
			vim.api.nvim_buf_set_lines(state.buf, start_line - 1, start_line - 1 + count, false, render_lines)
		end)
		buffer.scroll_to_end(state)
		count = #render_lines
	end
	return turn
end

-- replaces the compose box's content outright, recolors, and parks the cursor at the end.
-- Focus is the caller's own concern (panel/init.lua's M.focus_compose).
function M.set_compose(state, lines)
	vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, lines)
	M.recolor_compose(state)
	vim.api.nvim_win_set_cursor(state.input_win, { #lines, 0 })
end

return M
