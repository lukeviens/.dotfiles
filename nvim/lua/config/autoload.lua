-- general vim configs
vim.cmd([[
  set number relativenumber
  set tabstop=4
  set shiftwidth=4
  autocmd Filetype lua setlocal tabstop=2
  autocmd Filetype lua setlocal shiftwidth=2
]])

-- telescope
local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})

-- neotree
vim.cmd([[
	Neotree show
]])



-- toggle between neo-tree bits and bobs
vim.g.neotree_toggle_state = 1

function ToggleNeotree()
  if vim.g.neotree_toggle_state == 0 then
    vim.cmd('Neotree filesystem')
    vim.g.neotree_toggle_state = 1
  elseif vim.g.neotree_toggle_state == 1 then
    vim.cmd('Neotree buffers')
    vim.g.neotree_toggle_state = 2
  else
    vim.cmd('Neotree git_status')
    vim.g.neotree_toggle_state = 0
  end
end

-- Map <leader>t to the custom toggle function
vim.api.nvim_set_keymap('n', '<leader>t', ':lua ToggleNeotree()<CR>', { noremap = true, silent = true })

