-- place — the trail of where you've been, flipped through by back/forward.
return trail("place", function(p) return (p.kind or "") .. ":" .. (p.app or p.name or "") end)
