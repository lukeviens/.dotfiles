local M = {}

M.theme = function()
	local colors = {
		gray = "#727169",
		innerbg = nil,
		outerbg = nil,
	}
	local mode = {
		a = { fg = colors.gray, bg = colors.outerbg, gui = "bold" },
		b = { fg = colors.gray, bg = colors.outerbg },
		c = { fg = colors.gray, bg = colors.innerbg },
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
