-- general vim configs
vim.cmd([[
  set number relativenumber
  set tabstop=4
  set shiftwidth=4
  autocmd Filetype lua setlocal tabstop=2
  autocmd Filetype lua setlocal shiftwidth=2
]])

vim.cmd([[
	Neotree show
]])

-- telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
