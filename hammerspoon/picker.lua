-- picker.lua — a fully-themed overlay picker rendered in an hs.webview.
-- hs.chooser's chrome (search field, bg, fonts) isn't ours to style; a webview
-- IS — it's just HTML/CSS. So this is the "gui shim" over Hammerspoon.
--
-- THE SEAM (own this call; swap what's behind it):
--   picker.show({
--     placeholder = "apps",
--     choices  = { { text=, icon=<hs.image?>, iconKey=<stable id?>, ... }, ... },
--     onSelect = function(choice) ... end,       -- Enter / click
--     onFavourite = function(choice, slot) ... end,  -- optional: normal-mode 1-9
--   })
-- The view is HTML today. Later: swap the data source or the entire view.

local theme = require("theme")

local M = {}
local close_current     -- closes the open picker; also anchors it from Lua GC
local iconcache = {}    -- iconKey -> data-url, so each distinct icon encodes once, ever

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
.row{ display:flex; align-items:center; gap:12px; padding:9px 14px; border-radius:9px;
      border-left:3px solid transparent; color:var(--fg); font-size:14px; white-space:nowrap; }
.row .ic{ width:18px; height:18px; flex:none; }
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
</style>%DATA%</head><body>
<div id="box">
  <div id="hdr"><span id="prompt">❯</span><input id="q" placeholder="%PH%" autofocus spellcheck="false"></div>
  <div id="list"></div>
  <div id="foot">
    <span id="mode" class="mode insert">INSERT</span>
    <span id="hint" class="hint"></span>
    <span id="count" class="count"></span>
  </div>
</div>
<script>
const CH = window.CHOICES || [], FAVABLE = !!window.FAVABLE;
const post = m => window.webkit.messageHandlers.picker.postMessage(m);
let items = [], sel = 0;

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
    if(it.icon){ const im=document.createElement('img'); im.className='ic'; im.src=it.icon; r.appendChild(im); }
    else       { const sp=document.createElement('span'); sp.className='ic'; r.appendChild(sp); }
    const nm=document.createElement('span'); nm.className='name'; nm.textContent=it.text;
    r.appendChild(nm);
    r.onclick=()=>{ sel=idx; choose(); };
    l.appendChild(r);
  });
  const s=l.children[sel]; if(s) s.scrollIntoView({block:'nearest'});
}
function filter(q){
  items = CH.map(c=>({c,sc:score(q,c.text)}))
            .filter(x=>x.sc>=0)
            .sort((a,b)=> b.sc-a.sc || a.c.text.localeCompare(b.c.text))
            .map(x=>x.c);
  sel=0; render(); count.textContent = items.length+'/'+CH.length;
}
function choose(){ if(items[sel]) post({action:'select', idx:items[sel]._i}); }  // _i = original Lua index

const q=document.getElementById('q'), badge=document.getElementById('mode'),
      box=document.getElementById('box'), hint=document.getElementById('hint'),
      count=document.getElementById('count');
const HINT = FAVABLE ? '↵ open · esc back · 1-9 favourite' : '↵ open · esc back · j/k move';
hint.textContent = HINT;
let flashT;
function flash(t){ hint.textContent=t; clearTimeout(flashT); flashT=setTimeout(()=>hint.textContent=HINT, 1200); }

let mode='insert', lastG=0;
function move(d){ sel=Math.max(0,Math.min(sel+d,items.length-1)); render(); }
function setMode(m){
  mode=m;
  badge.textContent = m==='insert' ? 'INSERT' : 'NORMAL';
  badge.className = 'mode '+m;
  q.classList.toggle('normal', m==='normal');
  box.classList.toggle('normal', m==='normal');
}
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
filter(''); setMode('insert'); q.focus();
</script></body></html>
]]

function M.show(opts)
  local choices  = opts.choices or {}
  local onSelect = opts.onSelect or function() end
  local onFav    = opts.onFavourite
  local ph       = opts.placeholder or "search"
  if close_current then close_current() end   -- only one picker at a time

  -- data → JS, embedded in the HTML head so there's no page-load timing race.
  local js = {}
  for i, c in ipairs(choices) do
    local url = ""
    if c.icon then
      local key = c.iconKey or c.text          -- stable icon identity; text is the fallback
      url = iconcache[key]
      if not url then
        url = c.icon:setSize({ w = 36, h = 36 }):encodeAsURLString() or ""
        iconcache[key] = url
      end
    end
    js[i] = { text = c.text, icon = url, _i = i }
  end
  local data = "<script>window.CHOICES=" .. hs.json.encode(js)
            .. ";window.FAVABLE=" .. tostring(onFav ~= nil) .. ";</script>"

  local html = HTML
    :gsub("%%BG%%", theme.bg):gsub("%%FG%%", theme.fg):gsub("%%SUBTLE%%", theme.subtle)
    :gsub("%%ACTIVE%%", theme.active):gsub("%%ACCENT%%", theme.accent)
    :gsub("%%PH%%", function() return ph end)
    :gsub("%%DATA%%", function() return data end)

  -- open on the screen you're actually working on (multi-monitor)
  local fw  = hs.window.focusedWindow()
  local scr = (fw and fw:screen()) or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f   = scr:frame()
  local w, h = 560, 400
  local rect = { x = f.x + (f.w - w) / 2, y = f.y + (f.h - h) * 0.28, w = w, h = h }

  local wv
  local closed = false
  local function close()
    if closed then return end
    closed = true
    if wv then pcall(function() wv:delete() end) end   -- idempotent even if already gone
    wv = nil
  end

  local ucc = hs.webview.usercontent.new("picker")
  ucc:setCallback(function(msg)
    local body = msg.body or {}
    if body.action == "favourite" and onFav and body.idx and body.slot then
      local c = choices[body.idx]
      if c then pcall(onFav, c, body.slot) end
      return                                     -- favouriting keeps the picker open
    end
    close()
    if body.action == "select" and body.idx then
      local c = choices[body.idx]
      if c then
        local ok, err = pcall(onSelect, c)       -- a dead window / bad backend can't spew
        if not ok then hs.printf("picker onSelect error: %s", tostring(err)) end
      end
    end
  end)

  wv = hs.webview.new(rect, { developerExtrasEnabled = false }, ucc)
  wv:windowStyle({ "borderless" })
  wv:transparent(true)
  wv:allowTextEntry(true)                      -- lets the search field actually type
  wv:level(hs.canvas.windowLevels.modalPanel)

  -- dismiss on click-away: close once it loses focus (after a grace period so the
  -- initial focus grab doesn't self-close).
  local armed = false
  wv:windowCallback(function(action, _, hasFocus)
    if action == "focusChange" and armed and hasFocus == false then close() end
  end)

  wv:html(html)
  wv:bringToFront(true)
  wv:show()
  close_current = close                         -- anchors wv from GC; next show() closes this one
  hs.timer.doAfter(0.05, function()             -- force keyboard focus into the field
    if wv and wv:hswindow() then wv:hswindow():focus() end
  end)
  hs.timer.doAfter(0.30, function() armed = true end)
end

return M
