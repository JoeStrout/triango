

setup = function
	display(7).mode = displayMode.pixel
	outer.gfx = display(7)

	colors = ["#FFFFFF", "#AAAAFF", "#FFFFAA", "#FFCCCC"]
	gfx.clear
	for i in range(1000)
		gfx.setPixel rnd*960, rnd*640, colors[rnd * colors.len]
	end for
end function

if locals == globals then
	clear
	setup
end if

