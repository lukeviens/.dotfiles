return {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    dashboard = { enabled = true },
    explorer = { enabled = false }, -- using neo-tree
    indent = { enabled = true },
    input = { enabled = true },
    picker = { enabled = false }, -- using telescope
    notifier = { enabled = false }, -- using noice/nvim-notify
    quickfile = { enabled = true },
    scope = { enabled = true },
    scroll = { enabled = false },
    statuscolumn = { enabled = true },
    words = { enabled = true },
  },
}
