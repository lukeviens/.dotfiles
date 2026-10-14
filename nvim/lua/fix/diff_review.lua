-- Where fix/server.lua's transport meets ask/init.lua's change-view UI: the thing an external
-- caller (a Claude Code hook, anything else later) actually calls through --remote-expr.
local M = {}

-- same 1-line convention as ask/init.lua's own project_root — duplicated on purpose to keep
-- fix/ independent of ask/.
local function project_root(bufnr)
	return vim.fs.root(bufnr, { ".git", "go.mod" }) or vim.fn.getcwd()
end

local function read_file(path)
	local f = io.open(path, "rb")
	if not f then return "" end
	local content = f:read("a")
	f:close()
	return content
end

-- old_path/new_path: temp files holding the old/new content -- arbitrary code through inline
-- string escaping is fragile. meta_json: unused, room to grow.
--
-- Returns immediately: "ok" once the review is shown, "error: <message>" if it never opened.
-- Blocks nothing -- a human's decision reaches result_path later, written by on_resolved; the
-- hook script polls for it.
function M.review_from_paths(file_path, old_path, new_path, meta_json, result_path)
	local ok, err = pcall(function()
		local old_text, new_text = read_file(old_path), read_file(new_path)

		local bufnr = vim.fn.bufadd(file_path)
		-- two different "do you want to...?" prompts can block here, with nobody over RPC to
		-- answer either: a stale .swp triggers "E325: ATTENTION" (shortmess+=A skips it), and
		-- reloading a buffer this same file was already reviewed in (a second edit to it,
		-- after an earlier accept already wrote the first one to disk) triggers "W11: file
		-- changed, reload?" (autoread skips that one). The modified-buffer fail-safe elsewhere
		-- is the real guard against an actual conflicting edit -- neither prompt is needed for
		-- that.
		local shortmess, autoread = vim.o.shortmess, vim.bo[bufnr].autoread
		vim.opt.shortmess:append("A")
		vim.bo[bufnr].autoread = true
		local load_ok = pcall(vim.fn.bufload, bufnr)
		vim.o.shortmess = shortmess
		vim.bo[bufnr].autoread = autoread
		if not load_ok then error("could not load " .. file_path) end

		require("ask").show_change({
			root = project_root(bufnr),
			target_buf = bufnr,
			old_text = old_text,
			new_text = new_text,
			on_resolved = function(decision, comment_text, skip_reason)
				local out
				if decision == "accept" then
					out = { decision = "allow", additionalContext = comment_text }
				elseif decision == "reject" then
					out = { decision = "deny", reason = comment_text or "change rejected in nvim's change view, no reason given" }
				else -- decision == nil: a fail-safe tripped before the review ever opened
					out = { decision = "ask", reason = skip_reason or "review skipped" }
				end
				vim.fn.writefile({ vim.json.encode(out) }, result_path)
			end,
		})
	end)
	return ok and "ok" or ("error: " .. tostring(err))
end

-- the actual entrypoint a --remote-expr call reaches (see fix/server.lua, which defines
-- _G.FixServer's other members and guarantees this table exists).
_G.FixServer = _G.FixServer or {}
function _G.FixServer.review_diff(file_path, old_path, new_path, meta_json, result_path)
	return M.review_from_paths(file_path, old_path, new_path, meta_json, result_path)
end

return M
