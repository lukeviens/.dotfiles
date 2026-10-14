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
		vim.keymap.set({ 'n', 'i' }, '<M-o>', '<Cmd>BufferPrevious<CR>', { desc = 'Previous buffer' })
		vim.keymap.set({ 'n', 'i' }, '<M-i>', '<Cmd>BufferNext<CR>', { desc = 'Next buffer' })
	end
}
