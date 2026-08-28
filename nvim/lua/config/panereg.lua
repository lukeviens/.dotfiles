-- panereg.lua — this nvim is a town resident. It speaks a `focus` word (its RPC
-- socket + cwd + pane) whenever it comes to the foreground, so town's `present`
-- always knows the nvim you're looking at. Async (jobstart) — never blocks.
local pane = os.getenv("TMUX_PANE")
if pane then
  local TOWN = vim.fn.expand("~/.config/town/target/release/town")
  local function speak_focus()
    vim.fn.jobstart({ TOWN, "talk", "focus",
      "socket=" .. vim.v.servername, "cwd=" .. vim.fn.getcwd(), "pane=" .. pane })
  end
  local grp = vim.api.nvim_create_augroup("TownResident", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained", "DirChanged" }, { group = grp, callback = speak_focus })
  if vim.v.vim_did_enter == 1 then speak_focus() end -- register an already-running nvim
end
