// TrianGO

import "mapUtil"
import "listUtil"
import "textUtil"
import "bmfFonts"
import "boardUtil"
import "background"
import "sounds"
import "bucket"
import "importUtil"
ensureImport "triangoBoard"		// geometry and triangles, as the network sees them
ensureImport "triangoGame"		// the rules (a port of the Python reference)
ensureImport "TriangoNet"		// the AlphaZero network
ensureImport "TriangoMCTS"		// search over the network

boardImg = file.loadImage("pics/triango-board.png")
stoneImg = file.loadImage("pics/go-stone.png")
stoneSelectedImg = file.loadImage("pics/stone-selected.png")

smallFont = bmfFonts.Font.load("/sys/fonts/minimicro-pro-12.bmf")

// Define player values that can be added to represent
// any combination of players.
P1 = 1
P2 = 2
P3 = 4
P4 = 8
playerNames = {P1:"Red", P2:"Blue", P3:"Green", P4:"Gray"}

// Now, define what players have a closed triangle, and who
// has an open triangle, on each of the 55 spots on the board
// (plus one for index 0, which is unused).  And also, what
// piece (0 or P1-P4) is at each space.
resetState = function
	globals.closedTris = [0]*56
	globals.openTris = [0]*56
	globals.pieces = [0]*56
end function
resetState

// Functions to manipulate those triangle lists.
setPlayer = function(triList, index, player)
	triList[index] = bitOr(triList[index], player)
end function

clearPlayer = function(triList, index, player)
	triList[index] = bitAnd(triList[index], 15-player)
end function

isSet = function(triList, index, player)
	return bitAnd(triList[index], player) > 0
end function

setTriangle = function(triList, indexes, player, updateDisplay=true)
	for idx in boardUtil.allPointsInTriangle(indexes)
		setPlayer triList, idx, player
		// Note: a point can't be both open AND closed for the same
		// player.  So if this is the closed list, clear the open one.
		if refEquals(triList, closedTris) then clearPlayer openTris, idx, player

		if updateDisplay then vis.updateCell idx
	end for
end function

// Set up the displays.
clear
background.setup

triVisDisp = []
display(6).setMode displayMode.pixel
triVisDisp.push display(6)
display(5).setMode displayMode.pixel
triVisDisp.push display(5)
for g in triVisDisp; g.clear color.clear; end for

display(4).setMode displayMode.pixel
boardDisp = display(4)
boardDisp.clear color.clear
boardDisp.drawImage boardImg,
      boardUtil.midX - boardImg.width/2, boardUtil.midY - boardImg.height/2

display(2).setMode displayMode.sprite
spriteDisp = display(2)
spriteDisp.clear; sprites = spriteDisp.sprites

display(1).setMode displayMode.text
text = display(1)
text.clear

for pos in boardUtil.positions
	x = boardUtil.xForIndex(pos)
	y = boardUtil.yForIndex(pos)
	boardDisp.print pos, x+8, y+4, color.yellow, "small"
end for

StoneSprite = new Sprite
StoneSprite.image = stoneImg
StoneSprite.tints = {}
StoneSprite.tints[P1] = "#FF4444"
StoneSprite.tints[P2] = "#8888FF"
StoneSprite.tints[P3] = "#44FF44"
StoneSprite.tints[P4] = "#CCCCCC"

stoneAtIndex = {}	// key: position index; value: StoneSprite

clearStones = function
	spriteDisp.sprites = []
	outer.sprites = spriteDisp.sprites
	outer.stoneAtIndex = {}
end function

loadVisualization = function(style)
	import "trivis-" + style
	globals.vis = locals["trivis-" + style]
end function

loadVisualization "classic"
//loadVisualization "sharp"

printHelp = function(s, textColor)
	if textColor == null then textColor = StoneSprite.tints[player]
	gfx.fillRect 0, 0, 960, 20, "#00000088"
	smallFont.printCentered s, 480, 4, 1, textColor
end function

captureBtn = new textUtil.DialogButton
captureBtn.caption = "Capture"
captureBtn.y = 25
captureBtn.x = 42

showCaptureButton = function
	text.color = StoneSprite.tints[player]
	captureBtn.draw
	captureBtn.visible = true
end function

hideCaptureButton = function
	text.row = captureBtn.y; text.column = captureBtn.x - 10
	print " "*20
	captureBtn.visible = false
end function

// Show every player's triangles, from the game state: filled hexes for full
// (capturable) triangles, outlines for empty ones.  Only the cells that
// change are redrawn.
refreshTriangles = function
	newClosed = [0]*56
	newOpen = [0]*56
	for p in players
		for t in game.tris[p]
			if triangoBoard.isFull(game.board, t, p) then triList = newClosed else triList = newOpen
			for i in t.points
				setPlayer triList, i, p
			end for
		end for
	end for
	for i in range(1, 55)
		// A point can't be both open AND closed for the same player.
		newOpen[i] = bitAnd(newOpen[i], 15 - newClosed[i])
		if newClosed[i] != closedTris[i] or newOpen[i] != openTris[i] then
			closedTris[i] = newClosed[i]
			openTris[i] = newOpen[i]
			vis.updateCell i
		end if
	end for
end function

// Play an action (see triangoBoard.ms) for the player to move, and move the
// stones on screen to match.  Returns null, or why the action is illegal.
applyAction = function(action)
	mover = game.toMove
	before = game.board[:]
	problem = game.play(action)
	if problem then return problem
	if action >= triangoBoard.CAPTURE_BASE then
		// Own stones go back to the mover's bucket; opponents' are prisoners.
		for pos in triangoBoard.actionTriangle(action).points
			if not before[pos] then continue
			if stoneAtIndex.hasIndex(pos) and stoneAtIndex[pos] then
				buckets[mover].holdStone stoneAtIndex[pos], before[pos] == mover
			end if
			stoneAtIndex.remove pos
		end for
	else
		stoneAtIndex[action] = buckets[mover].playStone(action)
	end if
	refreshTriangles
	return null
end function

// Let the human pick which full triangle to capture, by clicking corners
// until only one candidate is left.  Returns the capture action, or null if
// cancelled (by Escape, or a click that isn't on one of their stones).
chooseCapture = function
	captures = game.fullTriangles(player)
	selectionDotCount = 0
	while captures.len > 1
		printHelp "Click a corner of the triangle to capture."
		while not mouse.button and not key.pressed("escape")
			yield
		end while
		pos = 0
		if mouse.button then
			pos = boardUtil.indexAtXY(mouse)
			if pieces[pos] != player then pos = 0
			while mouse.button; yield; end while
		end if
		if pos == 0 then	// cancel
			for i in range(1, selectionDotCount, 1); sprites.pop; end for
			showTurnHelp
			return null
		end if
		// Keep only the captures with a corner at the clicked position (but
		// ignore a click that would leave none).
		remaining = []
		for t in captures
			if t.corners.indexOf(pos) != null then remaining.push t
		end for
		if not remaining then
			sounds.playBadMove
			continue
		end if
		captures = remaining
		if captures.len > 1 then
			sp = new Sprite
			sp.image = stoneSelectedImg
			sp.x = boardUtil.xForIndex(pos)
			sp.y = boardUtil.yForIndex(pos)
			sprites.push sp
			selectionDotCount += 1
		end if
	end while
	for i in range(1, selectionDotCount, 1); sprites.pop; end for
	return triangoBoard.CAPTURE_BASE + captures[0].index
end function

showTurnHelp = function
	help = playerNames[player] + "'s turn.  "
	if game.passed then
		names = []
		for p in game.passed
			names.push playerNames[p]
		end for
		help = names.join(" and ") + " can't move.  " + help
	end if
	if humanPlayers.indexOf(player) == null then
		help += "Computer is thinking..."
		hideCaptureButton
	else
		captures = game.fullTriangles(player)
		if captures then
			captureBtn.caption = "Capture" + "…" * (captures.len > 1)
			help += "Place stone, or click the Capture button."
			showCaptureButton
		else
			help += "Click an empty node to place a stone."
			hideCaptureButton
		end if
	end if
	printHelp help
end function

if not globals.hasIndex("qtyPlayers") then qtyPlayers = 2
if qtyPlayers < 2 then qtyPlayers = 2
players = [P1, P2, P3, P4][:qtyPlayers]

buckets = {}	// key: P1-P4; value: Bucket
for i in players.indexes
	p = players[i]
	buckets[p] = new Bucket
	buckets[p].player = p
	buckets[p].left = [2, 958-Bucket.width, 958-Bucket.width, 2][i]
	if qtyPlayers > 2 then
		buckets[p].bottom = [320, 320, 2, 2][i]
	else
		buckets[p].bottom = 170
	end if
	buckets[p].init
end for

// The game itself: the rules, whose turn it is, and the stones in each hand
// all live in `game` (see lib/triangoGame.ms); the displays just show it.
game = triangoGame.start(players)
pieces = game.board		// the same list, so boardUtil sees the live board
player = game.toMove

// P1 is the human; the rest are the computer, which searches with the
// AlphaZero network.  More simulations play better but think longer: 100
// takes about 2 seconds per move.
humanPlayers = [P1]
net = TriangoNet.load
if net isa error then
	print net
	print "(Without the network, the computer will play randomly.)"
else
	TriangoMCTS.net = net
	TriangoMCTS.sims = 100
end if

doHumanMove = function
	while true
		idx = boardUtil.indexAtXY(mouse)
		text.row = 25
		if idx == null then
			print " " * 25
		else
			print idx + "       " //+ " (" + col + "," + row + ")      "
		end if
		if mouse.button then
			if idx and not pieces[idx] then
				if applyAction(idx) then sounds.playBadMove else return
			else if captureBtn.visible and captureBtn.contains(mouse) then
				if captureBtn.trackHit then
					action = chooseCapture
					if action != null then
						applyAction action
						return
					end if
				end if
			end if
			while mouse.button; yield; end while
		end if
		yield
	end while
end function

// Search a little each frame, so the display stays live while it thinks.
doAIMove = function
	if net isa error then
		legal = game.legalActions
		applyAction legal[rnd * legal.len]
		return
	end if
	TriangoMCTS.begin game
	while not TriangoMCTS.step(0.05)
		yield
	end while
	applyAction TriangoMCTS.bestMove
end function

// Main loop
showTurnHelp
while not game.isOver
	if humanPlayers.indexOf(player) != null then
		doHumanMove
	else
		doAIMove
	end if
	player = game.toMove
	if not game.isOver then showTurnHelp
end while
hideCaptureButton
printHelp playerNames[game.winner] + " wins!", StoneSprite.tints[game.winner]
