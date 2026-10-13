-- real gopls quickfixes, filtered to actual diagnostic fixes (not ambient "browse docs"-style
-- actions), as fix/init.lua's second source alongside identifier_fix.
local adapters = require("fix.adapters")
local M = {}

-- gopls also returns ambient actions available on almost any symbol regardless of errors
-- ("browse docs", "add test"...); only "quickfix" is a real diagnostic fix.
local function is_quickfix(action)
	return type(action.kind) == "string" and action.kind:match("^quickfix")
end

-- "declare it as a new variable/function/field" is almost never right when a real typo fix
-- exists for the same spot. The exact wording is this server's own (adapters.lua); languages
-- with no entry just never suppress — the typo fix still outranks it either way.
local function is_declare_new(action, pattern)
	return pattern and type(action.title) == "string" and action.title:match(pattern)
end

-- only diagnostics whose own range the cursor is inside, not just anywhere on the same line.
local function diagnostics_at_cursor(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local lnum, col = cursor[1] - 1, cursor[2]
	local diags = {}
	for _, d in ipairs(vim.diagnostic.get(bufnr, { lnum = lnum })) do
		local end_lnum, end_col = d.end_lnum or d.lnum, d.end_col or (d.col + 1)
		if (d.lnum < lnum or col >= d.col) and (end_lnum > lnum or col < end_col) then
			diags[#diags + 1] = d
		end
	end
	return diags
end

local function request_actions(bufnr, callback)
	local diagnostics = diagnostics_at_cursor(bufnr)
	local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
	if #diagnostics == 0 or #clients == 0 then
		callback({})
		return
	end
	local declare_pattern = adapters.declare_pattern[vim.bo[bufnr].filetype]
	require("fix.identifier_fix").find(bufnr, function(typo_fixes)
		local has_typo_fix = #typo_fixes > 0
		local params = vim.lsp.util.make_range_params(0, clients[1].offset_encoding)
		params.context = { diagnostics = diagnostics }
		vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", params, function(results)
			local actions = {}
			for client_id, res in pairs(results) do
				if res.result then
					for _, action in ipairs(res.result) do
						if is_quickfix(action) and not (has_typo_fix and is_declare_new(action, declare_pattern)) then
							actions[#actions + 1] = { action = action, client_id = client_id }
						end
					end
				end
			end
			callback(actions)
		end)
	end)
end

-- the engine's one entry point: a list of {label, apply(done)}.
function M.find(bufnr, callback)
	request_actions(bufnr, function(actions)
		local items = {}
		for _, entry in ipairs(actions) do
			local action, client_id = entry.action, entry.client_id
			items[#items + 1] = {
				label = action.title,
				apply = function(done)
					local client = vim.lsp.get_client_by_id(client_id)
					if not client then
						done()
						return
					end
					local function run(resolved)
						if resolved.edit then
							vim.lsp.util.apply_workspace_edit(resolved.edit, client.offset_encoding)
						end
						if resolved.command then
							local cmd = type(resolved.command) == "table" and resolved.command or { command = resolved.command }
							client:exec_cmd(cmd, { bufnr = bufnr })
						end
						done()
					end
					local resolve_provider = type(client.server_capabilities.codeActionProvider) == "table"
						and client.server_capabilities.codeActionProvider.resolveProvider
					if not action.edit and resolve_provider then
						client:request("codeAction/resolve", action, function(err, resolved) run(err and action or resolved) end)
					else
						run(action)
					end
				end,
			}
		end
		callback(items)
	end)
end

return M
