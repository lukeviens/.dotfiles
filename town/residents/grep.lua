-- grep — on the intention to grep, live_grep in the focused nvim.
local NVIM = bins.nvim
return when("grep", function()
  local f = present("focus")
  if f and f.socket then
    os.execute(NVIM .. " --server '" .. f.socket
      .. "' --remote-send '<C-\\><C-n>:Telescope live_grep<CR>' >/dev/null 2>&1 &")
  end
end)
