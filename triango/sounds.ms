
blip = file.loadSound("/sys/sounds/blipA4.wav")

playBadMove = function
	blip.play 1, 0, 0.125
	wait 0.2
	blip.stop
end function