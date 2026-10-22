-- tmux — the connection town holds to tmux, and what tmux means by what it says. Control mode
-- reports what changed instead of being asked, so nothing here polls.
local TX = bins.tmux -- NB: not $TMUX (tmux's own server-socket var)

-- a tmux command over the held connection: no shell, no spawn.
local function tmux(cmd) return work(cmd, { at = "tmux" }) end
local function set(opt, val) talk(tmux("set -g " .. opt .. " '" .. val .. "'")) end

-- Everything town needs from the terminal, in ONE line that names itself. A reply that carries
-- its own label needs no queue: `source-file` answers with a block per line in the file, so
-- matching a reply to its command by position cannot be made to work.
local ASK = "display-message -p 'town|#{session_name}|#{pane_current_command}|#{S:#{session_name}#,}'"

-- the backstop: a command that changes in place (you type `nvim` in the pane you are in) moves
-- no pane and notifies nothing. tmux evaluates a subscription on its own timer rather than on the
-- change, so this is never the fast path — only the one that catches what has no event at all.
local SUBSCRIBE = [[refresh-client -B "vim::#{pane_current_command}"]]

local function vim_is(out) return fact("vim", { active = out:match("vim") and "1" or "0" }) end

-- ── the transport: how a motion becomes a tmux command. one table — tmux's own keymap derives
-- from it (so a physical ⌥h still works) and town's `transport` word is answered from it. nothing
-- injects keystrokes, so there is no key manifest for a surface to read.
local HOME = os.getenv("HOME")

-- defer: the one primitive. Delegate a motion to whoever occupies the pane — if pane_current_command
-- matches `to`, hand the occupant `give`; else run `els`. vim is just one occupant; this is the
-- recursive layer-crossing (mac→tmux→vim), one `defer` per boundary. `els` can itself be a `defer`.
local function defer(to, give, els)
  return ("if -F '#{m:*%s*,#{pane_current_command}}' { send-keys %s } { %s }"):format(to, give, els)
end

local DIR = {   -- per direction: tmux select flag · edge predicate · swap target · nvim resize char · compass · wrap target
  h = { sel = "L", edge = "left",   of = "left-of",  win = ">", compass = "w", wrap = "right"  },
  j = { sel = "D", edge = "bottom", of = "down-of",  win = "-", compass = "s", wrap = "top"    },
  k = { sel = "U", edge = "top",    of = "up-of",    win = "+", compass = "n", wrap = "bottom" },
  l = { sel = "R", edge = "right",  of = "right-of", win = "<", compass = "e", wrap = "left"   },
}
local ORDER = { "h", "j", "k", "l" }   -- deterministic, so the generated file is stable (golden-diffable)

-- point/nav: defer to vim; else, at the pane edge, wrap to the pane at the opposite edge — depth 0
-- stays strictly tmux's; reaching the mac window is the containment tree's job (mode.lua), not nav's.
local function nav(d)
  local x = DIR[d]
  local wrap = ("if -F '#{pane_at_%s}' { select-pane -t '{%s}' } { select-pane -%s }")
    :format(x.edge, x.wrap, x.sel)
  return defer("vim", "M-" .. d, wrap)
end

-- scroll: defer to vim (native C-d/C-u half-page). Otherwise an occupant on the alternate screen
-- owns its own scroll — there is no scrollback for copy-mode to show — so it gets Page Up/Down
-- (Claude Code, less, and the like); only a plain pane gets copy-mode's scrollback. The screen is
-- the fact, not the program's name (which drifts: Claude Code's pane reads as its version number).
local function scroll(vk, page, way)
  local alt = ("if -F '#{alternate_on}' { send-keys %s } { copy-mode -e ; send-keys -X halfpage-%s }"):format(page, way)
  return defer("vim", vk, alt)
end

-- the transport: { verb, dir, key HS injects, tmux command }. one table, two surfaces derive it.
local rows = {}
local function row(verb, dir, key, cmd) rows[#rows + 1] = { verb, dir, key, cmd } end
for _, d in ipairs(ORDER) do
  local x = DIR[d]
  row("point", d, "M-" .. d,         nav(d))                                  -- glide focus
  row("edge",  d, "M-" .. d:upper(),                                          -- push the wall:
    defer("vim", "5 C-w " .. x.win, "resize-pane -" .. x.sel .. " 5"))        -- the nvim split, else the pane
  row("edge-pane", d, "M-" .. x.compass, "resize-pane -" .. x.sel .. " 5")    -- push the wall, tmux only — no defer
  row("cell",  d, "M-C-" .. d,       "swap-pane -t '{" .. x.of .. "}'")       -- carry the tile
end
row("scroll", "d", "M-d",  scroll("C-d", "NPage", "down"))   -- vim C-d / alt-screen PageDown / copy-mode
row("scroll", "u", "M-u",  scroll("C-u", "PPage", "up"))     -- vim C-u / alt-screen PageUp / copy-mode
row("read",   "v", "M-v",   "copy-mode")                     -- point at the screen (a TUI keeps its own Escape)
row("tab", "prev", "M-[", "previous-window")   -- tmux windows (tabs) — unconditional, no defer
row("tab", "next", "M-]", "next-window")       -- one town rung out from pane/split point-nav
row("flip",   "o", "M-o", defer("vim", "M-o", 'run-shell -b "$TOWN talk future place step=1 kind=session"'))     -- previous buffer in nvim, else previous session
row("flip",   "i", "M-i", defer("vim", "M-i", 'run-shell -b "$TOWN talk future place step=-1 kind=session"'))  -- next buffer in nvim, else next session
row("split",  "lr", "M-%",  defer("vim", "C-w v", "split-window -h"))   -- the nvim split, else the pane
row("split",  "tb", "M-\"", defer("vim", "C-w s", "split-window -v"))   -- the nvim split, else the pane
row("zoom",   "z", "M-z",   "resize-pane -Z")         -- the pane, inner rung (Caps ⏎ / ⌃⏎)

-- derive the two artifacts. it's all tmux config syntax (source-filed, not shell), so the nested
-- if/braces/$TOWN survive verbatim; only keys holding % or " need quoting for the tmux parser.
local function tmux_key(k) return k:find("[%%\"]") and ("'" .. k .. "'") or k end

local binds = { "# generated by residents/translators/tmux.lua — do not edit; edit the table there.\n" }
for _, r in ipairs(rows) do binds[#binds + 1] = ("bind -n %s %s\n"):format(tmux_key(r[3]), r[4]) end
emit(HOME .. "/.config/tmux/town-transport.conf", table.concat(binds))

local cmd = {}   -- verb → dir → the tmux command
for _, r in ipairs(rows) do cmd[r[1]] = cmd[r[1]] or {}; cmd[r[1]][r[2]] = r[4] end

-- hot-reload: push the regenerated binds into the live tmux NOW, and watch tmux.conf so hand edits
-- to it reload too — the same save-to-reload DX as the residents + HS. Over the connection
-- this file holds, so there is no shell: a failure comes back as %error, not a status.
local function source(file) talk(work("source-file '" .. file .. "'", { at = "tmux" })) end
source(HOME .. "/.config/tmux/town-transport.conf")   -- the binds we just wrote


local r = react {
  -- a motion town means to make. The command runs in our client's context, and our client
  -- shadows your session, so "current pane" is the one you are looking at — no target needed.
  on({ kind = "transport", tense = "future" }, function(w)
    local b = w.body
    -- flip is the one motion town can finish itself. A vim pane gets the key; otherwise the trail
    -- is town's own and there is nothing to ask tmux for — which is what the `run-shell` in the
    -- bind below exists to do, and why a physical ⌥o still needs it. This leans on `vim` being
    -- current: it is pushed on every pane, window and session change, with the subscription behind.
    if b.verb == "flip" then
      local v = present("vim")
      if v and v.active == "1" then return work("send-keys M-" .. b.dir, { at = "tmux" }) end
      return intent("place", { step = b.dir == "o" and 1 or -1, kind = "session" })
    end
    local c = cmd[b.verb] and cmd[b.verb][b.dir]
    if c then return work(c, { at = "tmux" }) end
  end),

  on("theme", function(w)
    if not w.body.bg then return end
    -- the @color_* options the whole status bar reads (see tmux.conf), not just status-style,
    -- so every segment re-colours; then repaint.
    local c = w.body
    set("@color_bg", c.bg);         set("@color_fg", c.fg)
    set("@color_subtle", c.subtle); set("@color_active", c.active); set("@color_accent", c.accent)
    set("@color_active_bg", c.bg);  set("@color_active_fg", c.active)   -- mirror tmux.conf's derivation
    talk(tmux("refresh-client -S"))
  end),

  -- entering a session still goes through a shell: switch-client's exit code is the answer, and a
  -- line written to the connection has no answer until %begin/%end is correlated.
  on({ kind = "place", tense = "future", by = { kind = "session", name = true } }, function(w)
    return work(TX .. " switch-client -t '=" .. w.body.name .. "' 2>/dev/null",
      { about = "session", name = w.body.name })
  end),
  on({ kind = "work", tense = "past", by = { about = "session" } }, function(w)
    if w.body.code ~= 0 then return event("place", { kind = "session", name = w.body.name }) end
    return intent("place", { kind = "window", app = "WezTerm" })  -- raise the terminal too
  end),

  on("tmuxconf", function() source(HOME .. "/.config/tmux/tmux.conf") end),

  on({ kind = "tmux", tense = "past" }, function(w)
    if w.body == nil then                      -- the connection came up; say it all again
      talk(tmux(SUBSCRIBE))
      return tmux(ASK)
    end
    local line = tostring(w.body)

    -- our own answer: where you are, what occupies the pane, and what sessions exist
    local sess, occupant, list = line:match("^town|([^|]*)|([^|]*)|(.*)$")
    if sess then
      local names = {}
      for n in list:gmatch("[^,]+") do names[#names + 1] = n end
      talk(vim_is(occupant))
      talk(fact("sessions", { names = names }))
      return fact("place", { kind = "session", name = sess })
    end

    -- another client moved, so that is where you are. Follow it, or everything we ask would be
    -- about a session you are not in.
    local name = line:match("^%%client%-session%-changed %S+ %S+ (.+)$")
    if name then
      talk(tmux("switch-client -t '=" .. name .. "'"))
      return fact("place", { kind = "session", name = name })
    end

    -- anything that can change what you are looking at, or what exists: ask at once
    if line:match("^%%window%-pane%-changed") or line:match("^%%session%-window%-changed")
      or line:match("^%%session%-changed") or line:match("^%%sessions%-changed") then
      return tmux(ASK)
    end

    local value = line:match("^%%subscription%-changed vim [^:]*: (.*)$")
    if value then return vim_is(value) end
  end),
}

-- town joins tmux rather than tmux joining the square: it cannot reach us, so we reach it.
-- ignore-size so attaching never resizes what you are looking at; no-output so the pane firehose
-- stays out and only the structured notifications arrive.
r.join = { tmux = { TX, "-C", "attach", "-f", "ignore-size,no-output" } }
r.watch = { tmuxconf = HOME .. "/.config/tmux/tmux.conf" }   -- hand edits reload too
return r
