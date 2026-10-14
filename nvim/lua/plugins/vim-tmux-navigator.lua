return {
	"christoomey/vim-tmux-navigator",
	-- ⌥hjkl, not ⌃, so pane motion never collides with shell/readline. Disable the plugin's
	-- default ⌃hjkl maps so ctrl is fully freed.
	init = function()
		vim.g.tmux_navigator_no_mappings = 1
		-- hitting the edge of vim's own split tree while the tmux pane is zoomed would otherwise
		-- fall through to tmux's own pane-select, which un-zooms you into a different pane —
		-- never leave the zoomed view just because vim ran out of its own splits to move into.
		vim.g.tmux_navigator_disable_when_zoomed = 1
	end,
	keys = {
		{ "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Go to the previous pane" },
		{ "<M-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to the left pane" },
		{ "<M-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to the down pane" },
		{ "<M-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to the up pane" },
		{ "<M-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to the right pane" },
	},
}


