-- Deterministic "did you mean X" for an undefined identifier, from three signals:
--   - spelling: edit distance against every in-scope name ("happened" -> "happening")
--   - type: what type the bad token is expected to be — member access (x.Field), assignment
--     from a call's return, or a bare call argument — matched against in-scope hover types
--     ("c" -> "clients", zero spelling overlap)
--   - workspace: workspace/symbol for a cross-file/cross-package rename
--     ("VerifyCodeSMS" -> "VerifySMSVerifcationCode", declared elsewhere)
-- All three just read what the server already knows, no model guessing. Type is the only
-- language-specific signal (adapters.lua); spelling and workspace work on any grammar.
local adapters = require("fix.adapters")
local M = {}

-- workspace/symbol gives a bare name ("Clients"); hover gives a qualified pointer
-- ("*clients.Clients") outside the same package — strip both to compare. A same-named
-- struct in an unrelated package colliding here is rare and livable.
local function bare_type_name(type_str)
	if not type_str then return type_str end
	return type_str:gsub("^%*", ""):match("([%w_]+)$") or type_str
end

local function edit_distance(a, b)
	local la, lb = #a, #b
	local d = {}
	for i = 0, la do
		d[i] = { [0] = i }
	end
	for j = 0, lb do
		d[0][j] = j
	end
	for i = 1, la do
		for j = 1, lb do
			local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
			d[i][j] = math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
		end
	end
	return d[la][lb]
end

-- edits as a fraction of the longer name's length, not a flat count — 3 edits is nearly
-- everything for a 4-letter name and almost nothing for a 15-letter one.
local MAX_DISTANCE_RATIO = 0.4

-- "VerifySMSVerifcationCode" -> {"Verify","SMS","Verifcation","Code"}; "from_user_id" -> {"from","user","id"}
local function chunk_identifier(name)
	local s = name:gsub("(%u+)(%u%l)", "%1 %2"):gsub("(%l)(%u)", "%1 %2"):gsub("[_%-]", " ")
	local chunks = {}
	for w in s:gmatch("%S+") do
		chunks[#chunks + 1] = w
	end
	return chunks
end

-- "req" is an exact prefix of "request", one of "login_verify_request"'s own chunks — as exact
-- a match as workspace search's chunk equality, just containment instead of requiring the whole
-- chunk. Whole-string edit distance alone never reaches across the rest of a long compound name.
local function chunk_prefix_match(bad, candidate)
	if #bad < 2 then return false end
	local bad_lower = bad:lower()
	for _, chunk in ipairs(chunk_identifier(candidate)) do
		if chunk:lower():sub(1, #bad_lower) == bad_lower then
			return true
		end
	end
	return false
end

-- gopls's workspace/symbol needs the query as an in-order subsequence of the real name, which
-- fails when a rename reorders its own chunks. Drop chunks from the end until something matches.
local function workspace_candidates(client, bad, callback)
	local chunks = chunk_identifier(bad)
	local function try(n)
		if n == 0 then
			callback({})
			return
		end
		local query = table.concat(chunks, "", 1, n)
		client:request("workspace/symbol", { query = query }, function(err, res)
			if err or not res or #res == 0 then
				try(n - 1)
				return
			end
			local names = {}
			for _, sym in ipairs(res) do
				names[#names + 1] = sym.name
			end
			callback(names)
		end)
	end
	try(#chunks)
end

-- "identifier"/"field_identifier" are the name-token types across most treesitter grammars.
-- Keeps each name's first position, for hover lookups later.
local NAME_TYPES = { identifier = true, field_identifier = true }

-- "package" (no enclosing scope_node) is visible everywhere; otherwise only within that same
-- scope node. Real Go scoping is point-of-declaration-to-end-of-block; this collapses to "same
-- enclosing function" — enough to stop a sibling function's own parameter leaking in as a candidate.
local function enclosing_scope_key(node, scope_node_types)
	while node do
		if scope_node_types[node:type()] then
			local row, col = node:start()
			return row .. ":" .. col
		end
		node = node:parent()
	end
	return "package"
end

-- a closure sees its own scope plus every scope it's nested inside, same as a real Go closure
-- captures its enclosing function's locals — the full ancestor chain, not just the nearest one.
local function scope_chain(node, scope_node_types)
	local chain = {}
	while node do
		if scope_node_types[node:type()] then
			local row, col = node:start()
			chain[#chain + 1] = row .. ":" .. col
		end
		node = node:parent()
	end
	chain[#chain + 1] = "package"
	return chain
end

-- a name only counts if it's actually declared here — a parameter, a var/const, or the left
-- side of ":=". Anything else (a package reference, a plain use of some other scope's name) is
-- a reference, not a declaration, and was never a candidate in the first place.
local DECL_PARENT_HAS_NAME_FIELD = {
	parameter_declaration = true,
	var_spec = true,
	const_spec = true,
	function_declaration = true,
	method_declaration = true,
}

local function is_declaration_node(node)
	local parent = node:parent()
	if not parent then return false end
	local ptype = parent:type()
	if DECL_PARENT_HAS_NAME_FIELD[ptype] then
		local ok, name_node = pcall(function() return parent:field("name")[1] end)
		return ok and name_node == node
	end
	if ptype == "expression_list" then
		local grandparent = parent:parent()
		if grandparent and grandparent:type() == "short_var_declaration" then
			local ok, left = pcall(function() return grandparent:field("left")[1] end)
			return ok and left == parent
		end
	end
	return false
end

-- different functions routinely reuse the same parameter name ("clients", "err", ...) — each
-- is its own declaration in its own scope, so keyed by (name, scope), not by name alone.
local function collect_names(node, bufnr, bad, scope_node_types, out)
	if NAME_TYPES[node:type()] and is_declaration_node(node) then
		local text = vim.treesitter.get_node_text(node, bufnr)
		if text ~= bad and text ~= "" then
			local by_scope = out[text]
			if not by_scope then
				by_scope = {}
				out[text] = by_scope
			end
			local scope = enclosing_scope_key(node, scope_node_types)
			if not by_scope[scope] then
				local row, col = node:start()
				by_scope[scope] = { row = row, col = col }
			end
		end
	end
	for child in node:iter_children() do
		collect_names(child, bufnr, bad, scope_node_types, out)
	end
end

-- the whole file, not just the enclosing function: a package-level name is valid everywhere.
local function file_scope(bufnr)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not parser_ok or not parser then return nil end
	local trees = parser:parse()
	return trees and trees[1] and trees[1]:root() or nil
end

local function node_at(bufnr, diag)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not parser_ok or not parser then return nil end
	parser:parse()
	return vim.treesitter.get_node({ bufnr = bufnr, pos = { diag.lnum, diag.col } })
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

local function hover_type(bufnr, client, parse_hover, row, col, callback)
	local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
	params.position = { line = row, character = col }
	client:request("textDocument/hover", params, function(err, res)
		if err or not res or not res.contents then
			callback(nil)
			return
		end
		local value = type(res.contents) == "table" and res.contents.value or res.contents
		callback(parse_hover(value))
	end)
end

-- is the bad token the operand of x.Field? ("field_identifier" would be Field itself — this
-- checks the OTHER side.) Generic tree-sitter field names, not gated to any one language.
local function member_access_field(bufnr, diag)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not parser_ok or not parser then return nil end
	parser:parse()
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { diag.lnum, diag.col } })
	local parent = node and node:parent()
	if not parent or parent:type() ~= "selector_expression" then return nil end
	local operand_ok, operand = pcall(function() return parent:field("operand")[1] end)
	if not operand_ok or operand ~= node then return nil end
	local field_ok, field_node = pcall(function() return parent:field("field")[1] end)
	if not field_ok or not field_node then return nil end
	return vim.treesitter.get_node_text(field_node, bufnr)
end

-- is the bad token the FIELD of x.Field, not the operand? (member_access_field above is the
-- mirror check, for when x itself is wrong.) A typo'd field on an otherwise-correct operand
-- needs the operand's real type, not the field's.
local function member_access_operand(bufnr, diag)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not parser_ok or not parser then return false end
	parser:parse()
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { diag.lnum, diag.col } })
	local parent = node and node:parent()
	if not parent or parent:type() ~= "selector_expression" then return false end
	local field_ok, field_node = pcall(function() return parent:field("field")[1] end)
	if not field_ok or field_node ~= node then return false end
	local operand_ok, operand = pcall(function() return parent:field("operand")[1] end)
	return operand_ok and operand ~= nil
end

-- the operand's real fields and methods, straight from completion as if "x." had just been
-- typed — ground truth from the server, not a guess at the type's shape. Position is the bad
-- field's own start, right after the dot and before any of the wrong text, so the typo itself
-- can't narrow what comes back.
local function member_candidates(client, diag, callback)
	local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
	params.position = { line = diag.lnum, character = diag.col }
	client:request("textDocument/completion", params, function(err, res)
		if err or not res then
			callback({})
			return
		end
		local items = res.items or res
		local names = {}
		for _, item in ipairs(items) do
			if item.kind == 2 or item.kind == 5 then -- LSP CompletionItemKind: Method=2, Field=5
				names[#names + 1] = item.label
			end
		end
		callback(names)
	end)
end

-- "req" in req.VerificationID isn't a plain value — what the surrounding call expects is the
-- wrong question (that's the call's own argument type). The right one: what type declares a
-- VerificationID member, via workspace/symbol (kind 8 = Field, 6 = Method — "x.Y" is the same
-- shape whether Y is a field or a method call, e.g. r.Context(); gopls's symbol name is itself
-- "Struct.Member", split there) — pure LSP spec, no server-specific text to parse.
local function expected_member_types(client, field_name, callback)
	client:request("workspace/symbol", { query = field_name }, function(err, res)
		if err or not res then
			callback({})
			return
		end
		local seen, types = {}, {}
		local suffix = "." .. field_name
		for _, sym in ipairs(res) do
			if (sym.kind == 8 or sym.kind == 6) and sym.name:sub(-#suffix) == suffix then
				local type_name = sym.name:sub(1, -(#suffix + 1))
				if not seen[type_name] then
					seen[type_name] = true
					types[#types + 1] = type_name
				end
			end
		end
		callback(types)
	end)
end

-- is the bad token on the LHS of "names := call()" or "names = call()" with a single call on
-- the RHS? Returns the callee's node and the token's 0-indexed position among the LHS names —
-- the callee's Nth return type is what it should be, member access pointed the other direction.
local function assignment_position(bufnr, diag)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not parser_ok or not parser then return nil end
	parser:parse()
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { diag.lnum, diag.col } })
	local lhs_list = node and node:parent()
	if not lhs_list or lhs_list:type() ~= "expression_list" then return nil end
	local stmt = lhs_list:parent()
	if not stmt then return nil end
	local left_ok, left = pcall(function() return stmt:field("left")[1] end)
	local right_ok, right = pcall(function() return stmt:field("right")[1] end)
	if not left_ok or not right_ok or left ~= lhs_list or not right then return nil end
	if right:named_child_count() ~= 1 then return nil end
	local call = right:named_child(0)
	if not call or call:type() ~= "call_expression" then return nil end
	local func_ok, func_node = pcall(function() return call:field("function")[1] end)
	if not func_ok or not func_node then return nil end
	local index = 0
	for i = 0, lhs_list:named_child_count() - 1 do
		if lhs_list:named_child(i) == node then
			index = i
			break
		end
	end
	return func_node, index
end

-- the callee's Nth return type, via hover on the callee — same text format as any other
-- hover, so parse_returns (adapters.lua) reads it the same way parse_hover reads a variable.
local function expected_assignment_types(client, func_node, bufnr, index, parse_returns, callback)
	local row, col = func_node:start()
	local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
	params.position = { line = row, character = col }
	client:request("textDocument/hover", params, function(err, res)
		if err or not res or not res.contents then
			callback({})
			return
		end
		local value = type(res.contents) == "table" and res.contents.value or res.contents
		local returns = parse_returns(value)
		local want = returns[index + 1]
		callback(want and { want } or {})
	end)
end

-- the bad token's expected type, if it's a call argument — signatureHelp works even though the
-- argument is undefined, since that's a semantic error, not a syntax one.
local function expected_arg_type(bufnr, diag, client, call_node, parse_param, callback)
	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not parser_ok or not parser then
		callback({})
		return
	end
	parser:parse()
	local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { diag.lnum, diag.col } })
	while node and node:type() ~= call_node do
		node = node:parent()
	end
	if not node then
		callback({})
		return
	end

	local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
	params.position = { line = diag.end_lnum, character = diag.end_col }
	client:request("textDocument/signatureHelp", params, function(err, res)
		if err or not res or not res.signatures or #res.signatures == 0 then
			callback({})
			return
		end
		local sig = res.signatures[res.activeSignature and (res.activeSignature + 1) or 1]
		local idx = sig.activeParameter or res.activeParameter
		local param = idx and sig.parameters and sig.parameters[idx + 1]
		if not param then
			callback({})
			return
		end
		local label = type(param.label) == "string" and param.label or nil
		local want = label and parse_param(label) or nil
		callback(want and { want } or {})
	end)
end

-- each shape is more specific than the next, and checked in that order: member access and
-- assignment-from-a-call are structurally distinct positions a bad token can sit in, and only
-- when neither matches does "it's some call's bare argument" become the right question.
local function expected_types(bufnr, diag, client, call_node, parse_param, parse_returns, callback)
	local field_name = member_access_field(bufnr, diag)
	if field_name and client:supports_method("workspace/symbol") then
		expected_member_types(client, field_name, callback)
		return
	end
	if parse_returns then
		local func_node, index = assignment_position(bufnr, diag)
		if func_node then
			expected_assignment_types(client, func_node, bufnr, index, parse_returns, callback)
			return
		end
	end
	if call_node and parse_param and client:supports_method("textDocument/signatureHelp") then
		expected_arg_type(bufnr, diag, client, call_node, parse_param, callback)
		return
	end
	callback({})
end

local function find_fixes(bufnr, callback)
	local diags = diagnostics_at_cursor(bufnr)
	if #diags == 0 then
		callback({})
		return
	end
	local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/hover" })
	local client = clients[1]
	local filetype = vim.bo[bufnr].filetype
	local call_node = adapters.call_node[filetype]
	local parse_hover = adapters.parse_hover[filetype]
	local parse_param = adapters.parse_param[filetype]
	local parse_returns = adapters.parse_returns[filetype]
	local scope_node_types = adapters.scope_node[filetype] or {}

	local fixes = {}
	local pending = #diags
	local function done()
		pending = pending - 1
		if pending == 0 then callback(fixes) end
	end

	for _, diag in ipairs(diags) do
		local bad = vim.api.nvim_buf_get_text(bufnr, diag.lnum, diag.col, diag.end_lnum, diag.end_col, {})[1]
		if not bad or bad == "" then
			done()
		else
			local scope = file_scope(bufnr)
			local all_candidates = {}
			if scope then collect_names(scope, bufnr, bad, scope_node_types, all_candidates) end

			-- keep only names visible at the bad token's position: walk its scope chain from
			-- innermost outward (a closure sees its own locals, then its enclosing function's,
			-- then the package) — first declaration found wins, same as real shadowing.
			local use_chain = scope_chain(node_at(bufnr, diag), scope_node_types)
			local candidates = {}
			for text, by_scope in pairs(all_candidates) do
				for _, s in ipairs(use_chain) do
					if by_scope[s] then
						candidates[text] = by_scope[s]
						break
					end
				end
			end

			-- name similarity — always available, no LSP round trip needed
			for text in pairs(candidates) do
				local dist = edit_distance(bad, text)
				if dist > 0 and dist / math.max(#bad, #text) <= MAX_DISTANCE_RATIO then
					fixes[#fixes + 1] = { label = text, dist = dist, diag = diag, reason = "spelling" }
				elseif chunk_prefix_match(bad, text) then
					fixes[#fixes + 1] = { label = text, dist = 0, diag = diag, reason = "spelling" }
				end
			end

			-- three more signals, each needing a client; run together, diag is done when all are
			local sub_pending = 3
			local function sub_done()
				sub_pending = sub_pending - 1
				if sub_pending == 0 then done() end
			end

			-- type — member access, assignment-from-call, or bare argument, whichever matches;
			-- needs parse_hover for the final comparison regardless of which.
			if client and parse_hover then
				expected_types(bufnr, diag, client, call_node, parse_param, parse_returns, function(want_types)
					if #want_types == 0 then
						sub_done()
						return
					end
					local want_bare = {}
					for _, t in ipairs(want_types) do
						want_bare[#want_bare + 1] = bare_type_name(t)
					end
					local names, hover_pending = {}, 0
					for text, pos in pairs(candidates) do
						names[#names + 1] = { text = text, pos = pos }
					end
					if #names == 0 then
						sub_done()
						return
					end
					hover_pending = #names
					for _, n in ipairs(names) do
						hover_type(bufnr, client, parse_hover, n.pos.row, n.pos.col, function(got_type)
							-- type outranks spelling in sorting below; among several type matches,
							-- spelling breaks the tie — a zero-overlap match still wins when it's the only one.
							if got_type and vim.tbl_contains(want_bare, bare_type_name(got_type)) then
								local dist = edit_distance(bad, n.text) / math.max(#bad, #n.text)
								fixes[#fixes + 1] = { label = n.text, dist = dist, diag = diag, reason = "type" }
							end
							hover_pending = hover_pending - 1
							if hover_pending == 0 then sub_done() end
						end)
					end
				end)
			else
				sub_done()
			end

			-- workspace — a cross-file/cross-package rename. Whole-string edit distance is the
			-- wrong metric (chunking exists to work around that); score by chunk overlap instead.
			-- A single-chunk bad token (e.g. "req") can only ever score 0% or 100% against any
			-- candidate — gopls's workspace/symbol pulls in the whole dependency graph, so some
			-- unrelated "AddReqParam" elsewhere trivially contains "req" as one of its own
			-- chunks and "matches" perfectly. Needs 2+ chunks to have a real gradient at all.
			local bad_chunks = chunk_identifier(bad)
			if client and client:supports_method("workspace/symbol") and #bad_chunks > 1 then
				workspace_candidates(client, bad, function(names)
					for _, text in ipairs(names) do
						if text ~= bad then
							local text_chunks = chunk_identifier(text)
							local matched = 0
							for _, bc in ipairs(bad_chunks) do
								for _, tc in ipairs(text_chunks) do
									if bc:lower() == tc:lower() then
										matched = matched + 1
										break
									end
								end
							end
							local overlap = matched / #bad_chunks
							if overlap >= 0.7 then
								fixes[#fixes + 1] = { label = text, dist = 1 - overlap, diag = diag, reason = "workspace" }
							end
						end
					end
					sub_done()
				end)
			else
				sub_done()
			end

			-- member — the bad token is itself the field, not the operand (member_access_field
			-- catches the reverse: an undefined x in x.Field). The operand's type is already
			-- resolved by gopls; score its real members the same way spelling scores local names.
			if member_access_operand(bufnr, diag) and client and client:supports_method("textDocument/completion") then
				member_candidates(client, diag, function(names)
					for _, text in ipairs(names) do
						if text ~= bad then
							local dist = edit_distance(bad, text)
							if dist > 0 and dist / math.max(#bad, #text) <= MAX_DISTANCE_RATIO then
								fixes[#fixes + 1] = { label = text, dist = dist, diag = diag, reason = "member" }
							elseif chunk_prefix_match(bad, text) then
								fixes[#fixes + 1] = { label = text, dist = 0, diag = diag, reason = "member" }
							end
						end
					end
					sub_done()
				end)
			else
				sub_done()
			end
		end
	end
end

-- the engine's one entry point: a list of {label, apply(done)}, ranked, deduped.
function M.find(bufnr, callback)
	find_fixes(bufnr, function(fixes)
		-- a type match is as strong a signal as it gets here; otherwise rank by closeness
		table.sort(fixes, function(a, b)
			if (a.reason == "type") ~= (b.reason == "type") then return a.reason == "type" end
			return a.dist < b.dist
		end)
		local items, seen = {}, {}
		for _, fix in ipairs(fixes) do
			if not seen[fix.label] then
				seen[fix.label] = true
				local suffix = ({ type = " (same type)", workspace = " (elsewhere in package)" })[fix.reason]
					or " (fix typo)"
				items[#items + 1] = {
					label = fix.label .. suffix,
					apply = function(done)
						-- replace the diagnostic's own span, not insert at cursor — the whole bad token needs to change.
						vim.api.nvim_buf_set_text(bufnr, fix.diag.lnum, fix.diag.col, fix.diag.end_lnum, fix.diag.end_col, { fix.label })
						-- Neovim keeps the cursor at the same offset into the replaced span — on the first
						-- character, that's often right after a ".", gopls's own completion trigger. Pin the
						-- cursor past the new text instead of trusting where the edit leaves it.
						vim.api.nvim_win_set_cursor(0, { fix.diag.end_lnum + 1, fix.diag.col + #fix.label })
						done()
					end,
				}
			end
		end
		callback(items)
	end)
end

return M
