-- The transcript window, its paired compose window, and the buffers/session they belong to --
-- everything about displaying a conversation or a change view. No knowledge of the model; see
-- ask/model for that. The window and the session are separate lifetimes: closing the window
-- only hides it (the buffers and session_id survive in M.state), so M.reopen brings the same
-- conversation back. A fresh M.ensure with no M.state picks up the root's saved conversation
-- (ask/session.lua), if any -- that is what survives a restart.
--
-- Orchestration only: window lifecycle lives here, turn rendering in transcript.lua, the
-- pending-turn float in queue.lua, change-view mode in diff.lua -- each takes M.state
-- explicitly rather than reaching for it via require, so there's no cycle back to this file.
local M = {}
local transcript = require("ask.panel.transcript")
local queue = require("ask.panel.queue")
local diff = require("ask.panel.diff")
local discuss = require("ask.panel.discuss")
local memory_view = require("ask.panel.memory_view")
local help = require("ask.panel.help")
local buffer = require("ask.panel.buffer")
local keymap = require("ask.panel.keymap")
local session = require("ask.session")

-- the full bind list lives in keymap.lua's registry, not here -- this is just "press ? to
-- see it."
local IDLE_HINT = "? for help"

-- `mode`/`diff` turn the transcript's own window into a change view instead of opening a
-- second one, so the ask window stays the one surface regardless of what it shows. `queued`:
-- see ask/panel/queue.lua. memory_view/help have no state of their own -- a self-wiping
-- buffer (see ask/panel/mode.lua's M.show_page) is all either one needs.
M.state = nil -- { win, buf, input_win, input_buf, session_id, root, mode, diff, queued }

-- called for a real chat-turn submit (<CR> when not in diff mode), and for the memory
-- view keymap -- both set once via M.setup, not threaded through every M.ensure call.
local on_send, on_memory_view, on_new_chat

-- both windows, not just the transcript's -- a bare :q or <C-w>c on just one of them bypasses
-- our own q/<Esc> keymaps (which close both), and a half-dead pair must count as closed or
-- M.ensure never reopens the other half.
local function window_open()
	return M.state ~= nil and vim.api.nvim_win_is_valid(M.state.win) and vim.api.nvim_win_is_valid(M.state.input_win)
end

function M.set_status(text)
	if M.state and vim.api.nvim_win_is_valid(M.state.input_win) then vim.wo[M.state.input_win].winbar = text end
end

function M.reset_status() M.set_status(IDLE_HINT) end

function M.focus_compose()
	if not window_open() then return end
	vim.api.nvim_set_current_win(M.state.input_win)
	vim.cmd("startinsert!")
end

-- new_chat clears the session outright -- unlike memory/help (mode.exit now returns to an
-- active review afterward instead of dropping it, so they're safe to interrupt it with), there
-- is no sane "undo" for wiping the conversation mid-review, so this one alone stays guarded.
local function guard_diff(fn)
	return function(...)
		if M.state and M.state.mode == "diff" then
			vim.notify("ask: resolve the pending change first (<leader>ay/<leader>an)", vim.log.levels.WARN)
			return
		end
		return fn(...)
	end
end

-- only steal focus into Insert mode if you were already looking at the panel -- an answer
-- landing while you've switched back to your code shouldn't yank you away.
function M.focus_if_active()
	if not M.state then return end
	local cur = vim.api.nvim_get_current_win()
	if cur == M.state.win or cur == M.state.input_win then M.focus_compose() end
end

function M.start_turn(label)
	return transcript.start_turn(M.state, label)
end

-- quotes a visual selection (or anything else) into the compose box and focuses it.
function M.set_compose(lines)
	transcript.set_compose(M.state, lines)
	M.focus_compose()
end

-- enters discuss mode, same orchestration diff's own entry gets: show it, then layer help/
-- memory_view onto its buffer the same way M.show_change does for diff's target_buf (keymap.apply
-- skips any action not supplied, so this is additive, never a second conflicting bind).
function M.show_discuss(state, opts)
	discuss.show(state, opts)
	if state.diff and state.diff.discuss_buf then
		keymap.apply("discuss", state.diff.discuss_buf, { help = function() help.show(state) end, memory_view = on_memory_view })
	end
end

-- the Visual-mode half of diff's discuss keymap (ask/panel/diff.lua's show_change binds it
-- directly, not through keymap.lua's registry -- see that file's comment on why). A static
-- global entrypoint, since the <cmd>lua string it's bound from can't close over M.state.
function M.discuss_selection()
	if M.state and M.state.diff then M.show_discuss(M.state, { from_visual_selection = true }) end
end

function M.enqueue()
	queue.enqueue(M.state)
end

function M.pop_queued()
	return queue.pop_queued(M.state)
end

function M.cancel_queued()
	queue.cancel_queued(M.state)
end

-- hides both windows -- buffers and session live on in M.state for M.reopen, compose's draft
-- text included. Only the queued flag itself doesn't survive: cancel_queued just un-marks it,
-- so a turn finishing after this point has nothing to auto-send -- the text stays put as an
-- ordinary draft once reopened, same as closing with nothing queued at all. A pending diff
-- review has no such fallback (abandoning it here, as a reject, is the only option once the
-- window showing it is about to disappear).
function M.close()
	if not window_open() then return end
	M.cancel_queued()
	diff.abandon(M.state)
	if vim.api.nvim_win_is_valid(M.state.input_win) then vim.api.nvim_win_close(M.state.input_win, true) end
	vim.api.nvim_win_close(M.state.win, true)
end

-- splits the transcript window to carve a small, fixed, always-visible strip at its own bottom
-- for the compose box -- a pinned input, not a moving target at the tail of a scrolling buffer.
local function open_windows(buf, input_buf)
	local prev_win = vim.api.nvim_get_current_win()
	-- vnew/new (fresh blank buffer), not vsplit/split (duplicates the current window's buffer)
	-- -- splitting from a sidebar like neo-tree would briefly put its buffer in a second
	-- window, and sidebar plugins can react by reopening into it before we swap the buffer out.
	vim.cmd("botright vnew")
	vim.cmd("vertical resize " .. math.floor(vim.o.columns * 0.4))
	local win = vim.api.nvim_get_current_win()
	local scratch = vim.api.nvim_win_get_buf(win)
	vim.api.nvim_win_set_buf(win, buf)
	pcall(vim.api.nvim_buf_delete, scratch, { force = true })
	-- plain 'wrap' breaks at the exact column edge, mid-word -- 'linebreak' breaks at word
	-- boundaries instead (at 'breakat' chars), 'breakindent' keeps a wrapped line's continuation
	-- aligned under where it started rather than back at column 0.
	vim.wo[win].wrap, vim.wo[win].linebreak, vim.wo[win].breakindent = true, true, true
	-- a transcript reads as a document, not code -- no editor gutter
	vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn = false, false, "no"
	-- without this, 'equalalways' (on by default) re-equalizes every vertical split's width on
	-- any layout-affecting event -- including a plain terminal resize (a tmux pane zoom, for
	-- one) -- snapping this deliberately-unequal split back to 50/50 even though nothing here
	-- ever asked for that.
	vim.wo[win].winfixwidth = true

	vim.cmd("belowright new")
	vim.cmd("resize 3")
	local input_win = vim.api.nvim_get_current_win()
	local scratch2 = vim.api.nvim_win_get_buf(input_win)
	vim.api.nvim_win_set_buf(input_win, input_buf)
	pcall(vim.api.nvim_buf_delete, scratch2, { force = true })
	vim.wo[input_win].wrap, vim.wo[input_win].linebreak, vim.wo[input_win].breakindent = true, true, true
	vim.wo[input_win].number, vim.wo[input_win].relativenumber, vim.wo[input_win].signcolumn = false, false, "no"
	vim.wo[input_win].winbar = IDLE_HINT
	-- same reasoning as win's winfixwidth, for the other axis -- this one's fixed 3-line height
	-- is just as exposed to 'equalalways' on a resize.
	vim.wo[input_win].winfixwidth = true
	vim.wo[input_win].winfixheight = true

	vim.api.nvim_set_current_win(prev_win)
	-- resizing/repurposing existing windows to make room (a sidebar like neo-tree included)
	-- can leave its content rendered stale against its old size until something forces a
	-- repaint -- same class of bug as the diff view's own resize glitch, different trigger
	-- (an internal split, not a VimResized-worthy terminal resize).
	vim.cmd("redraw!")
	return win, input_win
end

-- shows the panel, reopening closed-but-still-alive windows before ever starting fresh.
function M.ensure(root)
	if M.state and M.state.root ~= root then
		-- a different project: the open panel, if any, belongs to the old one. Abandon it
		-- (its own session is already saved on disk under its own root) and start fresh --
		-- that fresh start loads THIS root's own saved conversation, not the old one's.
		M.cancel_queued()
		diff.abandon(M.state)
		if vim.api.nvim_win_is_valid(M.state.win) then pcall(vim.api.nvim_win_close, M.state.win, true) end
		if vim.api.nvim_win_is_valid(M.state.input_win) then pcall(vim.api.nvim_win_close, M.state.input_win, true) end
		M.state = nil
	end
	if window_open() then return end
	if M.state then
		-- a bare :q on just one of the pair leaves the other one lingering -- close it before
		-- opening a fresh pair, or the stale survivor stays on screen as an orphan duplicate.
		if vim.api.nvim_win_is_valid(M.state.win) then pcall(vim.api.nvim_win_close, M.state.win, true) end
		if vim.api.nvim_win_is_valid(M.state.input_win) then pcall(vim.api.nvim_win_close, M.state.input_win, true) end
	end
	if M.state and vim.api.nvim_buf_is_valid(M.state.buf) and vim.api.nvim_buf_is_valid(M.state.input_buf) then
		M.state.win, M.state.input_win = open_windows(M.state.buf, M.state.input_buf)
		-- open_windows always shows the transcript -- a raw :q/<C-w>c (bypassing mode.exit)
		-- can leave state.mode stale from whatever was active when the window disappeared. If
		-- a change view was active, put the real file back up instead of silently dropping
		-- back to chat; memory view and help don't earn that, they're just a peek.
		if M.state.mode == "diff" and M.state.diff then
			vim.api.nvim_win_set_buf(M.state.win, M.state.diff.target_buf)
		elseif M.state.mode == "memory_view" or M.state.mode == "help" then
			M.state.mode = "chat"
		end
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "hide", false
	vim.bo[buf].filetype = "markdown" -- render-markdown.nvim + treesitter's code-block injection, for free
	vim.bo[buf].modifiable = false -- a transcript you read, not one you edit -- buffer.with_writable lifts this for our own writes

	local input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[input_buf].buftype, vim.bo[input_buf].bufhidden, vim.bo[input_buf].swapfile = "nofile", "hide", false
	-- same filetype as the transcript -- a quoted selection (M.set_compose) renders as a real
	-- code block while you're still composing the question, not just once it's sent.
	vim.bo[input_buf].filetype = "markdown"

	local win, input_win = open_windows(buf, input_buf)
	M.state = {
		win = win, buf = buf, input_win = input_win, input_buf = input_buf,
		session_id = nil, root = root, mode = "chat", diff = nil, queued = nil,
	}

	local saved = session.load(root)
	M.state.session_id = saved.session_id
	for _, t in ipairs(saved.turns) do
		transcript.start_turn(M.state, t.question):update(t.answer)
	end

	keymap.apply("transcript", buf, {
		close = M.close, focus_compose = M.focus_compose, memory_view = on_memory_view,
		new_chat = guard_diff(on_new_chat), help = function() help.show(M.state) end,
	})

	-- Empty Enter does nothing (<S-CR> inserts a literal newline). discuss mode routes to its
	-- own side conversation; any other non-chat mode just drops the text. Both on_send and
	-- discuss.send return whether a turn started: only then is the text spent -- queued/busy,
	-- it stays exactly as typed, free to keep editing until it does go out.
	local function submit()
		local typed = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
		local text = vim.trim(table.concat(typed, "\n"))
		if text == "" then return end
		if M.state.mode == "discuss" then
			if discuss.send(M.state, text) then
				vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "" })
			end
			return
		end
		if M.state.mode ~= "chat" then
			vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "" })
			return
		end
		if on_send(text) then
			vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "" })
		end
	end

	keymap.apply("compose", input_buf, {
		close = M.close, help = function() help.show(M.state) end,
		memory_view = on_memory_view, send = submit,
		accept = function() diff.accept(M.state) end, reject = function() diff.reject(M.state) end,
	})
	vim.api.nvim_create_autocmd(
		{ "TextChanged", "TextChangedI" },
		{ buffer = input_buf, callback = function() transcript.recolor_compose(M.state) end }
	)
end

-- Normal-mode <leader>aa with no selection: bring back whatever's already there instead of
-- no-op'ing. Nothing to bring back if no panel exists yet. The stale-mode fixup (put a change
-- view's real file back up; drop a stale memory/help back to chat) lives in M.ensure itself
-- now, so every caller gets it, not just this one.
function M.reopen()
	if window_open() then
		vim.api.nvim_set_current_win(M.state.win)
		return
	end
	if not M.state then return end
	M.ensure(M.state.root)
end

-- empties the transcript and forgets the session -- the next turn mints a new one. Clearing
-- what's on disk is the caller's concern (ask/session.lua).
function M.reset()
	if not M.state then return end
	M.cancel_queued()
	M.state.session_id = nil
	buffer.with_writable(M.state, function()
		vim.api.nvim_buf_clear_namespace(M.state.buf, -1, 0, -1)
		vim.api.nvim_buf_set_lines(M.state.buf, 0, -1, false, { "" })
	end)
end

-- opts = { root, target_buf, old_text, new_text, on_resolved(decision, comment_text,
-- skip_reason) }, see diff.lua. Both fail-safes checked before M.ensure, so neither ever opens
-- a panel just to say "skipped" -- a different root's own pending review doesn't count here;
-- M.ensure abandons that one when it switches roots, same as it always has.
function M.show_change(opts)
	if M.state and M.state.root == opts.root and M.state.diff then
		opts.on_resolved(nil, nil, "another review is already pending in nvim -- resolve it first")
		return
	end
	if vim.bo[opts.target_buf].modified then
		opts.on_resolved(nil, nil, "target buffer already had unsaved changes, skipped review")
		return
	end
	if opts.old_text == opts.new_text then
		opts.on_resolved(nil, nil, "the proposed change doesn't actually differ from the current content, skipped review")
		return
	end
	M.ensure(opts.root)
	diff.show_change(M.state, opts)
	-- diff's own keymap context lists ?/m too (ask/panel/keymap.lua) -- diff.lua doesn't have
	-- help/on_memory_view in scope to wire them itself, so add them here, same buffer, same
	-- context, right after. keymap.apply skips any action not supplied, so this only ever
	-- layers these two on top of what diff.lua already bound; nothing to touch if the fail-safe
	-- inside diff.show_change tripped and no review actually opened.
	if M.state.diff then
		keymap.apply("diff", opts.target_buf, {
			help = function() help.show(M.state) end,
			memory_view = on_memory_view,
		})
	end
end

-- records: see ask/memory.lua's M.read. Read-only -- see memory_view.lua.
function M.show_memory(records)
	memory_view.show(M.state, records)
end

-- opts = { on_send(text), on_memory_view(), on_new_chat() }, called by setup once.
function M.setup(opts)
	on_send = opts.on_send
	on_memory_view = opts.on_memory_view
	on_new_chat = opts.on_new_chat
	transcript.ensure_highlight()

	-- a terminal/window resize can leave the diff view's virt_lines decorations rendered
	-- stale -- still showing the pre-resize layout even though the buffer and extmarks
	-- underneath are already correct (confirmed: only the screen, not the data, goes stale).
	-- redraw! forces nvim to recompute the whole screen from scratch instead of trusting
	-- whatever it diffed against the old window size.
	vim.api.nvim_create_autocmd("VimResized", {
		callback = function()
			if window_open() then vim.cmd("redraw!") end
		end,
	})
end

return M
