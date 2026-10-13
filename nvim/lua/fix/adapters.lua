-- per-language knowledge the signals need beyond plain LSP requests: which tree-sitter node is
-- a call's argument list, how to read a type back out of hover/signatureHelp text, and how a
-- server phrases "declare this as new".
--
-- call_node is verified against each language's real grammar — not guessed. The rest (hover/param
-- parsing, declare_pattern) is a specific server's own wording, no LSP-spec guarantee elsewhere
-- matches it; only gopls is verified live, so only Go has them filled in. A language missing from
-- a field just sits that signal out — spelling and workspace search need none of this.
local M = {}

M.call_node = {
	go = "argument_list",
	c = "argument_list",
	cpp = "argument_list",
	python = "argument_list",
	javascript = "arguments",
	typescript = "arguments",
	rust = "arguments",
}

-- node types that introduce a new scope: a name declared inside one (a parameter, a local var)
-- is only a candidate for a bad token inside that SAME node, never a sibling one. A language
-- missing here just means every candidate is treated as always-in-scope, same as before this
-- existed — only Go is verified live.
M.scope_node = {
	go = { function_declaration = true, method_declaration = true, func_literal = true },
}

-- hover's declaration line is "var name Type" (optionally "const"/"field"/"func" in place of
-- "var"), inside a ```go fence. strip the fence, the leading keyword if any, then the name.
local function go_parse_hover(value)
	local decl_line = type(value) == "string" and value:match("```%a*\n([^\n]+)") or nil
	if not decl_line then return nil end
	local words = {}
	for w in decl_line:gmatch("%S+") do
		words[#words + 1] = w
	end
	if #words >= 2 and (words[1] == "var" or words[1] == "const" or words[1] == "field" or words[1] == "func") then
		table.remove(words, 1)
	end
	table.remove(words, 1) -- the name itself
	return table.concat(words, " ")
end

-- signatureHelp's parameter label is plain "name Type", no leading keyword.
local function go_parse_param(label)
	return (label:match("^%S+%s+(.+)$"))
end

-- a function's hover declaration is "func Name(params) ReturnClause" — nothing, a bare type, or
-- "(T1, T2, ...)". Walk the parameter list's parens by depth to find where it ends, rather than
-- regexing — a type can contain its own commas and parens.
local function balanced_split(inner)
	local parts, depth, cur = {}, 0, ""
	for i = 1, #inner do
		local ch = inner:sub(i, i)
		if ch == "(" then depth = depth + 1 end
		if ch == ")" then depth = depth - 1 end
		if ch == "," and depth == 0 then
			parts[#parts + 1] = cur:match("^%s*(.-)%s*$")
			cur = ""
		else
			cur = cur .. ch
		end
	end
	if cur:match("%S") then parts[#parts + 1] = cur:match("^%s*(.-)%s*$") end
	return parts
end

local function go_parse_returns(value)
	local decl_line = type(value) == "string" and value:match("```%a*\n([^\n]+)") or nil
	if not decl_line then return {} end
	local open = decl_line:find("(", 1, true)
	if not open then return {} end
	local depth, i = 0, open
	while i <= #decl_line do
		local ch = decl_line:sub(i, i)
		if ch == "(" then depth = depth + 1 end
		if ch == ")" then
			depth = depth - 1
			if depth == 0 then break end
		end
		i = i + 1
	end
	local rest = decl_line:sub(i + 1):match("^%s*(.-)%s*$")
	if rest == "" then return {} end
	if rest:sub(1, 1) == "(" and rest:sub(-1) == ")" then return balanced_split(rest:sub(2, -2)) end
	return { rest }
end

M.parse_hover = { go = go_parse_hover }
M.parse_param = { go = go_parse_param }
M.parse_returns = { go = go_parse_returns }
M.declare_pattern = { go = "^Create " }

return M
