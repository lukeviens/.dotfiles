-- The ? view: every keybind ask/ defines, read straight from the registry that actually
-- applies them (ask/panel/keymap.lua) -- never a separately hand-written list that could say
-- something that isn't true.
local M = {}
local keymap = require("ask.panel.keymap")
local mode = require("ask.panel.mode")

function M.show(state)
	mode.show_page(state, "help", keymap.help_lines())
end

return M
