-- town.lua — nvim as a town surface. One connection to the square, held: nvim reports what only
-- nvim knows (its RPC socket, its cwd) and obeys the words town sends it. A `town talk` per event
-- was a process spawned to say one word.
local M = { on = {} }

local SQUARE = vim.fn.expand("~/.cache/town/square.sock")
local pane = os.getenv("TMUX_PANE")
local ch, buf, link = nil, "", nil
local focused                       -- the socket of the nvim town last called focused

function M.listen(kind, fn)
  M.on[kind] = M.on[kind] or {}
  table.insert(M.on[kind], fn)
end

function M.talk(kind, body, tense)
  if not ch then return end
  local w = { kind = kind, body = body }
  if tense then w.tense = tense end
  pcall(vim.fn.chansend, ch, vim.json.encode(w) .. "\n")
end

-- are we the nvim town means? every instance hears every `focus`, so each knows who is current.
function M.mine() return focused == vim.v.servername end

local function dispatch(line)
  local ok, w = pcall(vim.json.decode, line)
  if not (ok and w and w.kind) then return end
  if w.kind == "focus" and type(w.body) == "table" then focused = w.body.socket end
  for _, fn in ipairs(M.on[w.kind] or {}) do pcall(fn, w) end
end

local function heard(_, data)
  if not data then return end
  buf = buf .. table.concat(data, "\n")
  while true do
    local nl = buf:find("\n", 1, true)
    if not nl then break end
    dispatch(buf:sub(1, nl - 1))
    buf = buf:sub(nl + 1)
  end
end

local function join()
  if ch then pcall(vim.fn.chanclose, ch) end
  ch, buf = nil, ""
  local ok, c = pcall(vim.fn.sockconnect, "pipe", SQUARE, { on_data = heard })
  if ok and type(c) == "number" and c > 0 then
    ch = c
    pcall(vim.fn.chansend, ch, "join\n")   -- two-way: hear the news and talk on the one socket
  end
end

local function focus()
  M.talk("focus", { socket = vim.v.servername, cwd = vim.fn.getcwd(), pane = pane })
end

function M.start()
  if not pane then return M end   -- outside tmux nvim is not a pane town can name
  join()
  local grp = vim.api.nvim_create_augroup("Town", { clear = true })
  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained", "DirChanged" }, { group = grp, callback = focus })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = grp, callback = function()
    if link then link:stop() end
    if ch then pcall(vim.fn.chanclose, ch) end
  end })
  -- town restarts; rejoin. chansend on a dead channel throws, which is how we notice.
  link = vim.uv.new_timer()
  link:start(2000, 2000, vim.schedule_wrap(function()
    if not ch or not pcall(vim.fn.chansend, ch, "") then join() end
  end))
  if vim.v.vim_did_enter == 1 then focus() end
  return M
end

return M
