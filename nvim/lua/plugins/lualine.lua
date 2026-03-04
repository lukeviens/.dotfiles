return {
	'nvim-lualine/lualine.nvim',
	dependencies = {
		'nvim-tree/nvim-web-devicons',
		'f-person/git-blame.nvim',
	},
	event = "VeryLazy",
	config = function()
		local git_blame = require('gitblame')

		require('lualine').setup({
			options = {
				theme = require('config.lualine').theme(),
				section_separators = '',
				component_separators = '',
				globalstatus = true,
			},
			sections = {
				lualine_a = {'branch'},
				lualine_b = {{'filename', path = 1}},
				lualine_c = {},
				lualine_x = {
					{ git_blame.get_current_blame_text, cond = git_blame.is_blame_text_available }
				},
				lualine_y = {'filetype'},
				lualine_z = {'progress', 'location'}
			},
		})
	end,
}
