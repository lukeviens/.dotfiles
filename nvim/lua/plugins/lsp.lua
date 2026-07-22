return {
	"neovim/nvim-lspconfig",
	dependencies = {
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		"hrsh7th/cmp-nvim-lsp",
		"hrsh7th/cmp-buffer",
		"hrsh7th/nvim-cmp",
		"L3MON4D3/LuaSnip",
		"saadparwaiz1/cmp_luasnip",
	},

	config = function()
		local cmp = require('cmp')
		local cmp_lsp = require("cmp_nvim_lsp")
		local on_attach = function(client, bufnr)
			local opts = function(desc) return { buffer = bufnr, desc = desc } end

			vim.keymap.set("n", "gD", require('telescope.builtin').lsp_type_definitions, opts("Go to Type Definition"))
			vim.keymap.set("n", "gd", require('telescope.builtin').lsp_definitions, opts("Go to Definition"))
			vim.keymap.set("n", "gi", require('telescope.builtin').lsp_implementations, opts("Go to Implementation"))
			vim.keymap.set("n", "gr", require('telescope.builtin').lsp_references, opts("Symbol References"))
			vim.keymap.set("n", "K", vim.lsp.buf.hover, opts("LSP Hover"))
			vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts("Previous Diagnostic"))
			vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts("Next Diagnostic"))
			vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts("Open Diagnostic Float"))
		end
		local capabilities = vim.tbl_deep_extend(
			"force",
			{},
			vim.lsp.protocol.make_client_capabilities(),
			cmp_lsp.default_capabilities())

		require("mason").setup()
		require("mason-lspconfig").setup({
			ensure_installed = {
				"pylsp",
				"rust_analyzer",
				"terraformls",
				"lua_ls",
				"clangd",
				"gopls",
				"vtsls",
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
						on_attach = on_attach,
						settings = {
							Lua = {
								diagnostics = {
									globals = { "vim", "it", "describe", "before_each", "after_each" },
								}
							}
						}
					}
				end,

				["vtsls"] = function()
					local lspconfig = require("lspconfig")
					lspconfig.vtsls.setup {
						capabilities = capabilities,
						on_attach = on_attach,
						settings = {
							typescript = {
								tsserver = {
									maxTsServerMemory = 8192,
								},
							},
							vtsls = {
								autoUseWorkspaceTsdk = true,
							},
						},
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
			virtual_text = false,
			signs = true,
			update_in_insert = false,
			underline = true,
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
