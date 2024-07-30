return {
	"romgrk/barbar.nvim",
	config = function()
		require('barbar').setup({
			icons = {
				preset = "default",
				separator_at_end = false,
			},
			maximum_padding = 2,
			minimum_padding = 2
		})
	end
}
