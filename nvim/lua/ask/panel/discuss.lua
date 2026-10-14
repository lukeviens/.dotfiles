-- A focused side conversation about a review -- a separate, read-only claude -p call (see
-- ask/model/claude.lua), resumed on the main session for full context, rendered into a scoped
-- transcript. Lives on state.diff itself, so it's disposed of with the review automatically.
-- Returning to the diff (mode.lua's M.exit) needs no code here -- state.diff stays untouched.
local M = {}
local mode = require("ask.panel.mode")
local transcript = require("ask.panel.transcript")
local model = require("ask.model")

local IDLE_HINT = "? for help"

-- mirrors ask/init.lua's own selected_text() -- duplicated rather than required back, which
-- would cycle (ask -> panel -> discuss -> ask) for three lines of code.
local function selected_text(bufnr)
	local lines = vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = vim.fn.visualmode() })
	return table.concat(lines, "\n")
end

-- resuming the session already has the diff in context -- only the framing (a discussion, not
-- license to edit) and any inline notes (never sent anywhere yet) need repeating here.
local function seed_prompt(d)
	local parts = {
		"I'm reviewing the change you just proposed to `" .. vim.api.nvim_buf_get_name(d.target_buf)
			.. "` and want to discuss it before deciding whether to accept or reject it. You can "
			.. "use Read/Grep/Glob to look at anything else you need, but you cannot make further "
			.. "edits right now -- that happens after we're done talking, if at all.",
	}
	local comments = require("fix.ui.diffview").comment_texts(d.target_buf, d.hunks, d.anchors)
	if #comments > 0 then
		parts[#parts + 1] = "Notes I've already left on specific lines:\n" .. require("ask.panel.diff").format_comments(comments)
	end
	return table.concat(parts, "\n\n")
end

-- opts.from_visual_selection: carries the current selection into the next M.send call, first
-- question or not -- decoupled from "is this the first turn" so either can happen in any order.
function M.show(state, opts)
	local d = state.diff
	if not d then return end
	if opts and opts.from_visual_selection then
		d.discuss_pending_selection = selected_text(d.target_buf)
	end
	if not d.discuss_buf then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "hide", false
		vim.bo[buf].filetype = "markdown"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Discussing this change", "" })
		vim.bo[buf].modifiable = false
		d.discuss_buf = buf
	end
	-- help/memory_view aren't wired here -- ask/panel/init.lua layers them onto d.discuss_buf
	-- right after this call, same as it already does for diff's target_buf (keymap.apply
	-- skips any action not supplied, so that's additive, not a second, conflicting bind).
	mode.enter(state, "discuss", d.discuss_buf, {
		-- mode.exit returns to whichever of diff/discuss is d.active_view -- entering discuss
		-- just set it to "discuss", so leaving discuss itself has to flip it back to "diff"
		-- first, or mode.exit can't tell that apart from help/memory_view merely interrupting
		-- an active discussion (where active_view must stay "discuss" to return to it).
		close = function()
			d.active_view = "diff"
			mode.exit(state)
		end,
	}, require("ask.panel.keymap").winbar_hint("discuss"))
end

-- a real chat turn, same machinery as ask/init.lua's run_turn, scoped to d.discuss_buf and
-- read-only. Returns whether it started -- submit() only clears compose when it did.
function M.send(state, text)
	local d = state.diff
	if not d then return false end
	if d.discuss_busy then
		vim.notify("ask: still waiting for a reply", vim.log.levels.WARN)
		return false
	end
	d.discuss_busy = true

	local prompt = text
	if d.discuss_pending_selection then
		prompt = "About this part:\n```\n" .. d.discuss_pending_selection .. "\n```\n\n" .. text
		d.discuss_pending_selection = nil
	end
	if not d.discuss_session_id then
		prompt = seed_prompt(d) .. "\n\n" .. prompt
	end

	local turn = transcript.start_turn({ buf = d.discuss_buf, win = state.win }, text)
	model.run({
		prompt = prompt,
		root = state.root,
		session_id = d.discuss_session_id or state.session_id,
		read_only = true,
		-- d can be gone by the time this fires -- the review may have resolved or been
		-- abandoned while the question was still in flight.
		on_status = function(s)
			if state.diff == d and vim.api.nvim_win_is_valid(state.input_win) then
				vim.wo[state.input_win].winbar = s
			end
		end,
		on_delta = function(partial) turn:update(partial) end,
		on_done = function(ok, body, session_id)
			if state.diff ~= d then return end
			d.discuss_busy = false
			d.discuss_session_id = session_id
			turn:update(body)
			if vim.api.nvim_win_is_valid(state.input_win) then vim.wo[state.input_win].winbar = IDLE_HINT end
		end,
	})
	return true
end

return M
