// TrianGO

import "mapUtil"
import "listUtil"
import "textUtil"
import "bmfFonts"
import "boardUtil"
import "background"

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
display(6).mode = displayMode.pixel
triVisDisp.push display(6)
display(5).mode = displayMode.pixel
triVisDisp.push display(5)
for g in triVisDisp; g.clear color.clear; end for
display(2).mode = displayMode.pixel
boardDisp = display(2)
boardDisp.clear color.clear
boardDisp.drawImage boardImg, 
      boardUtil.midX - boardImg.width/2, boardUtil.midY - boardImg.height/2
display(1).mode = displayMode.sprite
spriteDisp = display(1)
spriteDisp.clear; sprites = spriteDisp.sprites
display(0).mode = displayMode.text
text = display(0)
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

addStone = function(posIndex, player=null)
	if player == null then player = globals.player
	sp = new StoneSprite
	sp.tint = StoneSprite.tints[player]
	sp.x = boardUtil.xForIndex(posIndex)
	sp.y = boardUtil.yForIndex(posIndex)
	sprites.push sp
	stoneAtIndex[posIndex] = sp
	pieces[posIndex] = player
end function

clearStones = function
	spriteDisp.sprites = []
	outer.sprites = spriteDisp.sprites
	stoneAtIndex = {}
end function

addTri = function(indexes, closed=true)
	for pos in indexes
		addStone pos
	end for
	if closed then
		setTriangle closedTris, indexes, player
	else
		setTriangle openTris, indexes, player
	end if
end function

loadVisualization = function(style)
	import "trivis-" + style
	globals.vis = locals["trivis-" + style]
end function

loadVisualization "classic"
//loadVisualization "sharp"

// find all triangles and load (display) them on the board
findTriangles = function(updateDisplay = true)
	for tri in boardUtil.findTriangles
		if tri.closed then triList = closedTris else triList = openTris
		setTriangle triList, tri.points, tri.player, updateDisplay
	end for
end function

loadState = function(stateStr)
	clearStones
	for pos in range(1, 55)
		pieces[pos] = stateStr[pos].val
		if pieces[pos] then addStone pos, pieces[pos]
	end for
	findTriangles
end function

//loadState "00800400000000000008008000010010400040000202000000100202"

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

// cornerPoints: list of three position indexes defining a closed triangle
captureGroup = function(cornerPoints)
	allPoints = boardUtil.allPointsInTriangle(cornerPoints)
	for pos in allPoints
		p = pieces[pos]
		// ToDo: if nonempty, add this to the player's count
		pieces[pos] = 0
		sp = stoneAtIndex.get(pos)
		if sp then sprites.removeVal sp
	end for
	oldClosed = closedTris[:]; globals.closedTris = [0]*56
	oldOpen   = openTris[:];   globals.openTris   = [0]*56
	findTriangles false
	for i in range(1, 55)
		if closedTris[i] != oldClosed[i] or openTris[i] != oldOpen[i] then
			vis.updateCell i
		end if
	end for
end function

doCapture = function
	captures = boardUtil.findTriangles(player, true)
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
			return
		end if
		// Filter out any potential captures that don't
		// include the clicked position.
		for i in range(captures.len-1, 0)
			if not captures[i].points.contains(pos) then captures.remove i
		end for
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
	captureGroup captures[0].points
	nextPlayer
end function

showTurnHelp = function
	help = playerNames[player] + "'s turn.  "
	captures = boardUtil.findTriangles(player, true)
	if captures then
		captureBtn.caption = "Capture" + "…" * (captures.len > 1)
		help += "Place stone, or click the Capture button."
		showCaptureButton
	else
		help += "Click an empty node to place a stone."	  
		hideCaptureButton
	end if
	printHelp help
end function

if not globals.hasIndex("qtyPlayers") then qtyPlayers = 2
players = [P1, P2, P3, P4][:qtyPlayers]

nextPlayer = function
	i = players.indexOf(player)
	i = (i + 1) % players.len
	outer.player = players[i]
	showTurnHelp
end function

player = players[-1]
nextPlayer

while true
	row = boardUtil.rowAtXY(mouse); col = boardUtil.colAtXY(mouse)
	idx = boardUtil.colRowToIndex.get([col,row], null)
	text.row = 25
	if idx == null then
		print " " * 25
	else
		print idx + " (" + col + "," + row + ")      "
	end if
	if mouse.button then
		if boardUtil.inBounds(col, row) and pieces[idx] == 0 then
			addStone idx
			findTriangles
			nextPlayer
		else if captureBtn.visible and captureBtn.contains(mouse) then
			if captureBtn.trackHit then doCapture
		end if
		while mouse.button; yield; end while
	end if
	if key.available then
		k = key.get
		if k == char(27) then break
		if k >= "1" and k <= "4" then player = [P1, P2, P3, P4][val(k) - 1]
		text.row = 24; print player
	end if
	yield
end while
