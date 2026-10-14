-- Pure hunk computation + decoration rendering for an already-displayed buffer. No window-
-- opening logic here — that's ask/panel.lua's job (it owns the split); this only ever touches
-- a bufnr it's handed.
local M = {}

local NS = vim.api.nvim_create_namespace("fix_diff_review")
local COMMENT_NS = vim.api.nvim_create_namespace("fix_diff_comments")

-- portable across colorschemes, same pattern as ask/panel/transcript.lua's AskQuestion -- a
-- comment reads as a string literal, not code.
function M.ensure_highlight()
	if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "AskDiffComment" })) then
		vim.api.nvim_set_hl(0, "AskDiffComment", { link = "String", default = true })
	end
end

-- a_lines/b_lines: 0-indexed line arrays (as nvim_buf_get_lines returns), matching the slice
-- vim.diff's indices refer to. Returns one anchor extmark id per hunk (the added region's first
-- line, or the deletion's virt_lines if there's no added region) -- a stable position to
-- correlate comments against later, since extmarks track through edits automatically.
local function decorate(bufnr, hunks, old_lines)
	local anchors = {}
	for hunk_i, hunk in ipairs(hunks) do
		local start_a, count_a, start_b, count_b = hunk[1], hunk[2], hunk[3], hunk[4]
		local anchor_id

		if count_b > 0 then
			-- added/changed region: highlight the lines now in the buffer, 1-indexed start_b
			-- inclusive, count_b lines.
			for i = 0, count_b - 1 do
				local id = vim.api.nvim_buf_set_extmark(bufnr, NS, start_b - 1 + i, 0, {
					line_hl_group = "DiffAdd",
				})
				anchor_id = anchor_id or id
			end
		end

		if count_a > 0 then
			-- removed region: the old lines no longer exist in the buffer at all — render them
			-- as virt_lines, same primitive and anchor convention gitsigns uses in
			-- deleted_preview.lua:327-339 (place_inline_preview_lines), without its word-diff/
			-- statuscolumn matching. start_b follows unified-diff convention: the 1-indexed new
			-- line AFTER which this hunk sits, 0 meaning "at the very top".
			local removed = {}
			for i = 0, count_a - 1 do
				removed[#removed + 1] = { { old_lines[start_a + i] or "", "DiffDelete" } }
			end
			local topdelete = count_b == 0 and start_b == 0
			-- a change hunk (count_b > 0) anchors on the added region and shows the old lines
			-- directly above it, in place; a pure deletion has no added region to anchor on, so
			-- it anchors on the preceding line instead (or row 0, above, if at the very top).
			local anchor_row = topdelete and 0 or (start_b - 1)
			local id = vim.api.nvim_buf_set_extmark(bufnr, NS, anchor_row, 0, {
				virt_lines = removed,
				virt_lines_above = count_b > 0 or topdelete,
			})
			anchor_id = anchor_id or id
		end

		anchors[hunk_i] = anchor_id
	end
	return anchors
end

-- replaces bufnr's content with new_text and decorates the result. Returns the hunks (vim.diff's
-- raw indices), the buffer's prior lines (a caller can M.restore on reject), and one anchor
-- extmark id per hunk (see decorate, for M.comment_texts).
--
-- decorate() runs after the content is already replaced -- if it throws (a malformed hunk),
-- the buffer would otherwise sit there with the proposed text applied, marked modified, and no
-- caller ever wired up to resolve or restore it, permanently tripping show_change's own
-- "already modified" fail-safe on every later review of this same file. Revert and re-raise
-- instead, so a failed apply leaves no trace.
function M.apply(bufnr, old_text, new_text)
	local prior_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local old_lines = vim.split(old_text, "\n", { plain = true, trimempty = false })
	local hunks = vim.diff(old_text, new_text, { result_type = "indices" }) or {}

	local new_lines = vim.split(new_text, "\n", { plain = true, trimempty = false })
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
	local ok, anchors = pcall(decorate, bufnr, hunks, old_lines)
	if not ok then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, prior_lines)
		vim.bo[bufnr].modified = false
		error(anchors)
	end

	return hunks, prior_lines, anchors
end

-- a real buffer line, not virtual text -- normal editing (multi-line, backspace, ...) just
-- works. Tracked in its own namespace so M.comment_texts/M.strip_comment_lines can find it
-- regardless of whatever else happens to the buffer afterward. Returns the new line's row.
function M.add_comment_line(bufnr, row)
	vim.api.nvim_buf_set_lines(bufnr, row + 1, row + 1, false, { "" })
	vim.api.nvim_buf_set_extmark(bufnr, COMMENT_NS, row + 1, 0, { line_hl_group = "AskDiffComment" })
	return row + 1
end

-- removes every tracked comment line from the buffer -- called before clear/restore, so a
-- comment never reaches whatever actually gets evaluated or written. Highest row first, so an
-- earlier delete doesn't shift a later one's row out from under it. Deleting the line doesn't
-- remove its extmark on its own -- it orphans onto a neighboring row instead -- so each one is
-- deleted explicitly too.
function M.strip_comment_lines(bufnr)
	local marks = vim.api.nvim_buf_get_extmarks(bufnr, COMMENT_NS, 0, -1, {})
	table.sort(marks, function(a, b) return a[2] > b[2] end)
	for _, m in ipairs(marks) do
		vim.api.nvim_buf_set_lines(bufnr, m[2], m[2] + 1, false, {})
		vim.api.nvim_buf_del_extmark(bufnr, COMMENT_NS, m[1])
	end
end

-- every comment line's current text, paired with the nearest hunk anchor at or above it (both
-- move together under insertions -- see decorate). `line` is the hunk's own new-text line
-- number (start_b), a real line a human or model can point at, not an internal index. A comment
-- placed above every hunk (no anchor at or above its row) gets `line = nil` -- a general note,
-- not attributed to whichever hunk happens to be first. Call before M.strip_comment_lines --
-- the comment lines must still be there to read.
function M.comment_texts(bufnr, hunks, anchors)
	local anchor_rows = {}
	for i, id in ipairs(anchors) do
		anchor_rows[i] = vim.api.nvim_buf_get_extmark_by_id(bufnr, NS, id, {})[1]
	end

	local out = {}
	for _, c in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, COMMENT_NS, 0, -1, {})) do
		local row = c[2]
		local text = vim.trim(vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "")
		if text ~= "" then
			local nearest
			for i, arow in ipairs(anchor_rows) do
				if arow <= row and (not nearest or arow > anchor_rows[nearest]) then nearest = i end
			end
			local hunk = nearest and hunks[nearest]
			out[#out + 1] = {
				line = hunk and hunk[3] or nil,
				hunk_text = hunk and vim.api.nvim_buf_get_lines(bufnr, anchor_rows[nearest], anchor_rows[nearest] + 1, false)[1] or "",
				text = text,
			}
		end
	end
	table.sort(out, function(a, b) return (a.line or 0) < (b.line or 0) end)
	return out
end

-- marks the buffer clean -- its content now matches (accept, where the caller's own edit tool
-- is about to write this exact text) or already matched (reject/restore) what's on disk.
-- Without this, show_change's own "already modified" fail-safe blocks every later review of
-- this same file.
function M.clear(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
	vim.bo[bufnr].modified = false
end

function M.restore(bufnr, prior_lines)
	M.clear(bufnr)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, prior_lines)
	vim.bo[bufnr].modified = false
end

return M
