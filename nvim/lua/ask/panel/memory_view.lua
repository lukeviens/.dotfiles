-- Read-only view of what ask/memory has accumulated for this session -- the facts and
-- code_refs that get folded into the next prompt (ask/memory.lua's M.inject), made visible
-- instead of staying an invisible preamble. No editing yet, on purpose: we have no evidence
-- the distillation needs correcting often enough to earn that complexity -- see it first.
local M = {}
local mode = require("ask.panel.mode")

-- an item can span lines (a quoted code block); continuation lines indent under the bullet so
-- markdown keeps them inside the same list item.
local function add_item(lines, item)
	for i, l in ipairs(vim.split(item, "\n", { plain = true })) do
		lines[#lines + 1] = (i == 1 and "- " or "  ") .. l
	end
end

local function render(records)
	if #records == 0 then
		return { "# Memory for this conversation", "", "Nothing distilled yet." }
	end
	local lines = { "# Memory for this conversation", "" }
	for i, r in ipairs(records) do
		vim.list_extend(lines, { string.format("## Turn %d (%s)", i, os.date("%H:%M:%S", r.at)), "" })
		for _, f in ipairs(r.facts or {}) do add_item(lines, f) end
		for _, c in ipairs(r.code_refs or {}) do add_item(lines, c) end
		lines[#lines + 1] = ""
	end
	return lines
end

function M.show(state, records)
	mode.show_page(state, "memory_view", render(records))
end

return M
