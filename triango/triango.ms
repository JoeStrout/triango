// TrianGO

import "mapUtil"
import "listUtil"
import "boardUtil"
import "bmfFonts"
import "background"

boardImg = file.loadImage("pics/triango-board.png")
stoneImg = file.loadImage("pics/go-stone.png")

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
closedTris = [0]*56
openTris = [0]*56
pieces = [0]*56

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

setTriangle = function(triList, idxA, idxB, idxC, player, updateDisplay=true)
	// Assume that idxA and idxB are on the same row,
	// and the triangle sides move towards idxC, which
	// is on a row by itself.
	posA = boardUtil.indexToColRow[idxA]
	posB = boardUtil.indexToColRow[idxB]
	posC = boardUtil.indexToColRow[idxC]	
	row = posA[1]
	colA = posA[0]
	colB = posB[0]
	endRow = posC[1]
	endCol = posC[0]
	while true
		idx = boardUtil.colRowToIndex[[colA, row]]
		for col in range(colA, colB)
			setPlayer triList, idx, player
			if updateDisplay then vis.updateCell idx
			idx += 1
		end for
		if row == endRow then break
		row += sign(endRow - row)		
		if row % 2 then
			colA += sign(endCol - colA)
		else
			colB += sign(endCol - colB)
		end if
	end while	
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

addStone = function(posIndex, player=null)
	if player == null then player = globals.player
	sp = new StoneSprite
	sp.tint = StoneSprite.tints[player]
	sp.x = boardUtil.xForIndex(posIndex)
	sp.y = boardUtil.yForIndex(posIndex)
	sprites.push sp
	pieces[posIndex] = player
end function

addTri = function(posA, posB, posC, closed=true)
	for pos in [posA, posB, posC]
		addStone pos
	end for
	if closed then
		setTriangle closedTris, posA, posB, posC, player
	else
		setTriangle openTris, posA, posB, posC, player
	end if
end function

loadVisualization = function(style)
	import "trivis-" + style
	globals.vis = locals["trivis-" + style]
end function

loadVisualization "classic"
//loadVisualization "sharp"

findTriangles = function
	for pos in range(1, 55)
		p = pieces[pos]
		if not p then continue
		// Look for triangles down (SE and SW) from here that matches p.
		posA = pos; posB = pos; closed = false
		while true
			posA = boardUtil.neighbor[posA][dir.SW]
			posB = boardUtil.neighbor[posB][dir.SE]
			if not posA or not posB then break
			if not closed then
				for p2 in range(posA, posB)
					if pieces[p2] != 0 and pieces[p2] != p then closed = true
				end for
			end if
			if pieces[posA] == p and pieces[posB] == p then
				if closed then triList = closedTris else triList = openTris
				setTriangle triList, posA, posB, pos, p
			end if
		end while
		// Now do it again, looking for upward (NE-NW) triangles.
		posA = pos; posB = pos; closed =  false
		while true
			posA = boardUtil.neighbor[posA][dir.NW]
			posB = boardUtil.neighbor[posB][dir.NE]
			if not posA or not posB then break
			if not closed then
				for p2 in range(posA, posB)
					if pieces[p2] != 0 and pieces[p2] != p then closed = true
				end for
			end if
			if pieces[posA] == p and pieces[posB] == p then
				if closed then triList = closedTris else triList = openTris
				setTriangle triList, posA, posB, pos, p
			end if
		end while		
	end for
end function

loadState = function(stateStr)
	while sprites; sprites.pop; end while
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

players = [P1, P2]
nextPlayer = function
	i = players.indexOf(player)
	i = (i + 1) % players.len
	outer.player = players[i]
	printHelp playerNames[player] + "'s turn.  Click an empty node to place a stone."	  
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
