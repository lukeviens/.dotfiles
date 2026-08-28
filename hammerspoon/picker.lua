-- picker.lua — a themed webview picker, built ONCE and reused (show/hide) so opening is
-- instant: the list renders from injected data, and the icons (~250KB of data-urls) stream
-- in a tick later — the list is what you want to see first. The "gui shim" over Hammerspoon.
--
-- THE SEAM (own this call; swap what's behind it):
--   picker.show({
--     choices  = { { text=, icon=<hs.image?>, iconKey=<stable id?>, ... }, ... },
--     onSelect = function(choice) ... end,
--     onFavourite = function(choice, slot) ... end,  -- optional: normal-mode 1-9
--   })

local theme = require("theme")

-- The picker is a two-state fold: ASLEEP or AWAKE, and the only moves are wake and sleep.
-- Waking touches the window server exactly ONCE (place · show · grab key); while awake, a
-- repeat wake is a pure content delta (push a new list) — the webview keeps its place and its
-- focus. That's why spamming Caps f is free: only the first open asks the OS anything.
local M = {}
local wv, current, loaded = nil, nil, false
local awake, epoch = false, 0          -- the whole machine: are we up, and which wake is this
local grabTimer, graceUntil = nil, 0   -- the held focus-grab chain; a grace so the wake can't self-dismiss
local pending                          -- a show that arrived before the webview finished loading
local icons = {}                       -- iconKey -> data-url: encoded AND seeded into the webview, once each
local W, H = 560, 400                  -- the picker's size, named once (build + wake share it)

local HTML = [[
<!doctype html><html><head><meta charset="utf-8"><style>
:root{ --bg:%BG%; --fg:%FG%; --subtle:%SUBTLE%; --active:%ACTIVE%; --accent:%ACCENT%; }
*{ margin:0; padding:0; box-sizing:border-box; }
html,body{ background:transparent; font-family:'CaskaydiaMono Nerd Font Mono','SF Mono',monospace; }
#box{ background:var(--bg); border:1px solid var(--subtle); border-radius:14px;
      height:100vh; display:flex; flex-direction:column; overflow:hidden;
      box-shadow:0 18px 50px rgba(0,0,0,.55); }
#hdr{ display:flex; align-items:center; border-bottom:1px solid rgba(255,255,255,.07); }
#prompt{ color:var(--accent); font-size:18px; padding:0 4px 0 20px; }
#box.normal #prompt{ color:var(--active); }
#q{ flex:1; border:none; outline:none; background:transparent; color:var(--fg);
    caret-color:var(--active); font:inherit; font-size:18px; padding:17px 20px 17px 10px; }
#q.normal{ caret-color:transparent; }
#q::placeholder{ color:var(--subtle); }
#list{ flex:1; overflow-y:auto; padding:8px; }
#list::-webkit-scrollbar{ width:0; }
.row{ display:flex; align-items:center; gap:10px; padding:5px 12px; border-radius:8px;
      border-left:3px solid transparent; color:var(--fg); font-size:12.5px; white-space:nowrap; }
.row .ic{ width:16px; height:16px; flex:none; }
.row.sel{ background:rgba(255,255,255,.06); border-left-color:var(--active); }
.row.sel .name{ font-weight:600; }
.name{ overflow:hidden; text-overflow:ellipsis; }
.empty{ color:var(--subtle); padding:16px; font-size:13px; }
#foot{ display:flex; align-items:center; gap:12px; padding:8px 14px;
       border-top:1px solid rgba(255,255,255,.07); font-size:11px; }
.mode{ letter-spacing:.12em; font-weight:700; padding:3px 7px; border-radius:5px; color:var(--bg); }
.mode.insert{ background:var(--accent); }
.mode.normal{ background:var(--active); }
.hint{ flex:1; color:var(--subtle); }
.count{ color:var(--subtle); }
</style></head><body>
<div id="box">
  <div id="hdr"><span id="prompt">❯</span><input id="q" placeholder="go" autofocus spellcheck="false"></div>
  <div id="list"></div>
  <div id="foot">
    <span id="mode" class="mode insert">INSERT</span>
    <span id="hint" class="hint"></span>
    <span id="count" class="count"></span>
  </div>
</div>
<script>
let CH = [], ICONS = {}, FAVABLE = false, HINT = '';   // data is injected by load()/icons()
let items = [], sel = 0, mode = 'insert', lastG = 0, flashT;
const post = m => window.webkit.messageHandlers.picker.postMessage(m);
const q=document.getElementById('q'), badge=document.getElementById('mode'),
      box=document.getElementById('box'), hint=document.getElementById('hint'),
      count=document.getElementById('count');

function score(q, s){                       // fuzzy: subsequence, earlier+tighter wins
  q=q.toLowerCase(); s=s.toLowerCase();
  if(!q) return 0;
  let i=0,j=0,first=-1,gaps=0;
  while(i<q.length && j<s.length){
    if(q[i]===s[j]){ if(first<0)first=j; i++; } else if(first>=0){ gaps++; }
    j++;
  }
  if(i<q.length) return -1;
  return 1000 - first*3 - gaps;
}
function render(){                          // DOM + textContent — never innerHTML (injection-safe)
  const l=document.getElementById('list'); l.textContent='';
  if(!items.length){
    const e=document.createElement('div'); e.className='empty'; e.textContent='no matches';
    l.appendChild(e); return;
  }
  items.forEach((it,idx)=>{
    const r=document.createElement('div');
    r.className='row'+(idx===sel?' sel':'');
    const url = ICONS[it.ik];               // by iconKey — ICONS persists across opens (seeded once)
    if(url){ const im=document.createElement('img'); im.className='ic'; im.src=url; r.appendChild(im); }
    else   { const sp=document.createElement('span'); sp.className='ic'; r.appendChild(sp); }
    const nm=document.createElement('span'); nm.className='name'; nm.textContent=it.text;
    r.appendChild(nm);
    r.onclick=()=>{ sel=idx; choose(); };
    l.appendChild(r);
  });
  const s=l.children[sel]; if(s) s.scrollIntoView({block:'nearest'});
}
function filter(query){
  items = CH.map(c=>({c,sc:score(query,c.text)}))
            .filter(x=>x.sc>=0)
            .sort((a,b)=> b.sc-a.sc || a.c.text.localeCompare(b.c.text))
            .map(x=>x.c);
  sel=0; render(); count.textContent = items.length+'/'+CH.length;
}
function choose(){ if(items[sel]) post({action:'select', idx:items[sel]._i}); }  // _i = original Lua index
function move(d){ sel=Math.max(0,Math.min(sel+d,items.length-1)); render(); }
function setMode(m){
  mode=m;
  badge.textContent = m==='insert' ? 'INSERT' : 'NORMAL';
  badge.className = 'mode '+m;
  q.classList.toggle('normal', m==='normal');
  box.classList.toggle('normal', m==='normal');
}
function flash(t){ hint.textContent=t; clearTimeout(flashT); flashT=setTimeout(()=>hint.textContent=HINT, 1200); }

// ── the two entry points HS calls: load() draws the list now, icons() fills them in ──
function load(choices, favable){
  CH = choices; FAVABLE = !!favable; sel = 0;   // ICONS is NOT reset — it persists across opens
  HINT = FAVABLE ? '↵ open · esc back · 1-9 favourite' : '↵ open · esc back · j/k move';
  hint.textContent = HINT;
  q.value=''; setMode('insert'); filter(''); q.focus();
}
function seedIcons(map){ Object.assign(ICONS, map); render(); }
function setTheme(t){ const r=document.documentElement.style; for(const k in t) r.setProperty('--'+k, t[k]); }

q.addEventListener('input', e=>{ if(mode==='insert') filter(e.target.value); });
document.addEventListener('keydown', e=>{
  // universal — work in either mode
  if(e.ctrlKey&&e.key==='c'){ post({action:'cancel'}); e.preventDefault(); return; }
  if(e.key==='Enter'){ choose(); e.preventDefault(); return; }
  if(e.key==='ArrowDown'||(e.ctrlKey&&e.key==='n')){ move(1); e.preventDefault(); return; }
  if(e.key==='ArrowUp'||(e.ctrlKey&&e.key==='p')){ move(-1); e.preventDefault(); return; }

  if(mode==='insert'){
    if(e.key==='Escape'){ setMode('normal'); e.preventDefault(); }
    return;                                    // otherwise: type → filters
  }

  // ── normal mode — nothing types ──
  e.preventDefault();
  if(e.key==='Escape'||e.key==='q'){ post({action:'cancel'}); }
  else if(e.key==='j'){ move(1); }
  else if(e.key==='k'){ move(-1); }
  else if(e.key==='i'||e.key==='/'){ setMode('insert'); }
  else if(e.key==='G'){ sel=items.length-1; render(); }
  else if(e.key==='g'){ const n=Date.now(); if(n-lastG<400){ sel=0; render(); } lastG=n; }
  else if(FAVABLE && /^[1-9]$/.test(e.key) && items[sel]){
    post({action:'favourite', slot:+e.key, idx:items[sel]._i}); flash('favourited → '+e.key);
  }
});
</script></body></html>
]]

-- build the reused webview once (hidden). Its usercontent callback reads the LIVE opts.
local function build()
  local ucc = hs.webview.usercontent.new("picker")
  ucc:setCallback(function(msg)
    local body, opts = msg.body or {}, current or {}
    if body.action == "favourite" and opts.onFavourite and body.idx and body.slot then
      local c = opts.choices and opts.choices[body.idx]
      if c then pcall(opts.onFavourite, c, body.slot) end
      return                                     -- favouriting keeps the picker open
    end
    M.hide()
    if body.action == "select" and body.idx then
      local c = opts.choices and opts.choices[body.idx]
      if c and opts.onSelect then
        local ok, err = pcall(opts.onSelect, c)  -- a dead window / bad backend can't spew
        if not ok then hs.printf("picker onSelect error: %s", tostring(err)) end
      end
    end
  end)
  local html = HTML
    :gsub("%%BG%%", theme.bg):gsub("%%FG%%", theme.fg):gsub("%%SUBTLE%%", theme.subtle)
    :gsub("%%ACTIVE%%", theme.active):gsub("%%ACCENT%%", theme.accent)
  wv = hs.webview.new({ x = 0, y = 0, w = W, h = H }, { developerExtrasEnabled = false }, ucc)
  wv:windowStyle({ "borderless" })
  wv:transparent(true)
  wv:allowTextEntry(true)
  wv:level(hs.canvas.windowLevels.modalPanel)
  wv:navigationCallback(function(action)             -- the HTML finished loading — flush a waiting show
    if action == "didFinishNavigation" then loaded = true
      if pending then local o = pending; pending = nil; M.show(o) end
    end
  end)
  wv:windowCallback(function(action, _, hasFocus)    -- click-away: sleep once it loses focus,
    if action == "focusChange" and awake and not hasFocus  -- but not during the wake's grace window
       and hs.timer.secondsSinceEpoch() > graceUntil then M.hide() end
  end)
  wv:html(html)   -- loaded ONCE; opens after this just inject data
end

function M.build() if not wv then build() end end   -- pre-create at boot so the first open is warm

-- recolour the live webview when the palette changes (Caps t): just re-set the CSS vars —
-- no rebuild, no lost icons or state. Works while hidden too (ready for the next open).
function M.theme(palette)
  if wv and loaded then wv:evaluateJavaScript("setTheme(" .. hs.json.encode(palette) .. ")", function() end) end
end

local function newEpoch()   -- bump the wake generation and void any in-flight key-grab
  epoch = epoch + 1
  if grabTimer then grabTimer:stop(); grabTimer = nil end
  return epoch
end

function M.hide()   -- sleep: yield the keyboard and void any in-flight grab
  newEpoch()
  if wv then wv:hide() end
  awake = false; current = nil
end

-- encode an icon to a 36×36 data-url exactly once, caching it in `icons`; returns the new url or nil.
local function encodeIcon(c)
  if c.icon and c.iconKey and not icons[c.iconKey] then
    local url = c.icon:setSize({ w = 36, h = 36 }):encodeAsURLString() or ""
    if url ~= "" then icons[c.iconKey] = url; return url end
  end
end

-- push a list into the webview: seed any icons it hasn't seen, then draw. All async JS, so
-- it never blocks the main thread — this IS the whole cost of a repeat wake.
local function push(opts)
  local rows, newmap, anyNew = {}, {}, false
  for i, c in ipairs(opts.choices or {}) do
    rows[i] = { text = c.text, _i = i, ik = c.iconKey }
    local url = encodeIcon(c)
    if url then newmap[c.iconKey] = url; anyNew = true end
  end
  if anyNew then wv:evaluateJavaScript("seedIcons(" .. hs.json.encode(newmap) .. ")", function() end) end
  wv:evaluateJavaScript("load(" .. hs.json.encode(rows) .. ", " .. tostring(opts.onFavourite ~= nil) .. ")", function() end)
end

-- grab the keyboard for the webview: the ONE window-server fight. Async so it never blocks,
-- retried a few times (a reused webview doesn't always take key at once), and abandoned the
-- instant a newer wake or a sleep bumps `epoch`. Contained entirely to the wake edge.
local function grabKey(mine, n)
  if epoch ~= mine then return end
  grabTimer = nil
  local win = wv and wv:hswindow()
  if win then
    win:focus()
    wv:evaluateJavaScript(
      "(function(){var q=document.getElementById('q');if(q)q.focus();return document.activeElement===q})()",
      function(ok)
        if epoch ~= mine or ok == true then return end   -- superseded, or the field is key → done
        if n > 0 then grabTimer = hs.timer.doAfter(0.04, function() grabKey(mine, n - 1) end) end
      end)
  elseif n > 0 then
    grabTimer = hs.timer.doAfter(0.04, function() grabKey(mine, n - 1) end)
  end
end

-- wake onto `opts`. ASLEEP → the window dance, exactly once (place · push · show · grab key).
-- AWAKE → just push the new list; nothing touches the window server. This split is the fix.
local function wake(opts)
  newEpoch()
  current = opts
  if awake then push(opts); return end             -- already up — a pure content delta, done

  local scr = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()  -- mouse screen: no AX
  local f   = scr:frame()
  wv:frame({ x = f.x + (f.w - W) / 2, y = f.y + (f.h - H) * 0.28, w = W, h = H })
  push(opts)
  wv:show(); wv:bringToFront(true)
  awake = true
  graceUntil = hs.timer.secondsSinceEpoch() + 0.30 -- don't let the focus-fight click-away us
  grabKey(epoch, 4)
end

function M.show(opts)
  if not wv then build() end
  if loaded then wake(opts) else pending = opts end   -- before the HTML loads, wait; flushed on load
end

-- Pre-encode icons into the cache, a few per tick (non-blocking), so even the first open's
-- icon stream is instant. Call at idle after boot with the app list ({ text, icon, iconKey }).
local warmTimer   -- held, or HS garbage-collects the chained timer and the warm-up stalls
function M.prewarm(items)
  local i = 0
  local function chunk()
    local batch, done = {}, 0
    while i < #items and done < 12 do
      i = i + 1; done = done + 1
      local it = items[i]
      local url = encodeIcon(it)
      if url then batch[it.iconKey] = url end
    end
    if wv and next(batch) then wv:evaluateJavaScript("seedIcons(" .. hs.json.encode(batch) .. ")") end
    if i < #items then warmTimer = hs.timer.doAfter(0.03, chunk) end
  end
  chunk()
end

return M
