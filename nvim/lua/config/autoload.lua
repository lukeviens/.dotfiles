--
-- GENERAL
--

-- things going into the hole animation :o 
-- TODO: enable more logic and configuration 
--  - different entity types, e.g. hole consumes, tree stops, etc. 
--  - then, better randomization of scene and events

local function animate_buffer()
  return vim.fn.argc() == 0
end

if animate_buffer() then
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
  local timer = vim.uv.new_timer()

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
end

-- general options
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.clipboard:prepend({ "unnamed", "unnamedplus" })
vim.opt.mouse = "a"

-- filetype-specific indentation
local indent_overrides = {
	lua        = { tabstop = 2, shiftwidth = 2 },
	typescript = { tabstop = 2, shiftwidth = 2 },
	go         = { tabstop = 4, shiftwidth = 4, expandtab = false },
}

vim.api.nvim_create_autocmd("FileType", {
	pattern = vim.tbl_keys(indent_overrides),
	callback = function(ev)
		for opt, val in pairs(indent_overrides[ev.match]) do
			vim.opt_local[opt] = val
		end
	end,
})


---
--- TELESCOPE
---

vim.keymap.set('n', '<leader>ff', function() require('telescope.builtin').find_files() end, { desc = "Find files" })
vim.keymap.set('n', '<leader>fg', function() require('telescope.builtin').live_grep() end, { desc = "Live grep" })
vim.keymap.set('n', '<leader>fb', function() require('telescope.builtin').buffers() end, { desc = "Buffers" })
vim.keymap.set('n', '<leader>fh', function() require('telescope.builtin').help_tags() end, { desc = "Help tags" })


--
-- NEOTREE
--

vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.fn.argc() == 0 then
			vim.cmd('Neotree current')
			vim.api.nvim_create_autocmd("BufEnter", {
				once = true,
				callback = function()
					vim.cmd('bdelete 1')
				end,
			})
		end
	end,
})

vim.keymap.set('n', '<leader>t', '<cmd>Neotree current reveal filesystem<CR>', { desc = "Neotree filesystem" })
vim.keymap.set('n', '<leader>tt', '<cmd>Neotree current reveal buffers<CR>', { desc = "Neotree buffers" })
vim.keymap.set('n', '<leader>ttt', '<cmd>Neotree current reveal git_status<CR>', { desc = "Neotree git status" })


--
-- i LANGUAGE
--

vim.filetype.add({ extension = { i = "i" } })

vim.api.nvim_create_autocmd("FileType", {
	pattern = "i",
	callback = function()
		-- i identifiers include - / ?
		vim.opt_local.iskeyword:append("-,/,?")

		-- LSP keymaps (buffer-local)
		local opts = { buffer = 0 }
		vim.keymap.set("n", "gd", require('telescope.builtin').lsp_definitions, opts)
		vim.keymap.set("n", "gr", require('telescope.builtin').lsp_references, opts)
		vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
		vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
		vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
		vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts)
		vim.keymap.set("n", "<leader>ds", require('telescope.builtin').lsp_document_symbols, opts)

		vim.lsp.start({
			name = "i-lsp",
			cmd = { "/Users/lukeviens/code/i/i/i", "worlds/lsp.i" },
			root_dir = vim.fs.dirname(
				vim.fs.find({ ".git" }, { upward = true })[1]
			),
		})
	end,
})

---
--- EDITOR LOOK
---

-- transparent background overrides (applied after colorscheme loads)
vim.api.nvim_create_autocmd("ColorScheme", {
	callback = function()
		local transparent = {
			"Normal", "StatusLine", "StatusLineNC", "TabLine", "LspProgressNormal",
			"BufferCurrent", "BufferCurrentIndex", "BufferCurrentMod",
			"BufferCurrentSign", "BufferCurrentTarget",
			"BufferInactive", "BufferInactiveIndex", "BufferInactiveSign",
			"BufferOffset", "BufferTabpageFill", "BufferTabpages",
			"BufferVisible", "BufferVisibleIndex",
		}
		for _, group in ipairs(transparent) do
			vim.api.nvim_set_hl(0, group, { bg = "NONE", ctermbg = "NONE" })
		end
		vim.api.nvim_set_hl(0, "BufferCurrent", { bg = "NONE", fg = "#fbf1f1" })
	end,
})
-- trigger it now for the current colorscheme
vim.cmd("doautocmd ColorScheme")


-- gitblame virtual text disabled (shown in lualine instead)
vim.g.gitblame_display_virtual_text = 0
