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
			exclude_ft = {'neo-tree'},
			exclude_name = {'neo-tree'},
			custom_exclude = function(bufnr)
				local name = vim.api.nvim_buf_get_name(bufnr)
				return name:match("neo-tree") ~= nil or name:match("neo%-tree") ~= nil
			end,
		})
	end
}
