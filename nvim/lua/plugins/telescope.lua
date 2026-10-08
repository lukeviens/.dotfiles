-- fzf-native: the sorter in C. The Lua one scores every candidate per keystroke.
return {
	'nvim-telescope/telescope.nvim', branch = 'master',
	dependencies = {
		'nvim-lua/plenary.nvim',
		{ 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
	},
	opts = {},
	config = function(_, opts)
		local telescope = require('telescope')
		telescope.setup(opts)
		pcall(telescope.load_extension, 'fzf')   -- unbuilt → the Lua sorter
	end,
}
