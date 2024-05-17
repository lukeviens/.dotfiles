-- general vim configs
vim.cmd([[
	set number relativenumber
	set tabstop=4
	set shiftwidth=4
	autocmd Filetype lua setlocal tabstop=2
	autocmd Filetype lua setlocal shiftwidth=2
]])

-- mouse mode on
vim.o.mouse = "a"

-- leader
--local map = vim.api.nvim_set_keymap
--local silent = { silent = true, noremap = true }
--map("", "<Space>", "<Nop>", silent)
--vim.g.mapleader = " "
--vim.g.maplocalleader = " "

-- telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})

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


-- delete the initial buffer if not edited
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


--vim.cmd([[
--	Neotree show
--]])

--[[
-- toggle between neo-tree bits and bobs
vim.g.neotree_toggle_state = 1

function ToggleNeotreeState()
	if vim.g.neotree_toggle_state == 0 then
		vim.cmd('Neotree float filesystem')
		vim.g.neotree_toggle_state = 1
	elseif vim.g.neotree_toggle_state == 1 then
		vim.cmd('Neotree float buffers')
		vim.g.neotree_toggle_state = 2
	else
		vim.cmd('Neotree float git_status')
		vim.g.neotree_toggle_state = 0
	end
end

function ToggleNeotree()
	vim.cmd('Neotree toggle')
end

vim.api.nvim_set_keymap('n', '<leader>tt', ':lua ToggleNeotree()<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>t', ':lua ToggleNeotreeState()<CR>', { noremap = true, silent = true })
--]]


vim.api.nvim_set_keymap('n', '<leader>t', ':Neotree float filesystem<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>tt', ':Neotree float buffers<CR>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<leader>ttt', ':Neotree float git_status<CR>', { noremap = true, silent = true })

-- trouble
vim.keymap.set("n", "<leader>xx", function() require("trouble").toggle() end)

vim.g.trouble_toggle_state = 1

function ToggleTroubleState()
	if vim.g.trouble_toggle_state == 0 then
		require("trouble").toggle("workspace_diagnostics")
	elseif vim.g.trouble_toggle_state == 1 then
		require("trouble").toggle("document_diagnostics")
	end
end


vim.api.nvim_set_keymap('n', '<leader>x', ':lua ToggleNeotreeState()<CR>', { noremap = true, silent = true })

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

-- copying
vim.g.clipboard = {
	name = 'OSC 52',
	copy = {
		['+'] = require('vim.ui.clipboard.osc52').copy('+'),
		['*'] = require('vim.ui.clipboard.osc52').copy('*'),
	},
	paste = {
		['+'] = require('vim.ui.clipboard.osc52').paste('+'),
		['*'] = require('vim.ui.clipboard.osc52').paste('*'),
	},
}

-- colorscheme
--local onedark = require('onedark')
--onedark.setup { style = 'warmer' }
--onedark.load()
