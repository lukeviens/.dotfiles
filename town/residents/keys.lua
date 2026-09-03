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
-- Caps ⇧hjkl = the same motion one layer OUT (Shift = outward) — HS owns it; declared for the card.
for _, key in ipairs({ "H", "J", "K", "L" }) do m["leader " .. key] = surface("outer") end
-- Caps ⏎ zooms the inner thing (tmux pane in the terminal — HS routes that; else maximize ↔ restore
-- the mac window). Caps ⇧⏎ the outer thing: the whole window big — fills the screen, NOT mac-native
-- fullscreen (the one we never use).
m["leader return"]   = arrange("max", "zoom")
m["leader S-return"] = arrange("max", "full")

return keymap(m)
