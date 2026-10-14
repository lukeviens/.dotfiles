-- Change-view mode: repurposes the transcript's own window to show a real file with a diff
-- applied, instead of opening a second window.
local M = {}
local diffview = require("fix.ui.diffview")
local mode = require("ask.panel.mode")
local model = require("ask.model")
local keymap = require("ask.panel.keymap")

-- Ends the active change view exactly once: clears the buffer-local keys off the real file
-- buffer, swaps the window back, reports the decision plus the final comment text.
--
-- Takes `d` explicitly and checks identity against state.diff, not just non-nil: resolving
-- with 2+ comments goes through an async dedup call first, and a second review (a concurrent
-- tool call, or a second ask/ turn) can take over state.diff before that callback fires.
local function finish_change(state, d, decision, comment_text)
	if state.diff ~= d then return end
	state.diff = nil
	pcall(vim.keymap.del, "n", "<leader>ay", { buffer = d.target_buf })
	pcall(vim.keymap.del, "n", "<leader>an", { buffer = d.target_buf })
	pcall(vim.keymap.del, "n", "<leader>ac", { buffer = d.target_buf })
	pcall(vim.keymap.del, "n", "<leader>ad", { buffer = d.target_buf })
	pcall(vim.keymap.del, "v", "<leader>ad", { buffer = d.target_buf })
	mode.exit(state)
	d.on_resolved(decision, comment_text)
end

-- exported for ask/panel/discuss.lua, which seeds a side conversation with the same comments.
function M.format_comments(comments)
	local lines = {}
	for _, c in ipairs(comments) do
		if c.line then
			lines[#lines + 1] = string.format("Line %d (`%s`): %s", c.line, vim.trim(c.hunk_text), c.text)
		else
			lines[#lines + 1] = "General comment: " .. c.text
		end
	end
	return table.concat(lines, "\n")
end
local format_comments = M.format_comments

-- cursor on a line in the diff view -> a real, highlighted buffer line right below it, in
-- Insert mode. Bound only in the "diff" keymap context (ask/panel/keymap.lua) -- an inline
-- comment needs the actual lines in front of you.
--
-- Comments stay single-line: a real Enter would split the line, and the tracking extmark (one
-- point, one row) doesn't follow -- the second half becomes untracked and silently survives
-- into the final content. <CR> ends composing instead, removed again on InsertLeave so it
-- never lingers over normal editing elsewhere in the buffer.
function M.add_inline_comment(state)
	local d = state.diff
	if not d then return end
	local row = vim.api.nvim_win_get_cursor(state.win)[1] - 1
	local new_row = diffview.add_comment_line(d.target_buf, row)
	vim.api.nvim_win_set_cursor(state.win, { new_row + 1, 0 })
	vim.keymap.set("i", "<CR>", "<Esc>", { buffer = d.target_buf, nowait = true })
	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = d.target_buf,
		once = true,
		callback = function() pcall(vim.keymap.del, "i", "<CR>", { buffer = d.target_buf }) end,
	})
	-- startinsert called synchronously from inside a keymap callback doesn't reliably stick --
	-- deferred a tick so it applies after this callback's own dispatch finishes, not racing it.
	vim.schedule(function() vim.cmd("startinsert") end)
end

-- reads back every inline comment, strips them from the buffer either way, and hands callback
-- a single formatted string (or nil) -- 2+ comments get a dedup pass through model.quick first
-- (ask/memory.lua's M.distill_turn uses the same one-shot call), skipped for 0 or 1 since
-- there's nothing to merge.
local function resolve_comments(d, callback)
	local comments = diffview.comment_texts(d.target_buf, d.hunks, d.anchors)
	diffview.strip_comment_lines(d.target_buf)
	if #comments == 0 then
		callback(nil)
	elseif #comments == 1 then
		callback(format_comments(comments))
	else
		local prompt = "Merge obvious duplicate/near-duplicate code review comments below, keep "
			.. "distinct ones as-is, preserve the exact 'Line N (`...`): text' format, one per "
			.. "line, nothing else:\n\n" .. format_comments(comments)
		model.quick(prompt, function(ok, body)
			callback(ok and body ~= "" and body or format_comments(comments))
		end)
	end
end

-- the original claude -p call never sees ask/panel/discuss.lua's side conversation, only this
-- one sentence once it's over -- the human already did the arguing, it just needs the outcome.
local function qualify_discussed(d, decision, comment_text)
	if not d.discuss_session_id then return comment_text end
	if comment_text then return "(discussed with the user first) " .. comment_text end
	return "Discussed with the user, then " .. decision .. "ed."
end

-- bound on target_buf and the compose box -- a no-op without a pending review. `d.resolving`
-- guards a second press while the first's dedup call is still in flight: without it, the
-- second press races ahead synchronously and the first's result gets silently dropped by the
-- identity check below.
function M.accept(state)
	local d = state.diff
	if not d or d.resolving then return end
	d.resolving = true
	resolve_comments(d, function(comment_text)
		if state.diff ~= d then return end -- a newer review already took over
		diffview.clear(d.target_buf)
		finish_change(state, d, "accept", qualify_discussed(d, "accept", comment_text))
	end)
end

function M.reject(state)
	local d = state.diff
	if not d or d.resolving then return end
	d.resolving = true
	resolve_comments(d, function(comment_text)
		if state.diff ~= d then return end -- a newer review already took over
		diffview.restore(d.target_buf, d.prior_lines)
		finish_change(state, d, "reject", qualify_discussed(d, "reject", comment_text))
	end)
end

-- Abandons a pending review without accept/reject -- panel showing something else, or closing
-- outright. Same as reject, but synchronous and comment-free: nothing was explicitly submitted.
function M.abandon(state)
	local d = state.diff
	if not d then return end
	diffview.strip_comment_lines(d.target_buf)
	diffview.restore(d.target_buf, d.prior_lines)
	finish_change(state, d, "reject", nil)
end

-- opts = { target_buf, old_text, new_text, on_resolved(decision, comment_text, skip_reason) }.
-- decision nil means nothing was touched -- skip_reason says why. Caller must have already
-- called M.ensure; this only handles change-view mechanics on an already-open panel.
function M.show_change(state, opts)
	-- nothing else serializes two reviews arriving close together -- without this, a second
	-- one would silently overwrite state.diff, orphaning the first with no indication it was
	-- dropped.
	if state.diff then
		opts.on_resolved(nil, nil, "another review is already pending in nvim -- resolve it first")
		return
	end
	if vim.bo[opts.target_buf].modified then
		opts.on_resolved(nil, nil, "target buffer already had unsaved changes, skipped review")
		return
	end
	-- a caller-side bug upstream (a hook computing an edit that didn't actually change
	-- anything) must never surface as a real-looking diff with nothing in it -- old == new
	-- means there's nothing to review, full stop, regardless of why.
	if opts.old_text == opts.new_text then
		opts.on_resolved(nil, nil, "the proposed change doesn't actually differ from the current content, skipped review")
		return
	end
	local hunks, prior_lines, anchors = diffview.apply(opts.target_buf, opts.old_text, opts.new_text)
	state.diff = {
		target_buf = opts.target_buf,
		prior_lines = prior_lines,
		old_text = opts.old_text,
		new_text = opts.new_text,
		hunks = hunks,
		anchors = anchors,
		on_resolved = opts.on_resolved,
	}

	mode.enter(state, "diff", opts.target_buf, {
		accept = function() M.accept(state) end,
		reject = function() M.reject(state) end,
		comment = function() M.add_inline_comment(state) end,
		discuss = function() require("ask.panel").show_discuss(state) end,
	}, keymap.winbar_hint("diff"))
	vim.keymap.set("v", "<leader>ad", "<Esc><cmd>lua require('ask.panel').discuss_selection()<CR>", {
		buffer = opts.target_buf, nowait = true, desc = "ask: discuss selection",
	})
end

return M
