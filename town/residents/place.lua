-- place — the trail of where you've been; a future place by `step` walks it.
return trail("place", function(p) return (p.kind or "") .. ":" .. (p.app or p.name or "") end)
