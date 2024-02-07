-- general vim configs
vim.cmd([[
  set number relativenumber
  set tabstop=4
  set shiftwidth=4
  autocmd Filetype lua setlocal tabstop=2
  autocmd Filetype lua setlocal shiftwidth=2
]])

-- neotree configs
vim.cmd([[
  Neotree show
	Neotree %:p:h
]])

