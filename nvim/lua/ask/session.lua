-- One saved conversation per project root: the session_id that --resume needs, plus every
-- turn as typed and answered, so a restarted nvim can find the thread and show it again.
-- Turns are stored as text, not buffer lines -- replaying them through transcript.start_turn
-- renders them exactly as a live turn would, highlights included.
local M = {}

local function path(root)
	return vim.fn.stdpath("state") .. "/ask-sessions/" .. vim.fn.sha256(root) .. ".json"
end

-- { session_id, turns = { { question, answer } } }, or an empty one if nothing is saved.
function M.load(root)
	local p = path(root)
	if vim.uv.fs_stat(p) == nil then return { turns = {} } end
	local ok, saved = pcall(vim.json.decode, table.concat(vim.fn.readfile(p), "\n"))
	if not ok or type(saved) ~= "table" then return { turns = {} } end
	saved.turns = saved.turns or {}
	return saved
end

function M.append_turn(root, session_id, question, answer)
	local saved = M.load(root)
	saved.session_id = session_id
	saved.turns[#saved.turns + 1] = { question = question, answer = answer }
	vim.fn.mkdir(vim.fs.dirname(path(root)), "p")
	vim.fn.writefile({ vim.json.encode(saved) }, path(root))
end

function M.clear(root)
	pcall(vim.uv.fs_unlink, path(root))
end

return M
