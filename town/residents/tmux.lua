-- tmux — recolour the status bar on the theme; enter a session the town means to.
local TX = bins.tmux -- NB: not $TMUX (tmux's own server-socket var)
local function set(opt, val) os.execute(TX .. " set -g " .. opt .. " '" .. val .. "'") end

return react {
  on("theme", function(w)
    if not w.body.bg then return end
    -- update the @color_* options the whole status bar reads (see tmux.conf) — not just
    -- status-style — so EVERY segment (window list, status-left) re-colours, then repaint.
    local c = w.body
    set("@color_bg", c.bg);         set("@color_fg", c.fg)
    set("@color_subtle", c.subtle); set("@color_active", c.active); set("@color_accent", c.accent)
    set("@color_active_bg", c.bg);  set("@color_active_fg", c.active)  -- mirror tmux.conf's derivation
    os.execute(TX .. " refresh-client -S 2>/dev/null")
  end),
  on({ kind = "place", tense = "future", where = function(b) return b.kind == "session" end }, function(w)
    os.execute(TX .. " switch-client -t '" .. w.body.name .. "' 2>/dev/null")
    return intent("place", { kind = "window", app = "WezTerm" })  -- raise the terminal too
  end),
}
