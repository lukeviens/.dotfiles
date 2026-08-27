-- ~/.config/hammerspoon/init.lua
-- leader-key launcher on a shared substrate.
--   theme.lua    the palette (same file wezterm reads)
--   picker.lua   a fully-themed webview overlay picker — the seam: {choices, onSelect, onFavourite}
--   favourites.lua  persistent number slots (storage only)
--   init.lua     the data (kinds, leaves) + the keymap

local theme      = require("theme")
local picker     = require("picker")
local favourites = require("favourites")
local function color(hex) return { hex = hex, alpha = 1.0 } end

-- one in-theme alert style: always a bg fill + a palette stroke; the rest defaults
local function style(o)
  return {
    fillColor = color(theme.bg), strokeColor = color(o.stroke),
    textColor = color(o.text or theme.fg),
    strokeWidth = o.sw or 2, radius = o.radius or 8, textSize = o.size or 14,
  }
end

-- a small, in-theme toast (the raw hs.alert is huge and off-palette)
local function toast(msg)
  hs.alert.closeAll()
  hs.alert.show(msg, style{ stroke = theme.accent, sw = 1, size = 13 }, 0.7)
end

local HOME     = os.getenv("HOME")
local watchers = {}   -- anchor pathwatchers so they aren't garbage-collected

-- ── apps (⌃M f) — cached; ~300 iconForFile calls shouldn't run every open ─────
local APP_DIRS = {
  "/Applications", "/Applications/Utilities",
  "/System/Applications", "/System/Applications/Utilities",
  HOME .. "/Applications",
}

local app_cache
local function list_apps()
  if app_cache then return app_cache end
  local seen, out = {}, {}
  for _, dir in ipairs(APP_DIRS) do
    if hs.fs.attributes(dir) then
      for file in hs.fs.dir(dir) do
        if file:match("%.app$") then
          local name = file:gsub("%.app$", "")
          if not seen[name] then
            seen[name] = true
            local path = dir .. "/" .. file
            out[#out + 1] = { text = name, icon = hs.image.iconForFile(path), iconKey = path, kind = "app" }
          end
        end
      end
    end
  end
  app_cache = out
  return out
end

for _, dir in ipairs({ "/Applications", HOME .. "/Applications" }) do
  if hs.fs.attributes(dir) then
    watchers[#watchers + 1] = hs.pathwatcher.new(dir, function() app_cache = nil end):start()
  end
end

-- ── windows (⌃M w) — live, so no cache ────────────────────────────────────────
local function list_windows()
  local out = {}
  for _, w in ipairs(hs.window.orderedWindows()) do
    local title = w:title()                    -- one accessibility query, reused
    if w:isStandard() and title ~= "" then
      local app  = w:application()
      local name = app and app:name() or "?"
      local bid  = app and app:bundleID()
      out[#out + 1] = {
        text = name .. " — " .. title,
        icon = bid and hs.image.imageFromAppBundle(bid) or nil,
        iconKey = bid, win = w, kind = "window", app = name, title = title,
      }
    end
  end
  return out
end

-- ── sesh sessions (⌃M s) — switch the attached WezTerm client to the choice ───
local TMUX        = "/opt/homebrew/bin/tmux"
local WEZTERM_BID = "com.github.wez.wezterm"

local function list_sessions()
  local out = {}
  local raw = hs.execute(TMUX .. " list-sessions -F '#{session_name}' 2>/dev/null") or ""
  local icon = hs.image.imageFromAppBundle(WEZTERM_BID)
  for line in raw:gmatch("[^\r\n]+") do
    local name = (line:gsub("%s+$", ""))
    if name ~= "" then
      out[#out + 1] = { text = name, icon = icon, iconKey = "wezterm", kind = "session" }
    end
  end
  return out
end

-- pass the session name as a real argv element (no shell string → no injection).
local function connect_session(name)
  hs.application.launchOrFocus("WezTerm")
  hs.task.new(TMUX, function(_, out)
    local tty = out and out:match("[^\r\n]+")   -- first attached client
    if tty then hs.task.new(TMUX, nil, { "switch-client", "-c", tty, "-t", name }):start() end
  end, { "list-clients", "-F", "#{client_tty}" }):start()
end

-- ── kinds: each pickable thing knows how to become a favourite and reactivate ──
-- favourite(choice)->target (stored); activate(target) reopens it from storage alone.
local KINDS = {
  app = {
    favourite = function(c) return { kind = "app", name = c.text } end,
    activate  = function(t)
      local app = hs.application.get(t.name)
      if app and app:isFrontmost() then          -- already here → cycle its windows (like ⌘`)
        local wins = {}
        for _, w in ipairs(app:allWindows()) do
          if w:isStandard() then wins[#wins + 1] = w end
        end
        if #wins > 1 then
          table.sort(wins, function(a, b) return a:id() < b:id() end)   -- stable ring order
          local cur, idx = hs.window.focusedWindow(), 1
          for i, w in ipairs(wins) do if cur and w:id() == cur:id() then idx = i; break end end
          wins[(idx % #wins) + 1]:focus()
          return
        end
      end
      hs.application.launchOrFocus(t.name)        -- not here (or single window) → just go
    end,
  },
  session = {
    favourite = function(c) return { kind = "session", name = c.text } end,
    activate  = function(t) connect_session(t.name) end,
  },
  window = {
    favourite = function(c) return { kind = "window", app = c.app, title = c.title } end,
    activate = function(t)                       -- windows are ephemeral: best-effort re-find
      local a = t.app and hs.application.get(t.app)
      if a then
        for _, w in ipairs(a:allWindows()) do
          if w:title() == t.title then w:focus(); return end
        end
        a:activate()                             -- fallback: focus the app
      elseif t.app then
        hs.application.launchOrFocus(t.app)
      end
    end,
  },
}

local function favourite(choice, slot)           -- the picker footer already confirms in-theme
  local k = KINDS[choice.kind]
  if k then favourites.set(slot, k.favourite(choice)) end
end

local function jump(slot)
  local t = favourites.get(slot)
  if not t then toast("⌃M " .. slot .. " · empty"); return end
  local k = KINDS[t.kind]
  if k then k.activate(t) end
end

local function slot_label(t) return t and (t.name or t.title or t.app) or nil end

-- ── leaves: picker actions. each is { key, label, action }; onFavourite enables ⭐ ─
local function pick(key, label, list, onSelect)
  return { key = key, label = label, action = function()
    picker.show({ placeholder = label, choices = list(), onSelect = onSelect, onFavourite = favourite })
  end }
end

local leaves = {
  pick("f", "apps",     list_apps,     function(c) hs.application.launchOrFocus(c.text) end),
  pick("w", "windows",  list_windows,  function(c) if c.win then c.win:focus() end end),
  pick("s", "sessions", list_sessions, function(c) connect_session(c.text) end),
}

-- ── leader:  ⌃M  then …  ──────────────────────────────────────────────────────
local TIMEOUT = 3     -- seconds before an idle leader auto-exits (which-key style)
local ALERT = style{ stroke = theme.active, radius = 10, size = 16 }

local leader, leaderTimer = hs.hotkey.modal.new({ "ctrl" }, "m"), nil
function leader:entered()
  hs.alert.closeAll()
  local m = "  search\n"
  for _, lf in ipairs(leaves) do m = m .. "  " .. lf.key .. "   " .. lf.label .. "\n" end
  m = m .. "\n  favourites\n"
  local any = false
  for i = 1, 9 do
    local lbl = slot_label(favourites.get(i))
    if lbl then any = true; m = m .. "  " .. i .. "   " .. lbl .. "\n" end
  end
  if not any then m = m .. "  · press 1–9 inside a picker to favourite\n" end
  m = m .. "\n  esc   cancel"
  hs.alert.show(m, ALERT, TIMEOUT)
  leaderTimer = hs.timer.doAfter(TIMEOUT, function() leader:exit() end)   -- don't get stuck
end
function leader:exited()
  hs.alert.closeAll()
  if leaderTimer then leaderTimer:stop(); leaderTimer = nil end
end

for _, lf in ipairs(leaves) do
  leader:bind({}, lf.key, function() leader:exit(); lf.action() end)
end
for i = 1, 9 do
  leader:bind({}, tostring(i), function() leader:exit(); jump(i) end)
end
leader:bind({}, "escape", function() leader:exit() end)

-- ── reload on save (nvim-style DX) ────────────────────────────────────────────
watchers[#watchers + 1] = hs.pathwatcher.new(HOME .. "/.config/hammerspoon/", function(files)
  for _, f in ipairs(files) do if f:match("%.lua$") then hs.reload() end end
end):start()

hs.alert.show("hammerspoon: loaded", style{ stroke = theme.accent, text = theme.accent }, 1.2)
