-- A deleted/renamed cwd makes vim.uv.cwd() nil. Neovim's filetype detector calls
-- vim.fs.abspath() on Neo-tree's relative buffer name before Neo-tree can mark it
-- nofile, and abspath asserts in that state. Restore a real cwd before Neo-tree
-- chooses its root, and again before it names a new sidebar buffer.
local last_good_cwd = vim.uv.cwd()
vim.api.nvim_create_autocmd("DirChanged", {
	group = vim.api.nvim_create_augroup("NeoTreeCwdRecovery", { clear = true }),
	callback = function()
		last_good_cwd = vim.uv.cwd() or last_good_cwd
	end,
})

local function existing_dir(path)
	if not path or path:sub(1, 1) ~= "/" then return nil end
	while path do
		local stat = vim.uv.fs_stat(path)
		if stat and stat.type == "directory" then return path end
		local parent = vim.fs.dirname(path)
		if parent == path then break end
		path = parent
	end
end

local function restore_cwd()
	if vim.uv.cwd() then return end
	local name = vim.api.nvim_buf_get_name(0)
	local file_dir = vim.bo.buftype == "" and name:sub(1, 1) == "/" and vim.fs.dirname(name) or nil
	local ok, prior = pcall(vim.fn.getcwd)
	local target = existing_dir(file_dir) or existing_dir(last_good_cwd)
		or (ok and existing_dir(prior)) or existing_dir(vim.env.HOME) or "/"
	local lost = last_good_cwd
	vim.api.nvim_set_current_dir(target)
	vim.schedule(function()
		vim.notify("Working directory unavailable: " .. (lost or "unknown") .. "; moved to " .. target,
			vim.log.levels.WARN)
	end)
end

return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons",
			"MunifTanjim/nui.nvim",
			"s1n7ax/nvim-window-picker"
		},
		opts = {
			enable_git_status = true,
			enable_diagnostics = true,
			event_handlers = {
				{ event = "state_created", handler = restore_cwd },
				{ event = "neo_tree_window_before_open", handler = restore_cwd },
			},
			filesystem = {
				follow_current_file = {
					enabled = true,
					leave_dirs_open = false,
				}
			},
			buffers = {
				follow_current_file = {
					enabled = true, -- This will find and focus the file in the active buffer every time
					leave_dirs_open = false, -- `false` closes auto expanded dirs, such as with `:Neotree reveal`
				}
			}
		}
	}
}
