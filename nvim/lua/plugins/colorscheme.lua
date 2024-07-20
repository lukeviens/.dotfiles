--[[
return {
  -- add gruvbox
  { "ellisonleao/gruvbox.nvim" },

  -- Configure LazyVim to load gruvbox
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "gruvbox",
    },
  }
}
--]]

--[[
return {
	{
		"navarasu/onedark.nvim",
		lazy = false,
		priority = 1000,
		opts = {
		}
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "onedark",
		},
	},
}
--]]

return {
	{
		"UtkarshVerma/molokai.nvim",
		lazy = false,
		priority = 1000,
		opts = {
		}
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "molokai",
		},
	},
}
