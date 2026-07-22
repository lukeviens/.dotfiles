return {
  -- nvim-treesitter `main` branch (rewrite) — required for Neovim 0.12.
  -- The old `master`-branch API (configs.setup, ensure_installed, highlight,
  -- indent, incremental_selection, textobjects opts) no longer exists here.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")

      ts.setup({
        -- default install_dir is stdpath("data").."/site"; leave as-is
      })

      -- Parsers to keep installed (was `ensure_installed`). install() is async;
      -- first run downloads/compiles, then they persist. :TSUpdate refreshes.
      ts.install({
        "c",
        "comment",
        "cpp",
        "css",
        "glimmer",
        "go",
        "html",
        "java",
        "javascript",
        "jsdoc",
        "json",
        "markdown",
        "lua",
        "python",
        "query",
        "rst",
        "rust",
        "yaml",
        "svelte",
        "tsx",
        "typescript",
        "terraform",
      })

      -- highlight + indent are per-buffer now: start treesitter on FileType.
      -- pcall guards filetypes whose parser isn't installed yet (no error spam).
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if vim.g.vscode == 1 then
            return
          end
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- textobjects on the matching `main` branch.
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
      })

      local select = require("nvim-treesitter-textobjects.select")
      local swap = require("nvim-treesitter-textobjects.swap")

      local selections = {
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner",
        ["ab"] = "@block.outer",
        ["ib"] = "@block.inner",
      }
      for key, obj in pairs(selections) do
        vim.keymap.set({ "x", "o" }, key, function()
          select.select_textobject(obj, "textobjects")
        end, { desc = "TS select " .. obj })
      end

      vim.keymap.set("n", "<Leader>a", function()
        swap.swap_next("@parameter.inner")
      end, { desc = "TS swap next parameter" })
      vim.keymap.set("n", "<Leader>A", function()
        swap.swap_previous("@parameter.inner")
      end, { desc = "TS swap previous parameter" })
    end,
  },
}
