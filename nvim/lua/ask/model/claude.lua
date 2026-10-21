-- The claude -p implementation of ask/model's interface (see ask/model/init.lua). Every
-- claude -p invocation in ask/ lives here -- no other module builds a claude command line or
-- knows its flags. Knows nothing about nvim buffers, windows, or panels.
local M = {}

local TOOLS = { "Read", "Grep", "Glob", "Edit", "Write" }
-- --allowed-tools alone isn't enforced under this account's defaultMode: "auto". --permission-
-- mode default overrides that inherited mode for this one call, making --allowed-tools a real
-- allowlist -- and covers any tool added later, where an enumerated deny-list wouldn't.
local HOOK_SCRIPT = vim.fn.expand("~/.claude/hooks/nvim-diff-review.sh")
-- seconds; must stay just under the hook's own TIMEOUT_MS, or Claude Code's own fallback
-- prompt wins the race instead of the hook's timeout.
local HOOK_TIMEOUT_S = 1810
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function format_bytes(n)
	if n < 1024 then return n .. "B" end
	return string.format("%.1fKB", n / 1024)
end

-- --settings doesn't load hooks -- only a real settings file does. Adds the review hook to
-- settings.local.json (untracked, never settings.json) for one call's lifetime, keeping
-- whatever the user already has there. Returns a restore function that puts the file back as
-- it was; it also runs if nvim quits mid-call, so the hook never outlives the call.
local function with_hook_settings(root)
	local dir = root .. "/.claude"
	local path = dir .. "/settings.local.json"
	local raw = vim.uv.fs_stat(path) and vim.fn.readfile(path) or nil

	local ok, settings = pcall(vim.json.decode, table.concat(raw or {}, "\n"))
	if not ok or type(settings) ~= "table" then settings = {} end

	-- strip any of our own PreToolUse entries first -- a hard crash (kill -9, no VimLeavePre)
	-- can leave one behind. Without this, every later call reads that leftover back as part of
	-- `prior` and restores right back to it, wiring the hook into this project forever (and
	-- piling up a fresh duplicate entry each time) instead of just for the length of one call.
	if settings.hooks and settings.hooks.PreToolUse then
		local cleaned = {}
		for _, entry in ipairs(settings.hooks.PreToolUse) do
			local ours = false
			for _, h in ipairs(entry.hooks or {}) do
				if h.command == HOOK_SCRIPT then ours = true end
			end
			if not ours then cleaned[#cleaned + 1] = entry end
		end
		settings.hooks.PreToolUse = #cleaned > 0 and cleaned or nil
		if vim.tbl_isempty(settings.hooks) then settings.hooks = nil end
	end
	local prior = not vim.tbl_isempty(settings) and { vim.json.encode(settings) } or nil

	settings.hooks = settings.hooks or {}
	settings.hooks.PreToolUse = settings.hooks.PreToolUse or {}
	table.insert(settings.hooks.PreToolUse, {
		matcher = "Edit|Write",
		hooks = { { type = "command", command = HOOK_SCRIPT, timeout = HOOK_TIMEOUT_S } },
	})
	vim.fn.mkdir(dir, "p")
	vim.fn.writefile({ vim.json.encode(settings) }, path)

	local autocmd
	local function restore()
		pcall(vim.api.nvim_del_autocmd, autocmd)
		if prior then
			vim.fn.writefile(prior, path)
		else
			pcall(vim.uv.fs_unlink, path)
		end
	end
	autocmd = vim.api.nvim_create_autocmd("VimLeavePre", { once = true, callback = restore })
	return restore
end

-- Runs one claude -p turn. opts: prompt, root, session_id (string|nil), on_status(text),
-- on_delta(text_so_far), on_done(ok, body, session_id), read_only (bool, default false).
--
-- Edit/Write are on by default: a PreToolUse hook (with_hook_settings) routes every proposed
-- change through ask's diff review before it touches disk, and that review is the gate. The
-- hook reaches this instance via $FIX_NVIM_SOCKET -- no registry needed, since only one
-- instance can be spawning this call.
--
-- read_only=true (ask/panel/discuss.lua) drops to Read/Grep/Glob -- no hook needed, nothing it
-- does can reach disk. Deliberate: a discussion must never become a second, untracked way to
-- change files while the human is still deciding on the one already open for review.
function M.run(opts)
	local tools = opts.read_only and { "Read", "Grep", "Glob" } or TOOLS
	local args = {
		"claude", "-p", opts.prompt, "--allowed-tools", table.concat(tools, " "),
		"--permission-mode", "default", "--permission-prompts", "none",
		"--output-format", "stream-json", "--include-partial-messages", "--verbose",
	}
	if not opts.read_only then
		vim.list_extend(args, {
			-- without this, nothing ever tells the model its edits are reviewed at all -- a
			-- deny just looks like an ordinary permission failure, with no sense that a human
			-- read the diff and may have left an actual reason.
			"--append-system-prompt",
			"Edit and Write calls are reviewed by the user in their editor before taking "
				.. "effect. A denial's reason, or an approval's additional context, may be the "
				.. "user's own comment on the change -- real feedback to act on, not a generic "
				.. "refusal.",
		})
	end
	-- read_only skips the hook entirely -- restore_hook_settings must still exist (finish()
	-- calls it unconditionally), just as a no-op.
	local restore_hook_settings = opts.read_only and function() end or with_hook_settings(opts.root)
	-- vim.v.servername isn't reliably a listening address -- a real interactive session leaves
	-- it non-empty but unbound. fix.server.address() is the one guaranteed to actually be bound.
	local env = not opts.read_only and { FIX_NVIM_SOCKET = require("fix.server").address() } or nil
	if opts.session_id then
		vim.list_extend(args, { "--resume", opts.session_id })
	end

	-- A byte counter alone looks frozen before the first delta arrives. The spinner keeps the
	-- wait visibly alive; `phase` (set from content_block_start below) names what's actually
	-- happening instead of a flat "Asking...". sent_bytes is only ever the prompt's own size --
	-- a tool call's result feeds back into the model as a fresh round (a second message_start),
	-- sending real additional data we have no way to size: Claude Code never echoes a tool's
	-- result to us. `rounds` counts those message_start events as the honest signal instead of
	-- a fabricated byte count.
	local sent_bytes, received_bytes, rounds = #opts.prompt, 0, 0
	local start_ns, phase, spin_i = vim.uv.hrtime(), "Connecting", 0
	local function render_status()
		spin_i = spin_i % #SPINNER + 1
		local elapsed = (vim.uv.hrtime() - start_ns) / 1e9
		local round = rounds > 1 and (" · round " .. rounds) or ""
		opts.on_status(string.format(
			"%s %s… %.1fs ↑%s ↓%s%s",
			SPINNER[spin_i], phase, elapsed, format_bytes(sent_bytes), format_bytes(received_bytes), round
		))
	end
	local timer = vim.uv.new_timer()
	timer:start(0, 120, vim.schedule_wrap(render_status))

	-- stream-json + include-partial-messages streams content_block_delta events as the model
	-- generates them; plain text mode buffers the whole answer until the process exits. ndjson
	-- lines can split across stdout chunks, so a partial line carries over to the next chunk.
	-- claude -p failing before it ever enters stream-json mode (missing/expired auth, a plain
	-- CLI usage error, ...) prints plain text, not JSON, on stdout. unparsed_chunks keeps every
	-- line that fails vim.json.decode, so that failure reports its real error body instead of a
	-- bare "Error (exit 1):" with nothing after it.
	local pending_line, live_text, final_result, stderr_chunks, unparsed_chunks = "", "", nil, {}, {}
	local function on_stdout(_, data)
		if not data then return end
		received_bytes = received_bytes + #data
		pending_line = pending_line .. data
		local lines = vim.split(pending_line, "\n", { plain = true })
		pending_line = lines[#lines]
		for i = 1, #lines - 1 do
			local ok, obj = pcall(vim.json.decode, lines[i])
			if not ok then
				if lines[i] ~= "" then unparsed_chunks[#unparsed_chunks + 1] = lines[i] end
				goto continue
			end
			if obj.type == "result" then
				final_result = obj
			elseif obj.type == "stream_event" then
				local ev = obj.event
				if ev.type == "message_start" then
					rounds = rounds + 1
				elseif ev.type == "content_block_delta" and ev.delta.type == "text_delta" then
					live_text = live_text .. ev.delta.text
				elseif ev.type == "content_block_start" then
					local block = ev.content_block
					phase = block.type == "tool_use" and ("Using " .. block.name)
						or block.type == "thinking" and "Thinking"
						or block.type == "text" and "Writing"
						or phase
				end
			end
			::continue::
		end
		vim.schedule(function()
			if live_text ~= "" then opts.on_delta(live_text) end
		end)
	end
	local function on_stderr(_, data)
		if data then stderr_chunks[#stderr_chunks + 1] = data end
	end

	local function finish(ok, body)
		timer:stop()
		timer:close()
		restore_hook_settings()
		-- the result event names the session claude actually holds. Without one, a fresh id
		-- may name nothing -- adopting it would make every later --resume fail.
		local held = final_result and final_result.session_id or opts.session_id
		opts.on_done(ok, body, held)
	end

	local spawned, err = pcall(vim.system, args, { cwd = opts.root, env = env, stdout = on_stdout, stderr = on_stderr }, function(result)
		vim.schedule(function()
			-- A trailing line with no newline before EOF never reached on_stdout's loop --
			-- parse it here before falling back to live_text.
			if pending_line ~= "" then
				local ok, obj = pcall(vim.json.decode, pending_line)
				if ok and obj.type == "result" then
					final_result = obj
				else
					unparsed_chunks[#unparsed_chunks + 1] = pending_line
				end
			end
			-- the result event, when present, is the authoritative final text; accumulated
			-- deltas are only a live preview.
			if result.code ~= 0 then
				local stderr_text = table.concat(stderr_chunks)
				local detail = stderr_text ~= "" and stderr_text or table.concat(unparsed_chunks, "\n")
				finish(false, "Error (exit " .. result.code .. ")" .. (detail ~= "" and (":\n" .. detail) or " (no output)"))
			elseif final_result and final_result.is_error then
				finish(false, "Error: " .. tostring(final_result.result))
			else
				finish(true, final_result and final_result.result or live_text)
			end
		end)
	end)
	-- claude missing from PATH throws here, before any callback could ever run.
	if not spawned then finish(false, "Error: " .. tostring(err)) end
end

-- A bare, stateless claude -p call: no tools, no session, no streaming, firing after every turn
-- with nobody watching -- --permission-mode default matters even more here, since an empty
-- --allowed-tools alone isn't enforced under the inherited "auto" mode. on_done(ok, body).
-- haiku: small task, runs every turn. --no-session-persistence: skips leaving a session behind
-- in --resume's list.
function M.quick(prompt, on_done)
	local chunks = {}
	vim.system(
		{
			"claude", "-p", prompt, "--allowed-tools", "", "--permission-mode", "default",
			"--permission-prompts", "none", "--model", "haiku", "--no-session-persistence",
		},
		{ stdout = function(_, data) if data then chunks[#chunks + 1] = data end end },
		function(result)
			vim.schedule(function()
				on_done(result.code == 0, vim.trim(table.concat(chunks)))
			end)
		end
	)
end

return M
