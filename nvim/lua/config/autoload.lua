--
-- GENERAL
--

-- things going into the hole animation :o 
-- TODO: enable more logic and configuration 
--  - different entity types, e.g. hole consumes, tree stops, etc. 
--  - then, better randomization of scene and events

local first_buffer = vim.api.nvim_get_current_buf()

local starts = {"🌳"}
local ends   = {"🕳️"}
local scene = {" ", " ", " ", " ", " ", " ", " "}
scene[1] = starts[math.random(#starts)]
scene[#scene] = ends[math.random(#ends)]

local things = {"🧍‍♂️", "🧍‍♀️"}
local thing = things[math.random(#things)]
local thing_pos = 2
local thing_dir = 1
local timer = vim.loop.new_timer()

scene[thing_pos] = thing

local function render_scene()
  local scene_str = table.concat(scene)
  if vim.api.nvim_buf_is_valid(first_buffer) then
    vim.api.nvim_buf_set_name(first_buffer, scene_str)
  end
end
render_scene()

local function is_action(pct)
  return math.random(100) <= pct
end

local function run_scene()
  -- decide action 
  if thing_pos == #scene or thing_pos == 2 then
    if not is_action(10) then return end
  else
    if not is_action(25) then return end
  end

  -- update the direction
  if thing_pos == #scene then
    thing = things[math.random(#things)]
    thing_dir = -1
  elseif thing_pos == 2 then
    thing_dir = 1
  end

  -- update the position 
  thing_pos = thing_pos + thing_dir

  -- in the hole
  if thing_pos == #scene then
    local w = vim.fn.strdisplaywidth(thing)
    scene[thing_pos-1] = string.rep(" ", w)
  -- leaving the hole
  elseif thing_pos == #scene - 1 and thing_dir == -1 then
    scene[thing_pos] = thing
  -- out of the hole
  else
    scene[thing_pos - thing_dir] = " "
    scene[thing_pos] = thing
  end

  -- render the scene  
  render_scene()
end

timer:start(0, 200, vim.schedule_wrap(run_scene))

vim.api.nvim_create_autocmd("BufWipeout", {
  buffer = first_buffer,
  callback = function()
    timer:stop()
    timer:close()
  end,
})

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
