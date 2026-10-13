-- The engine: idle trigger, merge every source's fixes, hand labels to fix/ui, apply
-- whichever gets accepted. No blink.cmp involvement below this file — a fix isn't a completion.
local ui = require("fix.ui")
local M = {}

local SOURCES = { require("fix.identifier_fix"), require("fix.code_actions") }

-- the merged list currently shown, so the ui's accept callback (an index) can find its .apply —
-- only one ui is ever open at a time.
local shown = nil

-- a raw edit looks like typing to blink's own popups (not Insert-mode scoped), so it pops up
-- for whatever's now valid even though nothing here was typed. Close everything, just in case.
local function clear_blink_artifacts()
	vim.schedule(function()
		pcall(function() require("blink.cmp.signature.window").close() end)
		pcall(function() require("blink.cmp").hide() end)
		pcall(function() require("blink.cmp").cancel() end)
	end)
end

local function on_accept(index)
	local fix = shown[index]
	shown = nil
	fix.apply(clear_blink_artifacts)
end

-- the diagnostic the open popup is showing fixes for, as a range key — not just "is there a
-- diagnostic at the cursor", since a line can carry several and moving between them must count
-- as leaving the first one.
local shown_diag_key = nil

local function diag_key(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local lnum, col = cursor[1] - 1, cursor[2]
	for _, d in ipairs(vim.diagnostic.get(bufnr, { lnum = lnum })) do
		local end_lnum, end_col = d.end_lnum or d.lnum, d.end_col or (d.col + 1)
		if (d.lnum < lnum or col >= d.col) and (end_lnum > lnum or col < end_col) then
			return d.lnum .. ":" .. d.col .. ":" .. end_lnum .. ":" .. end_col
		end
	end
	return nil
end

-- every source's fixes, in a fixed slot per source so the merge order is deterministic
-- regardless of which async request finishes first — identifier fixes rank first: a real typo
-- fix should outrank a generic quickfix for the same spot.
local function maybe_show(bufnr)
	if ui.is_open() then return end -- CursorHold refires every updatetime while idle; don't re-show and reset the selection
	local key = diag_key(bufnr)
	local results, pending = {}, #SOURCES
	local function done()
		pending = pending - 1
		if pending > 0 then return end
		local merged = {}
		for _, r in ipairs(results) do
			vim.list_extend(merged, r)
		end
		if #merged == 0 then return end
		shown = merged
		shown_diag_key = key
		local labels = {}
		for i, fix in ipairs(merged) do
			labels[i] = fix.label
		end
		ui.open(bufnr, labels, on_accept)
	end
	for i, source in ipairs(SOURCES) do
		source.find(bufnr, function(fixes)
			results[i] = fixes
			done()
		end)
	end
end

function M.setup()
	-- on idle, read what the server already knows (diagnostics, hover, signatureHelp, workspace
	-- symbols, code actions) and offer the ground-truth fix. Needs a live updatetime; CursorHold
	-- otherwise waits 4s.
	vim.o.updatetime = 300

	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
			local bufnr = args.buf
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client then return end
			-- Normal mode only — Insert mode's idle pauses are part of typing, not "stopped to
			-- look something up," and a popup there was stealing <Tab> from blink mid-composition.
			if client:supports_method("textDocument/hover") or client:supports_method("textDocument/codeAction") then
				vim.api.nvim_create_autocmd("CursorHold", {
					buffer = bufnr,
					callback = function() maybe_show(bufnr) end,
				})
			end
		end,
	})

	-- the ui doesn't close itself the way a typing-triggered menu does — without this it sits
	-- there once the cursor leaves the diagnostic it was opened for, including onto a
	-- different diagnostic on the same line.
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		callback = function()
			if ui.is_open() and diag_key(vim.api.nvim_get_current_buf()) ~= shown_diag_key then
				ui.close()
				shown_diag_key = nil
			end
		end,
	})

	-- a Normal-mode-only popup that's still open when typing resumes (cursor never left the
	-- diagnostic first) would otherwise claim <Tab>/<Down>/<Up> for Insert mode too — on the
	-- same buffer-local keys blink.cmp re-registers every InsertEnter, so leaving the popup
	-- open across that event clobbers blink's own binding until the next Insert-mode entry.
	vim.api.nvim_create_autocmd("InsertEnter", {
		callback = function()
			if ui.is_open() then
				ui.close()
				shown_diag_key = nil
			end
		end,
	})
end

return M
