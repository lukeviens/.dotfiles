return {
	"romgrk/barbar.nvim",
	config = function()
		require('barbar').setup({
			icons = {
				preset = "default",
				separator_at_end = false,
        filetype = {
          enabled = false,
        },
			},
			maximum_padding = 2,
			minimum_padding = 2,
		})
		-- Caps o/i arrives as M-o/M-i and means recency, so it is the jumplist. BufferPrevious/Next
		-- walk by position, and barbar excludes neo-tree from that order just above.
		vim.keymap.set('n', '<M-o>', '<C-o>', { desc = 'Jump back' })
		vim.keymap.set('n', '<M-i>', '<C-i>', { desc = 'Jump forward' })
		vim.keymap.set('i', '<M-o>', '<Esc><C-o>', { desc = 'Jump back' })
		vim.keymap.set('i', '<M-i>', '<Esc><C-i>', { desc = 'Jump forward' })
	end
}
