local gruvbox = {
    fg = '#928374',
    bg = '#1F2542',
    black ='#1B1B1B',
    skyblue = '#458588',
    cyan = '#83a597',
    green = '#689d6a',
    oceanblue = '#1d2021',
    magenta = '#fb4934',
    orange = '#fabd2f',
    red = '#cc241d',
    violet = '#b16286',
    white = '#ebdbb2',
    yellow = '#d79921',
}

return {
	"famiu/feline.nvim",
	config = function()
		require('feline').setup({
			theme = gruvbox
		})
		require('feline').winbar.setup()
	end
}
