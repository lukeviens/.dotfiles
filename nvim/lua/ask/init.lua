-- Public entrypoint: Visual-mode selection -> a typed question -> the model. Edits are always
-- allowed; each proposed change is reviewed as a real diff in the same window
-- (panel.show_change, called by fix/diff_review.lua) before it touches disk. The window and
-- transcript live in ask/panel/, the model interface in ask/model/, distillation in
-- ask/memory.lua, saved chats in ask/session.lua -- this file only wires a submitted turn into
-- a request and back.
local M = {}
local panel = require("ask.panel")
local model = require("ask.model")
local memory = require("ask.memory")
local session = require("ask.session")

local function project_root(bufnr)
	return vim.fs.root(bufnr, { ".git", "go.mod" }) or vim.fn.getcwd()
end

-- getregion knows charwise, linewise and blockwise, and never cuts a multibyte char in half.
local function selected_text()
	local lines = vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
	return table.concat(lines, "\n")
end

local function quote_block(bufnr, text)
	local filetype = vim.bo[bufnr].filetype
	return string.format(
		"File: %s\nLanguage: %s\n\n```%s\n%s\n```",
		vim.api.nvim_buf_get_name(bufnr), filetype, filetype, text
	)
end

-- Only one claude -p call runs at a time per panel -- two concurrently would both think they
-- own the same turn:update() render region and corrupt each other's output. A submit while
-- busy goes to panel.enqueue (depth 1, see its own comment); the queued turn, if any, fires
-- the moment the running one finishes.
local busy = false

local function run_turn(text)
	busy = true
	-- the panel this turn belongs to. Asking from another project mid-turn replaces
	-- panel.state; the answer still lands here, in its own transcript and its own session.
	local state = panel.state
	local turn = panel.start_turn(text) -- shows exactly what was typed
	model.run({
		-- what's actually sent folds in everything distilled so far -- additive to --resume's
		-- native session, not a replacement; a no-op until anything's been distilled.
		prompt = memory.inject(state.session_id, text),
		root = state.root,
		session_id = state.session_id,
		-- guarded the same way state.session_id's write below effectively is: asking from a
		-- different project mid-turn replaces panel.state, and an unguarded panel.set_status
		-- would otherwise go on writing this turn's status into whichever panel is now current.
		on_status = function(text) if panel.state == state then panel.set_status(text) end end,
		on_delta = function(text_so_far) turn:update(text_so_far) end,
		on_done = function(ok, body, session_id)
			state.session_id = session_id
			turn:update(body)
			if session_id then session.append_turn(state.root, session_id, text, body) end
			-- an error body is the backend's text, not the conversation's.
			if ok and session_id then pcall(memory.distill_turn, session_id, text, body) end -- fire-and-forget
			busy = false
			local queued_text = panel.pop_queued()
			if queued_text and queued_text ~= "" then
				run_turn(queued_text)
			else
				panel.reset_status()
				panel.focus_if_active()
			end
		end,
	})
end

-- A real chat turn -- panel.lua has already filtered out diff-mode comments before calling
-- this, so this is only ever "actually ask claude something." Returns whether a turn actually
-- started: panel's submit() only clears the compose box when it did -- queued, the text stays
-- exactly as typed, since it never moved anywhere else to be edited.
local function on_send(text)
	if busy then
		panel.enqueue()
		return false
	end
	run_turn(text)
	return true
end

-- `m` from the transcript: a read-only peek at what's actually going into the next prompt
-- (memory.inject's own source data), not an invisible preamble you have to trust blindly.
local function on_memory_view()
	if not panel.state then return end
	panel.show_memory(memory.read(panel.state.session_id))
end

-- `n` from the transcript. Not mid-turn: the running turn's on_done would write the old
-- session_id straight back.
local function on_new_chat()
	if busy then
		vim.notify("ask: wait for the current turn to finish", vim.log.levels.WARN)
		return
	end
	session.clear(panel.state.root)
	panel.reset()
end

-- Quotes the selection into the compose box instead of a command-line prompt -- one place to
-- type the question, and the quote sits there editable before sending.
function M.ask()
	local bufnr = vim.api.nvim_get_current_buf()
	local text = selected_text()
	if text == "" then return end
	panel.ensure(project_root(bufnr))
	local quote = vim.split(quote_block(bufnr, text), "\n", { plain = true })
	vim.list_extend(quote, { "", "" })
	panel.set_compose(quote)
end

-- Normal-mode <leader>aa: the open panel if there is one, else this root's saved
-- conversation -- after a restart there's no panel state, only what's on disk.
function M.show()
	if panel.state then
		panel.reopen()
	else
		panel.ensure(project_root(0))
		panel.focus_compose()
	end
end
M.show_change = panel.show_change

function M.setup()
	panel.setup({ on_send = on_send, on_memory_view = on_memory_view, on_new_chat = on_new_chat })
	vim.keymap.set("n", "<leader>aa", M.show, { desc = "Ask Claude: reopen panel" })
	-- A Visual-mode mapping to a bare Lua function never leaves Visual mode the way an
	-- operator does -- '<'/'>' go stale. <Esc> leaves cleanly (setting the marks) first.
	vim.keymap.set("v", "<leader>aa", "<Esc><cmd>lua require('ask').ask()<CR>", { desc = "Ask Claude about selection" })
end

return M
