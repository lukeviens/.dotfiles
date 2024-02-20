return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
			"3rd/image.nvim",
			"nvimdev/nerdicons.nvim",
			"s1n7ax/nvim-window-picker"
		},
		config = function()
			require 'window-picker'.setup({
				filter_rules = {
					include_current_win = false,
					autoselect_one = true,
					-- filter using buffer options
					bo = {
						-- if the file type is one of following, the window will be ignored
						filetype = { 'neo-tree', "neo-tree-popup", "notify" },
						-- if the buffer type is one of following, the window will be ignored
						buftype = { 'terminal', "quickfix" },
					},
				},
			})
		end,
		opts = {
			buffers = {
				follow_current_file = {
					enabled = true, -- This will find and focus the file in the active buffer every time
					leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
				}
			}
		}
	}
}
