-- A swap file means one of two things and only one is worth stopping for: someone is editing this
-- file now, or an nvim died holding unsaved changes. Anything else is debris — and debris is most
-- of it, because a rename of the machine orphans every swap the old hostname wrote.
--
-- Never leave it to the prompt. E325 propagates as a Lua error through whatever called `:edit`,
-- so a stale swap turns into a stack traceback out of neo-tree rather than a question.
local function held_by_a_live_nvim(i)
  if i.host ~= vim.uv.os_gethostname() then return false end   -- another machine's pid means nothing
  if not i.pid or i.pid <= 0 then return false end
  local ok, res = pcall(vim.uv.kill, i.pid, 0)
  return ok and res == 0
end

vim.api.nvim_create_autocmd("SwapExists", {
  group = vim.api.nvim_create_augroup("Swap", { clear = true }),
  callback = function()
    local i = vim.fn.swapinfo(vim.v.swapname)
    local held = held_by_a_live_nvim(i)
    -- a clean swap holds nothing to recover; it only ever said "someone may be editing this"
    if not i.error and (i.dirty or 0) == 0 and not held then
      vim.v.swapchoice = "d"
      return
    end
    vim.v.swapchoice = "o"
    local why = held and "another nvim has it open" or "unsaved changes are in it — :recover"
    vim.schedule(function() vim.notify("swap: " .. why .. "; opened read-only", vim.log.levels.WARN) end)
  end,
})
