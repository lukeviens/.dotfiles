-- A small floating selection menu, cursor-anchored. Knows nothing about fixes, LSP, or
-- treesitter — just labels in, a chosen index out. One of possibly several implementations of
-- the fix/ui interface (see ui/init.lua); reached only through it, never required directly.
local M = {}

local state = nil -- { win, buf, labels, selected, anchor_bufnr, on_accept }

function M.is_open()
	return state ~= nil
end

-- a highlight-only indicator (first PmenuSel, then Visual) never showed up live, even though it
-- was confirmed present on the buffer — plain text can't fail to render.
local function render()
	local lines = {}
	for i, label in ipairs(state.labels) do
		lines[i] = (i == state.selected and "> " or "  ") .. label
	end
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
end

local KEYS = { "<Tab>", "<M-j>", "<M-k>", "<Down>", "<Up>", "<Esc>" }

function M.close()
	if not state then return end
	if vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
	if vim.api.nvim_buf_is_valid(state.buf) then vim.api.nvim_buf_delete(state.buf, { force = true }) end
	for _, key in ipairs(KEYS) do
		pcall(vim.keymap.del, "n", key, { buffer = state.anchor_bufnr })
	end
	state = nil
end

local function select(delta)
	state.selected = ((state.selected - 1 + delta) % #state.labels) + 1
	render()
end

local function accept()
	local selected, on_accept = state.selected, state.on_accept
	M.close()
	on_accept(selected)
end

-- bufnr: buffer to bind the accept/cycle/dismiss keys to (buffer-local, cleared on close).
-- labels: array of display strings. on_accept(index): called once, after the popup has closed.
function M.open(bufnr, labels, on_accept)
	local width = 0
	for _, label in ipairs(labels) do
		width = math.max(width, #label + 2)
	end
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = #labels,
		style = "minimal",
		border = "none",
	})
	vim.wo[win].winhighlight = "Normal:Pmenu,FloatBorder:Pmenu"
	state = { win = win, buf = buf, labels = labels, selected = 1, anchor_bufnr = bufnr, on_accept = on_accept }
	render()

	local opts = { buffer = bufnr, nowait = true }
	vim.keymap.set("n", "<Tab>", accept, vim.tbl_extend("force", opts, { desc = "fix: accept" }))
	vim.keymap.set("n", "<M-j>", function() select(1) end, vim.tbl_extend("force", opts, { desc = "fix: next" }))
	vim.keymap.set("n", "<M-k>", function() select(-1) end, vim.tbl_extend("force", opts, { desc = "fix: prev" }))
	vim.keymap.set("n", "<Down>", function() select(1) end, vim.tbl_extend("force", opts, { desc = "fix: next" }))
	vim.keymap.set("n", "<Up>", function() select(-1) end, vim.tbl_extend("force", opts, { desc = "fix: prev" }))
	vim.keymap.set("n", "<Esc>", M.close, vim.tbl_extend("force", opts, { desc = "fix: cancel" }))
end

return M
