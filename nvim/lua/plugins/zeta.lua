-- Zeta predicts the next edit from the buffer and recent edits. The plugin owns
-- the preview and acceptance in Neovim; the model is served locally by llama.cpp.
return {
	"cursortab/cursortab.nvim",
	lazy = false,
	build = "cd server && go build",
	config = function()
		local zeta = vim.fn.fnamemodify(vim.fn.stdpath("config"), ":h") .. "/town/bin/zeta"
		vim.fn.jobstart({ zeta }, { detach = true })
		require("cursortab").setup({
			contribute_data = false,
			provider = {
				type = "zeta-2.1",
				url = "http://127.0.0.1:8012",
				model = "zeta-2.1",
				temperature = 0.5,
				context_size = 2048,
				max_tokens = 256,
				completion_timeout = 10000,
				privacy_mode = true,
			},
			behavior = {
				enabled_modes = { "insert", "normal" },
				text_change_debounce = 150,
				idle_completion_delay = 200,
			},
		})

		-- Cursortab establishes its disk baseline on the first request. Give it
		-- the clean buffer before typing, so the first edit is not discarded.
		local function prime_clean_buffer()
			local bufnr = vim.api.nvim_get_current_buf()
			if vim.bo[bufnr].modified or require("cursortab.buffer").should_skip() then
				return
			end
			require("cursortab.daemon").send_event("file_saved")
		end

		vim.api.nvim_create_autocmd("BufEnter", {
			callback = function()
				vim.defer_fn(prime_clean_buffer, 500)
			end,
		})
		vim.api.nvim_create_autocmd("InsertEnter", { callback = prime_clean_buffer })
		vim.defer_fn(prime_clean_buffer, 500)
	end,
}
