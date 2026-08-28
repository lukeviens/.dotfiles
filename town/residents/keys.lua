-- keys — the desktop keymap. Every surface reports the keys it cares about as
-- `key {at, press}`; this is the one place that says what they mean.
local m = {
  ["leader f"] = pick("all"),       -- search everything at once: places, windows, sessions, apps

  -- specific filters, when you want to search just one source
  ["leader a"] = pick("apps"),
  ["leader w"] = pick("windows"),
  ["leader s"] = pick("sessions"),

  ["leader /"] = grep(),
  ["leader t"] = retheme("next"),     -- Caps t → cycle the palette
  ["leader T"] = retheme("random", "random theme"),  -- Caps ⇧T → a fresh random palette
  ["leader o"] = back(),              -- o / i flip back / forward through ALL recent places
  ["leader i"] = forward(),           -- (windows AND sessions — same universe as leader f)
  ["tmux o"]   = back("session"),     -- ⌃b o/i stays session-only inside the terminal
  ["tmux i"]   = forward("session"),

  -- ⌃⏎ zoom is the one direct chord left (mac max, or tmux zooms the pane in the terminal).
  -- Directional motion is Caps hjkl — HS glides it: focus in a mac app, or ⌥hjkl emitted into
  -- the terminal so nvim/tmux own the pane motion and cross back at their edge.
  ["ctrl return"] = aware("zoom"),
}
-- Caps then 1-9 → jump to a favourite. a plain digit inside the mode, so nothing
-- (Mission Control, apps) can steal it the way ⌃1 was being stolen.
for i = 1, 9 do m["leader " .. i] = jump(i) end

-- Caps hjkl move focus between windows; Caps HJKL snap the window to a half.
for _, d in ipairs({ "h", "j", "k", "l" }) do m["leader " .. d] = move(d) end
local halves = { H = "left", J = "bottom", K = "top", L = "right" }
for key, to in pairs(halves) do m["leader " .. key] = arrange(to, "snap") end
-- Caps ⏎ zoom (maximize ↔ restore); Caps ⇧⏎ native macOS fullscreen.
m["leader return"]   = arrange("max", "zoom")
m["leader S-return"] = arrange("fullscreen", "fullscreen")

return keymap(m)
