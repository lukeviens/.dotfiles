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
  vim.bo[first_buffer].swapfile = false

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
      pcall(vim.api.nvim_buf_set_name, first_buffer, scene_str)
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
			local startup_buf = vim.api.nvim_get_current_buf()
			vim.cmd('Neotree current')
			vim.api.nvim_create_autocmd("BufEnter", {
				once = true,
				callback = function()
					if vim.api.nvim_buf_is_valid(startup_buf) then
						vim.cmd('bdelete ' .. startup_buf)
					end
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

local theme = require('config.theme').colors

-- transparent background overrides (applied after colorscheme loads)
vim.api.nvim_create_autocmd("ColorScheme", {
	callback = function()
		local transparent = {
			"Normal", "StatusLine", "StatusLineNC", "TabLine", "TabLineFill", "LspProgressNormal",
			"DiagnosticSignError", "DiagnosticSignWarn", "DiagnosticSignInfo", "DiagnosticSignHint", "DiagnosticSignOk",
			-- BufferCurrent is owned outright below (bg=NONE + live fg), so it's intentionally not here
			"BufferCurrentIndex", "BufferCurrentMod", "BufferCurrentSign", "BufferCurrentTarget",
			"BufferInactive", "BufferInactiveIndex", "BufferInactiveSign",
			"BufferOffset", "BufferTabpageFill", "BufferTabpages", "BufferVisible", "BufferVisibleIndex",
			"LineNr", "LineNrAbove", "LineNrBelow", "CursorLineNr", "SignColumn", "FoldColumn", "EndOfBuffer",
		}
		for _, group in ipairs(transparent) do
			local h = vim.api.nvim_get_hl(0, { name = group, link = false }); h.bg, h.ctermbg = nil, nil; vim.api.nvim_set_hl(0, group, h)
		end
		-- the current buffer-tab fg must follow the LIVE palette (Caps t) — the `theme` above is
		-- cached at startup (dark → white), so on a light swap it'd stay white-on-white. Read fresh.
		local fg = require('config.theme').read().fg or theme.fg
		vim.api.nvim_set_hl(0, "BufferCurrent", { bg = "NONE", fg = fg })
	end,
})
-- trigger it now for the current colorscheme
vim.cmd("doautocmd ColorScheme")

-- Follow the town palette live when ~/.config/theme/colors changes (Caps t), so nvim re-themes
-- with the whole desktop. HYBRID: the four NAMED themes use handcrafted schemes (max polish);
-- any UNKNOWN theme (a random roll) generates a full base16 scheme from the 5 palette values.
-- Either way the bg is transparent, so it rides WezTerm's background.
do
	local palette = require('config.theme')   -- one parser + the one path (config/theme.lua)
	local SCHEME = { dark = "molokai", sun = "tokyonight-day", light = "tokyonight-day", black = "molokai" }
	local uv = vim.uv or vim.loop

	local function read_skin()   -- the whole palette (fresh), over name/mode defaults
		return vim.tbl_extend("force", { name = "dark", mode = "dark" }, palette.read())
	end

	-- the resident writes the derived 16-colour scheme (base00-0F) into the file; read it —
	-- one generator (in the theme resident), shared by WezTerm ANSI and nvim.
	local function file_base16(s)
		local pal = {}
		for i = 0, 15 do local k = string.format("base%02X", i); pal[k] = s[k] end
		return pal
	end

	local function apply()
		local s = read_skin()
		local dark = s.mode ~= "light"
		vim.o.background = dark and "dark" or "light"
		if SCHEME[s.name] then
			pcall(vim.cmd.colorscheme, SCHEME[s.name])           -- named: the handcrafted scheme
		elseif s.bg then                                         -- random/unknown: generate one
			-- mini.base16 maps a 16-colour palette across every modern group (treesitter @-captures,
			-- LSP, semantic tokens, plugins) — no hand-linking, correct on current nvim.
			local ok, base16 = pcall(require, "mini.base16")
			if ok then
				base16.setup({ palette = file_base16(s), use_cterm = false })
				for _, g in ipairs({ "TabLineFill", "TabLine", "StatusLine" }) do vim.api.nvim_set_hl(0, g, { bg = "NONE" }) end
				vim.cmd("doautocmd ColorScheme")   -- run our transparency overrides (incl. the gutter)
			end
		end
	end
	vim.api.nvim_create_autocmd("VimEnter", { callback = apply })  -- match the theme once loaded
	local function watch()
		local h = uv.new_fs_event(); if not h then return end
		h:start(palette.path, {}, vim.schedule_wrap(function()
			apply()
			h:stop(); watch()   -- re-arm (survives the resident's rewrite)
		end))
	end
	watch()
end


-- gitblame virtual text disabled (shown in lualine instead)
vim.g.gitblame_display_virtual_text = 0
