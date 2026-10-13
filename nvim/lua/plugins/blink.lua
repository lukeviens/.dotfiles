-- blink.cmp: the menu, shown automatically like any normal completion UI — just never the
-- ghost text, that's zeta's job (plugins/zeta.lua). Tab defaults to zeta regardless of whether
-- the menu happens to be open; it only takes Tab back once you've explicitly selected something
-- in it (<M-j>/<M-k>/<Down>/<Up>) — that's what preselect=false buys: no selection exists until
-- you navigate, so get_selected_item_idx() is a clean "did they reach into the menu" check.
-- Enter always means newline, never a hijacked accept.
return {
	"saghen/blink.cmp",
	version = "1.*",
	dependencies = { "rafamadriz/friendly-snippets" },
	opts = {
		keymap = {
			preset = "super-tab",
			["<Tab>"] = {
				function(cmp)
					-- nothing explicitly selected in the menu yet — zeta gets first refusal.
					-- accept() itself no-ops (returns false) when it has nothing to offer either.
					if cmp.get_selected_item_idx() == nil and require("cursortab").accept() then return true end
				end,
				function(cmp)
					if cmp.snippet_active() then
						return cmp.accept()
					else
						return cmp.select_and_accept()
					end
				end,
				"snippet_forward",
				"fallback",
			},
			["<M-j>"] = { "select_next", "fallback" },
			["<M-k>"] = { "select_prev", "fallback" },
		},
		completion = {
			documentation = { auto_show = true },
			-- zeta is the ghost text now (plugins/zeta.lua); blink shows none of its own.
			ghost_text = { enabled = false },
			list = { selection = { preselect = false } },
			-- dot_repeat fakes an Insert-mode complete() call unconditionally — crashes (E785)
			-- on any accept/preview triggered from Normal mode. Cheap insurance to leave off.
			accept = { dot_repeat = false },
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
	},
	opts_extend = { "sources.default" },
}
