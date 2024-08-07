-- Ensure vim.g.bigfile_size is set to a default value
vim.g.bigfile_size = 1024 * 1024 * 1.5 -- 1.5 MB

-- have to set this early or else nvim freaks out
vim.opt.termguicolors = true

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- all plugins
require("lazy").setup("plugins")

-- general vim config
require("config.autoload")
