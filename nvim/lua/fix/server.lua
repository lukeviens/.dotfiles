-- RPC bootstrap: makes this nvim instance callable from an external process (a Claude Code
-- hook, anything else later) via its own native `nvim --server <addr> --remote-expr` — no
-- bespoke protocol, nothing tied to any one AI tool.
local M = {}

_G.FixServer = _G.FixServer or {}

-- a quick liveness check from outside: `nvim --server <addr> --remote-expr 'v:lua.FixServer.ping()'`
function _G.FixServer.ping()
	return "pong"
end

local address

-- NOT vim.v.servername: a predicted path nvim doesn't bind to in a real interactive session.
-- serverstart() returns the actual bound address; cached so each ask/ turn reuses it instead
-- of spawning a new server.
function M.address()
	if not address then
		address = vim.fn.serverstart()
	end
	return address
end

function M.setup()
	M.address()
	-- registers _G.FixServer.review_diff -- the real entrypoint, loaded eagerly so it's
	-- callable the moment this instance is up, not just once something else happens to
	-- require it first. No instance registry needed: ask/model/claude.lua hands this
	-- instance's own address (M.address(), an env var) directly to the exact claude -p child
	-- it spawns, so there's never any "which instance" ambiguity to resolve.
	require("fix.diff_review")
end

return M
