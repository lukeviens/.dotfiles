-- have to set this early or else nvim freaks out
vim.opt.termguicolors = true

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- all plugins
require("lazy").setup({
	{ import = "plugins" },
})

-- the square first, so everything below can report to it and listen on it
require("config.town").start()

-- a stale swap is debris, not a question (see the file)
require("config.swap")

-- general vim config
require("config.autoload")

-- visual selection -> ask Claude Code a question about it
require("ask").setup()
