return {
	"neovim/nvim-lspconfig",
	dependencies = { "williamboman/mason.nvim", "williamboman/mason-lspconfig.nvim" },
	config = function()
		require("mason").setup()

		-- one attach point for every server (mason-managed or hand-started, e.g. i's LSP in
		-- autoload.lua): keymaps, native completion, inlay hints, format-on-save.
		vim.api.nvim_create_autocmd("LspAttach", {
			callback = function(args)
				local bufnr = args.buf
				local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
				local opts = function(desc) return { buffer = bufnr, desc = desc } end

				local tb = require("telescope.builtin")
				vim.keymap.set("n", "gd", tb.lsp_definitions, opts("Go to Definition"))
				vim.keymap.set("n", "gD", tb.lsp_type_definitions, opts("Go to Type Definition"))
				vim.keymap.set("n", "gi", tb.lsp_implementations, opts("Go to Implementation"))
				vim.keymap.set("n", "gr", tb.lsp_references, opts("References"))
				vim.keymap.set("n", "<leader>ds", tb.lsp_document_symbols, opts("Document Symbols"))
				vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts("Diagnostic Float"))
				vim.keymap.set("n", "K", vim.lsp.buf.hover, opts("Hover"))
				vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts("Rename"))
				vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts("Code Action"))
				vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts("Previous Diagnostic"))
				vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts("Next Diagnostic"))

				if client:supports_method("textDocument/completion") then
					vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
				end
				if client:supports_method("textDocument/inlayHint") then
					vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
				end
				if client:supports_method("textDocument/formatting") then
					vim.api.nvim_create_autocmd("BufWritePre", {
						buffer = bufnr,
						callback = function()
							vim.lsp.buf.format({ bufnr = bufnr, id = client.id, timeout_ms = 3000 })
						end,
					})
				end
			end,
		})

		vim.diagnostic.config({
			virtual_text = { current_line = true },
			signs = true,
			underline = true,
			update_in_insert = false,
			float = { focusable = false, style = "minimal", border = "rounded", source = "always" },
		})

		-- per-server settings, native API — mason-lspconfig enables each installed server for us
		-- (automatic_enable defaults true: it calls vim.lsp.enable() per server it manages).
		vim.lsp.config("lua_ls", { settings = { Lua = { diagnostics = { globals = { "vim" } } } } })
		vim.lsp.config("pylsp", {
			settings = { pylsp = { plugins = { pycodestyle = { ignore = { "E203", "E302", "E501", "E303" } } } } },
		})
		vim.lsp.config("gopls", {
			settings = { gopls = { gofumpt = true, staticcheck = true, usePlaceholders = true } },
		})
		vim.lsp.config("vtsls", {
			settings = {
				typescript = { tsserver = { maxTsServerMemory = 8192 } },
				vtsls = { autoUseWorkspaceTsdk = true },
			},
		})

		require("mason-lspconfig").setup({
			ensure_installed = { "pylsp", "rust_analyzer", "terraformls", "lua_ls", "clangd", "gopls", "vtsls" },
		})
	end,
}
