local theme = require('config.theme').colors

local M = {}

M.theme = function()
	local mode = {
		a = { fg = theme.subtle, bg = nil, gui = "bold" },
		b = { fg = theme.subtle, bg = nil },
		c = { fg = theme.subtle, bg = nil },
	}
	return {
		inactive = mode,
		visual = mode,
		replace = mode,
		normal = mode,
		insert = mode,
		command = mode,
	}
end

return M
