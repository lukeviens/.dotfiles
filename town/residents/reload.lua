-- reload — town reloading itself. Watch the residents directory; on any save,
-- reopen them all. The only core help it needs is `reopen`; the rest is a resident.
return {
  watch  = { changed = os.getenv("HOME") .. "/.config/town/residents" },
  listen = { "changed" },
  talk   = function() reopen() end,
}
