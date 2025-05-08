--
-- GENERAL
--

-- tabs/spaces 
vim.cmd([[
	set number relativenumber
	set tabstop=4
	set shiftwidth=4
	set expandtab
	autocmd Filetype lua setlocal tabstop=2
	autocmd Filetype lua setlocal shiftwidth=2
	autocmd Filetype typescript setlocal shiftwidth=2
	autocmd Filetype typescript setlocal shiftwidth=2
]])

-- clipboard -> system
vim.cmd([[
	set clipboard^=unnamed,unnamedplus
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
--[[
local onedark = require('onedark')
onedark.setup { style = 'dark' }
onedark.load()
]]--

-- TODO: move this somewhere less dumb
-- general ui 
vim.cmd(":hi Normal guibg=NONE ctermbg=NONE")
vim.cmd(":hi StatusLine guibg=NONE ctermbg=NONE")
vim.cmd(":hi StatusLineNC guibg=NONE ctermbg=NONE")
vim.cmd(":hi TabLine guibg=NONE")
vim.cmd(":hi LspProgressNormal guibg=NONE ctermbg=NONE")

-- barbar specific
vim.cmd(":hi BufferCurrent guibg=NONE guifg=#fbf1f1")
vim.cmd(":hi BufferCurrentIndex guibg=NONE")
vim.cmd(":hi BufferCurrentMod guibg=NONE")
vim.cmd(":hi BufferCurrentSign guibg=NONE")
vim.cmd(":hi BufferCurrentTarget guibg=NONE")

vim.cmd(":hi BufferInactive guibg=NONE")
vim.cmd(":hi BufferInactiveIndex guibg=NONE")
vim.cmd(":hi BufferInactiveSign guibg=NONE")

vim.cmd(":hi BufferOffset guibg=NONE")
vim.cmd(":hi BufferTabpageFill guibg=NONE")
vim.cmd(":hi BufferTabpages guibg=NONE")

vim.cmd(":hi BufferVisible guibg=NONE")
vim.cmd(":hi BufferVisibleIndex guibg=NONE")


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
