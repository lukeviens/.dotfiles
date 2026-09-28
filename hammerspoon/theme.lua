-- theme.lua — the shared palette, read from ~/.config/theme/colors: the ONE substrate every
-- surface reads. The town theme resident owns that file (and cycles it via Caps t); no palette
-- is hardcoded here — the resident regenerates the file from its catalog if it ever goes missing.
-- `start` listens for the palette fact and applies it: HS's own chrome, the picker, the live zsh
-- prompts, macOS light/dark, and Claude Code's theme.
local t = {}
local f = io.open(os.getenv("HOME") .. "/.config/theme/colors", "r")
if f then
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.+)$")
    if k and v then t[k] = v end
  end
  f:close()
end

-- d = { sh, hud, picker } — passed in, not required: hud and picker require this table.
function t.start(town, d)
  local lastMode
  town.listen("theme", function(w)
    if w.tense == "future" then return end   -- the cycle intention (Caps t) is for the resident
    local changed = false
    for k, v in pairs(w.body) do if t[k] ~= v then t[k] = v; changed = true end end
    if changed then
      d.hud.toast("theme ↻")
      -- repaint any live interactive zsh prompts that registered themselves (see .zshrc): SIGUSR1
      -- fires their TRAPUSR1, which re-reads the palette and redraws. Only a pid that IS a live zsh
      -- (guards against PID reuse); any stale registration is removed in passing. Async.
      d.sh('d="$HOME/.cache/town/shells"; [ -d "$d" ] || exit 0; for f in "$d"/*; do [ -e "$f" ] || continue; ' ..
        'p=${f##*/}; case "$(ps -p "$p" -o comm= 2>/dev/null)" in *zsh) kill -USR1 "$p" 2>/dev/null;; *) rm -f "$f";; esac; done')
    end
    d.picker.theme(w.body)   -- recolour the live picker webview (Caps f)
    -- macOS light/dark follows the palette's mode — only when it changes, so dark→black or
    -- sun→light don't re-flip the whole system.
    if w.body.mode and w.body.mode ~= lastMode then
      lastMode = w.body.mode
      local dark = w.body.mode ~= "light"
      hs.task.new("/usr/bin/osascript", nil, { "-e",
        'tell application "System Events" to tell appearance preferences to set dark mode to ' .. tostring(dark) }):start()
      -- Claude Code follows: the matching ANSI theme, so it rides the terminal palette. Atomic,
      -- preserves the rest of settings.json; no-op without jq or the file.
      local ctheme = dark and "dark-ansi" or "light-ansi"
      d.sh('s="$HOME/.claude/settings.json"; command -v jq >/dev/null 2>&1 || exit 0; [ -f "$s" ] || exit 0; ' ..
        'tmp=$(mktemp) && jq --arg v "' .. ctheme .. '" \'.theme = $v\' "$s" > "$tmp" && mv "$tmp" "$s"')
    end
  end)
end

return t
