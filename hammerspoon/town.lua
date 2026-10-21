-- town.lua — the bus. HS's ONE persistent connection to the square: it talks words in and hears
-- the news back on the SAME socket (a bidirectional `join`), so there is NO process per word — a
-- fork per Caps f was what stalled HS (each a posix_spawn on the WebKit UI thread). The socket
-- reconnects itself if town restarts. Everything else in the surface is a thin `listen`/`talk`.
local M = { on = {} }

local HOME   = os.getenv("HOME")
local TOWN   = HOME .. "/.config/town/target/release/town"
local SQUARE = HOME .. "/.cache/town/square.sock"
local sq                                 -- the live socket, or nil while (re)connecting
local townlink                           -- the reconnect heartbeat (held here so HS can't GC it)
local lastRx = 0                         -- when we last heard ANY bytes — our proof of life
local now = {}                           -- kind → its latest present body

-- the present, as this surface last heard it. a join is greeted with all of it, so it is filled
-- before the first word arrives.
function M.present(kind) return now[kind] end

function M.listen(kind, fn)
  M.on[kind] = M.on[kind] or {}
  table.insert(M.on[kind], fn)
end

local function dispatch(line)            -- one incoming word → its listeners, by kind
  local ok, w = pcall(hs.json.decode, line)
  if ok and w and w.kind and (w.tense or "present") == "present" then now[w.kind] = w.body end
  if ok and w and w.kind and M.on[w.kind] then
    for _, fn in ipairs(M.on[w.kind]) do   -- one bad listener must not take the bus down with it
      local ok, err = pcall(fn, w)
      if not ok then hs.printf("town: listener for '%s' errored: %s", w.kind, tostring(err)) end
    end
  end
end

function M.talk(kind, body, tense)
  local w = { kind = kind, body = body }
  if tense then w.tense = tense end
  local line = hs.json.encode(w)
  if sq and sq:connected() then sq:write(line .. "\n")
  else hs.task.new(TOWN, nil, { "talk", line }):start() end  -- fallback only while reconnecting
end

local function join()                    -- open (or reopen) the one connection to the square
  if sq then pcall(function() sq:disconnect() end) end   -- tear down any stale socket first
  sq = hs.socket.new(function(data)
    -- re-arm while the socket is live. an empty read is not a hangup; treating it as one stops the
    -- loop for good. the connected() guard is what keeps EOF from spinning the main thread.
    if not (sq and sq:connected()) then return end
    if data and data ~= "" then
      lastRx = hs.timer.secondsSinceEpoch()
      for line in data:gmatch("[^\r\n]+") do dispatch(line) end
    end
    sq:read("\n")
  end)
  sq:connect(SQUARE, function()
    lastRx = hs.timer.secondsSinceEpoch()
    sq:write("join\n")
    sq:read("\n")                        -- start the read loop
  end)
end

-- open the connection and keep it open. Call once, AFTER every listener is registered, so nothing
-- misses the present the square greets us with. launchd owns whether town runs; this only connects.
function M.start()
  join()
  -- hs.socket:connected() can lie (stays true on a half-dead socket), so we don't trust it alone:
  -- every tick we ping, town echoes every word back on the join, and if no bytes have landed for a
  -- while the link is really dead → rejoin. Idle-cheap, self-healing.
  townlink = hs.timer.doEvery(2, function()
    if not (sq and sq:connected()) or hs.timer.secondsSinceEpoch() - lastRx > 6 then join()
    else pcall(function() sq:write('{"kind":"ping","tense":"future"}\n') end) end   -- echoes back → refreshes lastRx
  end)
  return M
end

-- teardown on reload — and the GC anchor: because M (returned to `require`) is held forever in
-- package.loaded, and M.stop closes over `sq` + `townlink`, the live socket and heartbeat stay
-- reachable and HS can't collect them out from under us.
function M.stop()
  if townlink then townlink:stop(); townlink = nil end
  if sq then pcall(function() sq:disconnect() end); sq = nil end
end

return M
