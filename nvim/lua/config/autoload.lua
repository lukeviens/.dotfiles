--
-- GENERAL
--

vim.cmd([[
	set number relativenumber
	set tabstop=4
	set shiftwidth=4
	autocmd Filetype lua setlocal tabstop=2
	autocmd Filetype lua setlocal shiftwidth=2
]])

-- mouse mode on lol
vim.o.mouse = "a"


---
--- TELESCOPE
---

local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})


--
-- NEOTREE
--

local initial_buffer = false

vim.api.nvim_create_autocmd("VimEnter", {
	pattern = "*",
	callback = function()
		if vim.fn.argc() == 0 then
			vim.cmd('Neotree current')
			initial_buffer = true
		end
	end,
})


--
-- STARTUP COMMANDS
--

vim.api.nvim_create_autocmd("VimEnter", {
	pattern = "*",
	callback = function()
		if vim.fn.argc() == 0 then
			vim.api.nvim_create_autocmd("BufEnter", {
				pattern = "*",
				once = true,
				callback = function()
					if initial_buffer == true then
						vim.cmd('bdelete 1')
						initial_buffer = false
					end
				end,
			})
		end
	end,
})

vim.api.nvim_set_keymap('n', '<leader>t', ':Neotree current reveal filesystem<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>tt', ':Neotree current reveal buffers<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>ttt', ':Neotree current reveal git_status<CR>', { noremap = true, silent = true })


--
-- LSP
--

-- remove inline errors
vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
	vim.lsp.diagnostic.on_publish_diagnostics,
	{
		virtual_text = false,
		signs = true,
		update_in_insert = false,
		underline = true,
	}
)


---
--- EDITOR LOOK
---

-- colorscheme
local onedark = require('onedark')
onedark.setup { style = 'warmer' }
onedark.load()

vim.cmd(":hi BufferTabpageFill guibg=none")
vim.cmd(":hi TabLine guibg=none")
vim.cmd(":hi BufferCurrent guibg=none guifg=#fbf1f1")
vim.cmd(":hi BufferVisible guibg=none")
vim.cmd(":hi BufferInactive guibg=none")
vim.cmd(":hi BufferInactiveSign guibg=none")
vim.cmd(":hi Normal guibg=NONE ctermbg=NONE")
vim.cmd(":hi StatusLine guibg=NONE ctermbg=NONE")
vim.cmd(":hi StatusLineNC guibg=NONE ctermbg=NONE")
vim.cmd(":hi LspProgressNormal guibg=NONE ctermbg=NONE")
--statusline
vim.g.gitblame_display_virtual_text = 0 -- Disable virtual text
local git_blame = require('gitblame')

require('lualine').setup({
	options = {
		theme = require('config.lualine').theme(),
		section_separators = '',
		component_separators = '',
		globalstatus = true,
	},
	sections = {
		lualine_a = {'branch'},
		lualine_b = {{'filename', path = 1}},
		lualine_c = {},
		lualine_x = {
			{ git_blame.get_current_blame_text, cond = git_blame.is_blame_text_available }
		},
		lualine_y = {'filetype'},
		lualine_z = {'progress', 'location'}
	},
})
