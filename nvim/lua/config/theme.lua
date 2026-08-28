local M = {}

M.path = os.getenv("HOME") .. "/.config/theme/colors"   -- the one shared palette file

local function parse_colors(path)
	local colors = {}
	local f = io.open(path, "r")
	if not f then
		return {
			bg     = "#1f1d20",
			fg     = "#f8f8f2",
			subtle = "#878787",
			active = "#f92672",
			accent = "#66d9ef",
		}
	end
	for line in f:lines() do
		local key, val = line:match("^([%w_]+)=(.+)$")
		if key and val then
			colors[key] = val
		end
	end
	f:close()
	return colors
end

-- one parser for the shared palette: `read()` re-reads it fresh (for live Caps-t follows);
-- `colors` is the startup snapshot most callers want.
function M.read() return parse_colors(M.path) end
M.colors = parse_colors(M.path)

return M
