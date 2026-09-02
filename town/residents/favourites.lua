-- favourites — pinned places on slots 1-9. `save` remembers a place (a present fact,
-- so it persists via the past→present fold); `jump` recalls it and goes there. A slot
-- falls back to DEFAULTS until you pin your own (press 1-9 in the picker to pin).
local DEFAULTS = {
  ["1"] = { kind = "window", app = "WezTerm" },
  ["2"] = { kind = "window", app = "Google Chrome" },
  ["3"] = { kind = "window", app = "Slack" },
  ["4"] = { kind = "window", app = "Spotify" },
}
return react {
  on("save", function(w)
    local faves = present("favourites") or {}
    faves[tostring(w.body.slot)] = w.body.place
    return fact("favourites", faves)
  end),
  on("jump", function(w)
    local faves = present("favourites") or {}
    local slot = tostring(w.body.slot)
    local p = faves[slot] or DEFAULTS[slot]   -- your pin, else the default
    if p then return intent("place", p) end
  end),
}
