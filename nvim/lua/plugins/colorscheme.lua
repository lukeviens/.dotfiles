return {
	{
		"UtkarshVerma/molokai.nvim",
		lazy = false,
		priority = 1000,
		opts = {
			transparent = true,
			styles = {
				sidebars = "transparent",
				floats = "transparent",
			},
		}
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "molokai",
		},
	},
}
