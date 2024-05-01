return {
	"neovim/nvim-lspconfig",
	dependencies = {
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		"hrsh7th/cmp-nvim-lsp",
		"hrsh7th/cmp-buffer",
		"hrsh7th/cmp-path",
		"hrsh7th/cmp-cmdline",
		"hrsh7th/nvim-cmp",
		"L3MON4D3/LuaSnip",
		"saadparwaiz1/cmp_luasnip",
		"j-hui/fidget.nvim",
	},

	config = function()
		local cmp = require('cmp')
		local cmp_lsp = require("cmp_nvim_lsp")
		local on_attach = function(client, bufnr)
			-- Using Telescope for jumping to declaration, definition, and references
			vim.keymap.set("n", "gD", require('telescope.builtin').lsp_type_definitions, { buffer = bufnr, desc = "Go to Type Definition" })
			vim.keymap.set("n", "gd", require('telescope.builtin').lsp_definitions, { buffer = bufnr, desc = "Go to Definition" })
			vim.keymap.set("n", "gi", require('telescope.builtin').lsp_implementations, { buffer = bufnr, desc = "Go to Implementation" })
			vim.keymap.set("n", "gr", require('telescope.builtin').lsp_references, { buffer = bufnr, desc = "Symbol References" })

			-- Retaining other LSP functionalities with original bindings
			vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr, desc = "LSP Hover" })
			vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, { buffer = bufnr, desc = "Signature Help" })
			vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { buffer = bufnr, desc = "Go to Next Diagnostic" })
			vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { buffer = bufnr, desc = "Go to Previous Diagnostic" })
			vim.keymap.set("n", "gl", vim.diagnostic.open_float, { buffer = bufnr, desc = "Open Diagnostic Float" })
		end
		local capabilities = vim.tbl_deep_extend(
			"force",
			{},
			vim.lsp.protocol.make_client_capabilities(),
			cmp_lsp.default_capabilities())

		require("fidget").setup({})
		require("mason").setup()
		require("mason-lspconfig").setup({
			ensure_installed = {
				"pylsp",
				"rust_analyzer",
				"terraformls",
				"lua_ls",
				"clangd",
			},
			handlers = {
				function(server_name) -- default handler (optional)

					require("lspconfig")[server_name].setup {
						capabilities = capabilities,
						on_attach = on_attach
					}
				end,

				["pylsp"] = function()
					local lspconfig = require("lspconfig")
					lspconfig.pylsp.setup {
						capabilities = capabilities,
						on_attach = on_attach,
						settings = {
							pylsp = {
								plugins = {
									pycodestyle = {
										ignore = {'E203', 'E302', 'E501', 'E303'}
									}
								}
							}
						}
					}
				end,

				["lua_ls"] = function()
					local lspconfig = require("lspconfig")
					lspconfig.lua_ls.setup {
						capabilities = capabilities,
						on_atach = on_attach,
						settings = {
							Lua = {
								diagnostics = {
									globals = { "vim", "it", "describe", "before_each", "after_each" },
								}
							}
						}
					}
				end,
			}
		})

		local cmp_select = { behavior = cmp.SelectBehavior.Select }

		cmp.setup({
			snippet = {
				expand = function(args)
					require('luasnip').lsp_expand(args.body) -- For `luasnip` users.
				end,
			},
			mapping = cmp.mapping.preset.insert({
				['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
				['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
				['<C-y>'] = cmp.mapping.confirm({ select = true }),
				["<C-Space>"] = cmp.mapping.complete(),
			}),
			sources = cmp.config.sources({
				{ name = 'nvim_lsp' },
				{ name = 'luasnip' }, -- For luasnip users.
				}, {
					{ name = 'buffer' },
			})
		})

		vim.diagnostic.config({
			-- update_in_insert = true,
			float = {
				focusable = false,
				style = "minimal",
				border = "rounded",
				source = "always",
				header = "",
				prefix = "",
			},
		})
	end
}
