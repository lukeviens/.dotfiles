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
		-- molokai has no light variant, so this is its light partner: the town theme
		-- (Caps t) swaps to tokyonight-day on light (see config/autoload.lua's watcher).
		"folke/tokyonight.nvim",
		lazy = false,
		priority = 1000,
		opts = { transparent = true, styles = { sidebars = "transparent", floats = "transparent" } },
	},
	{
		-- base16 applier for UNKNOWN themes (a random roll): config/autoload.lua generates a
		-- 16-colour palette from the town colours and feeds it here. mini.base16 maps it across
		-- every modern group (treesitter/LSP/semantic/plugins) correctly — named themes still
		-- use the handcrafted schemes above.
		"echasnovski/mini.base16",
		lazy = false,
		priority = 1000,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "molokai",
		},
	},
}
