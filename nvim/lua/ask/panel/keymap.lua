-- Every keybind ask/ defines, grouped by which buffer it applies to. One table drives both
-- the actual vim.keymap.set calls (M.apply) and the ? help view (M.help_lines) -- the same
-- data, so they can never drift the way separately hand-written desc strings and a
-- hand-written hint string could (same idea as town/residents/translators/tmux.lua).
--
-- Each entry: { mode, key, desc, action } -- action names a callback the caller supplies to
-- M.apply at the point the real buffer exists (closures aren't available at module-load
-- time). A `literal` entry maps directly to a literal keystroke instead (vim.keymap.set's
-- default noremap semantics -- it re-feeds the real key, not one of our own mappings).
--
-- `m`/`?` are deliberately bound in both transcript and compose (Normal mode only -- typing
-- "m" while actually composing still just types "m"): both make sense regardless of which
-- buffer you're sitting in. `a` ("jump to the prompt") stays transcript-only on purpose --
-- meaningless from inside the prompt you'd be jumping to.
local M = {}

M.registry = {
	transcript = {
		{ mode = "n", key = "q", desc = "close", action = "close" },
		{ mode = "n", key = "<Esc>", desc = "close", action = "close" },
		{ mode = "n", key = "a", desc = "jump to the prompt", action = "focus_compose" },
		{ mode = "n", key = "m", desc = "view memory", action = "memory_view" },
		{ mode = "n", key = "n", desc = "new chat", action = "new_chat" },
		{ mode = "n", key = "?", desc = "this help", action = "help" },
	},
	compose = {
		{ mode = "n", key = "q", desc = "close", action = "close" },
		{ mode = "n", key = "<Esc>", desc = "close", action = "close" },
		{ mode = "n", key = "?", desc = "this help", action = "help" },
		{ mode = "n", key = "m", desc = "view memory", action = "memory_view" },
		{ mode = "i", key = "<CR>", desc = "send", action = "send" },
		{ mode = "i", key = "<S-CR>", desc = "newline", literal = "<CR>" },
		-- same keys as diff's own target_buf -- accepting/rejecting shouldn't require switching
		-- windows first. No-ops without a pending review (ask.panel.diff.accept/reject).
		{ mode = "n", key = "<leader>ay", desc = "accept the pending change", action = "accept" },
		{ mode = "n", key = "<leader>an", desc = "reject the pending change", action = "reject" },
	},
	diff = {
		{ mode = "n", key = "<leader>ay", desc = "accept", action = "accept" },
		{ mode = "n", key = "<leader>an", desc = "reject", action = "reject" },
		{ mode = "n", key = "<leader>ac", desc = "comment on this line", action = "comment" },
		-- Normal mode only -- the Visual-mode case (discuss a selection) is bound directly in
		-- diff.lua's show_change instead: a bare Lua-function mapping doesn't leave Visual mode
		-- cleanly enough for '<'/'>' to land, same reason ask/init.lua's own <leader>aa uses a
		-- literal <Esc> first.
		{ mode = "n", key = "<leader>ad", desc = "discuss", action = "discuss" },
		-- safe now, unlike the other contexts' guard_diff wrapping: mode.exit returns to this
		-- same review afterward instead of dropping to chat, since state.diff is still set.
		{ mode = "n", key = "?", desc = "help", action = "help" },
		{ mode = "n", key = "m", desc = "memory", action = "memory_view" },
	},
	discuss = {
		{ mode = "n", key = "q", desc = "back to the review", action = "close" },
		{ mode = "n", key = "<Esc>", desc = "back to the review", action = "close" },
		{ mode = "n", key = "?", desc = "help", action = "help" },
		{ mode = "n", key = "m", desc = "memory", action = "memory_view" },
	},
	memory_view = {
		{ mode = "n", key = "q", desc = "back to chat", action = "close" },
		{ mode = "n", key = "<Esc>", desc = "back to chat", action = "close" },
	},
	help = {
		{ mode = "n", key = "q", desc = "back to chat", action = "close" },
		{ mode = "n", key = "<Esc>", desc = "back to chat", action = "close" },
	},
}

-- actions: { action_name -> fn }. Entries naming an action this buffer's caller didn't
-- supply are silently skipped -- lets a context's registry list bindings that only some
-- callers wire up, without every caller needing every action.
function M.apply(context, bufnr, actions)
	for _, b in ipairs(M.registry[context] or {}) do
		local rhs = b.literal or actions[b.action]
		if rhs then
			vim.keymap.set(b.mode, b.key, rhs, { buffer = bufnr, nowait = true, desc = "ask: " .. b.desc })
		end
	end
end

local TITLES = {
	transcript = "Transcript", compose = "Compose box", diff = "Diff review",
	discuss = "Discussing the change", memory_view = "Memory view", help = "Help",
}
local ORDER = { "transcript", "compose", "diff", "discuss", "memory_view", "help" }

-- TITLES/ORDER duplicate M.registry's keys by hand. Assert both cover every context, so a
-- missing entry stops nvim instead of quietly dropping a section from the ? screen.
for ctx in pairs(M.registry) do
	assert(TITLES[ctx], "keymap.lua: context '" .. ctx .. "' has no TITLES entry")
	assert(vim.tbl_contains(ORDER, ctx), "keymap.lua: context '" .. ctx .. "' missing from ORDER")
end

-- a short "`key` desc · `key` desc" line for a context's own winbar -- diff uses this so its
-- keys stay visible without having to actually open the full help screen. Skips literal
-- entries (not an action worth naming).
function M.winbar_hint(context)
	local parts = {}
	for _, b in ipairs(M.registry[context] or {}) do
		if not b.literal then parts[#parts + 1] = b.key .. " " .. b.desc end
	end
	return table.concat(parts, " · ")
end

-- a flat, deterministic listing -- every bound key, every context, one source, so it can
-- never claim a binding that isn't actually there.
function M.help_lines()
	local lines = { "# ask/ keybinds", "" }
	for _, ctx in ipairs(ORDER) do
		lines[#lines + 1] = "## " .. TITLES[ctx]
		for _, b in ipairs(M.registry[ctx]) do
			lines[#lines + 1] = string.format("- `%s` -- %s", b.key, b.desc)
		end
		lines[#lines + 1] = ""
	end
	return lines
end

return M
