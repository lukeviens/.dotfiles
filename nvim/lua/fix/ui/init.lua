-- The interface fix/init.lua talks to, nothing more:
--   is_open() -> bool
--   close()
--   open(bufnr, labels, on_accept) -- labels: string[]; on_accept(index), called once, after close
--
-- popup.lua is today's (only) implementation — a cursor-anchored floating menu. A future shape
-- (e.g. a whole-buffer list for reviewing many fixes at once) would live alongside it here as
-- its own file; this module is what picks which one answers to fix/init.lua.
return require("fix.ui.popup")
