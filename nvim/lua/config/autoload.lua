-- general vim configs
vim.cmd([[
  set number relativenumber
  set tabstop=4
  set shiftwidth=4
  autocmd Filetype lua setlocal tabstop=2
  autocmd Filetype lua setlocal shiftwidth=2

	nnoremap <silent> <C-j> <Cmd>NvimTmuxNavigateDown<CR>
	nnoremap <silent> <C-k> <Cmd>NvimTmuxNavigateUp<CR>
	nnoremap <silent> <C-l> <Cmd>NvimTmuxNavigateRight<CR>
	nnoremap <silent> <C-\> <Cmd>NvimTmuxNavigateLastActive<CR>
	nnoremap <silent> <C-Space> <Cmd>NvimTmuxNavigateNext<CR>

]])


-- neotree configs
if next(vim.fn.argv()) ~= nil then
	vim.cmd([[
		Neotree show
		Neotree %:p:h
	]])
else
	vim.cmd([[
		Neotree position=current
	]])
end

-- telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
