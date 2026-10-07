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
  ["leader o"] = back("window"),     -- outer depth: recent mac windows
  ["leader i"] = forward("window"),
  ["tmux o"]   = back("session"),    -- terminal middle depth: recent sessions
  ["tmux i"]   = forward("session"),
  ["chrome o"] = back("tab"),        -- chrome inner depth: recent tabs
  ["chrome i"] = forward("tab"),

  -- ⌃⏎ zoom is the one direct chord left (mac max, or tmux zooms the pane in the terminal).
  -- Directional motion is Caps hjkl — HS glides it: focus in a mac app, or ⌥hjkl emitted into
  -- the terminal so nvim/tmux own the pane motion, wrapping at their edge (depth stays inside).
  ["ctrl return"] = aware("zoom"),
}
-- Caps then 1-9 → jump to a favourite. a plain digit inside the mode, so nothing
-- (Mission Control, apps) can steal it the way ⌃1 was being stolen.
for i = 1, 9 do m["leader " .. i] = jump(i) end

-- Caps hjkl move focus at the current layer; Caps ⇧hjkl do the same one layer OUT (see below).
for _, d in ipairs({ "h", "j", "k", "l" }) do m["leader " .. d] = move(d) end
-- Registers + structure ops HS owns (hjkl grabs the mesh element; % / " split). Declared here so
-- the map stays the whole doc and the ? card derives them; HS binds the keys, town never routes.
m["leader e"]  = surface("edge")    -- arm: hjkl slides the wall (resize)
m["leader c"]  = surface("cell")    -- arm: hjkl carries the tile (swap)
m["leader d"]  = surface("scroll")  -- d / u → half-page down / up (vim C-d/C-u, else copy-mode scrollback)
m["leader u"]  = surface("scroll")
m["leader %"]  = surface("split")   -- % → split left/right
m["leader \""] = surface("split")   -- " → split top/bottom
m["leader m"]  = surface("menu bar")     -- opens it via AX; hjkl/return/esc drive it, all local
m["leader F"]  = surface("click")        -- fuzzy-search & click any labeled on-screen element
-- Caps ⇧hjkl/⇧oi = the same motion at the outermost layer (Shift = outward) — HS owns the binding;
-- declared here so the card stays the whole doc. ⇧o/⇧i flip mac windows from wherever you are.
for _, key in ipairs({ "H", "J", "K", "L", "O", "I" }) do m["leader " .. key] = surface("outer") end
-- Caps ⏎ zooms the inner thing (tmux pane in the terminal — HS routes that; else maximize ↔
-- restore the mac window). Caps ⇧⏎ always goes straight to that same mac maximize, even from
-- inside a terminal pane — same action either way, so one shared label.
m["leader return"]   = arrange("max", "zoom")
m["leader S-return"] = arrange("max", "maximize")

return keymap(m)
