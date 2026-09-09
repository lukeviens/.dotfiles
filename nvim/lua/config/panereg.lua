-- panereg.lua — this nvim is a town resident. It speaks a `focus` word (its RPC
-- socket + cwd + pane) whenever it comes to the foreground, so town's `present`
-- always knows the nvim you're looking at. Also speaks `vim active=0|1` on
-- enter/leave. jobstart (async) throughout, except VimLeave's report, which
-- blocks (vim.fn.system) so it lands before the process exits.
local pane = os.getenv("TMUX_PANE")
if pane then
  local TOWN = vim.fn.expand("~/.config/town/target/release/town")
  local function speak_focus()
    vim.fn.jobstart({ TOWN, "talk", "focus",
      "socket=" .. vim.v.servername, "cwd=" .. vim.fn.getcwd(), "pane=" .. pane })
  end
  local function speak_vim(active)
    vim.fn.jobstart({ TOWN, "talk", "vim", "active=" .. active, "pane=" .. pane })
  end
  local grp = vim.api.nvim_create_augroup("TownResident", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained", "DirChanged" }, { group = grp, callback = speak_focus })
  vim.api.nvim_create_autocmd("VimEnter", { group = grp, callback = function() speak_vim("1") end })
  vim.api.nvim_create_autocmd("VimLeave", { group = grp,
    callback = function() vim.fn.system({ TOWN, "talk", "vim", "active=0", "pane=" .. pane }) end })
  if vim.v.vim_did_enter == 1 then speak_focus(); speak_vim("1") end -- register an already-running nvim
end
