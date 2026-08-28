return {
	"christoomey/vim-tmux-navigator",
	-- ⌥hjkl, not ⌃, so pane motion never collides with shell/readline. Disable the plugin's
	-- default ⌃hjkl maps so ctrl is fully freed.
	init = function() vim.g.tmux_navigator_no_mappings = 1 end,
	keys = {
		{ "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Go to the previous pane" },
		{ "<M-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to the left pane" },
		{ "<M-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to the down pane" },
		{ "<M-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to the up pane" },
		{ "<M-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to the right pane" },
	},
}


