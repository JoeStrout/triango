// Utility functions for dealing with Triango's weird board.

import "importUtil"
ensureImport "listUtil"

// Maps between row/column and position index.
colRowToIndex = {}	// key: [col,row]; value: postion index 1-55
indexToColRow = {}	// key: position index 1-55; value: [col,row]

// Board position and spacing on screen, in pixels
midX = 480; midY = 320
xSpacing = 37*2; ySpacing = 32*2

// All position indexes
positions = range(1, 55)

// Conversion to/from screen locations
yForColRow = function(col, row)
	return midY + (4-row) * ySpacing
end function

rowAtXY = function(xyMap)
	return round((midY - xyMap.y) / ySpacing + 4)
end function

xForColRow = function(col, row)
	return midX + (col - 3 - 0.5*(row%2)) * xSpacing
end function

colAtXY = function(xyMap)
	row = rowAtXY(xyMap)
	return round((xyMap.x - midX) / xSpacing + 3 + 0.5*(row%2))
end function

yForIndex = function(idx)
	colRow = indexToColRow[idx]
	return midY + (4-colRow[1]) * ySpacing
end function

xForIndex = function(idx)
	colRow = indexToColRow[idx]
	return midX + (colRow[0] - 3 - 0.5 * (colRow[1] % 2)) * xSpacing
end function

indexAtXY = function(xyMap)
	col = colAtXY(xyMap)
	row = rowAtXY(xyMap)
	return colRowToIndex.get([col, row], 0)
end function

// List providing the column range for each row.
rowColRange = [
	range(2,4),
	range(1,6),
	range(0,6),
	range(0,7),
	range(0,6),
	range(0,7),
	range(0,6),
	range(1,6),
	range(2,4),
]

inBounds = function(col, row)
	if row < 0 or row >= rowColRange.len then return false
	r = rowColRange[row]
	return r[0] <= col <= r[-1]
end function

i = 0
for row in range(0, 8)
	for col in range(0, 7)
		if not inBounds(col, row) then continue
		i += 1
		colRowToIndex[[col,row]] = i
		indexToColRow[i] = [col,row]
	end for
end for

// Directions from one point on the board towards neighboring points.
globals.dirs = {}
dirs.E = 0
dirs.NE = 1
dirs.NW = 2
dirs.W = 3
dirs.SW = 4
dirs.SE = 5

// A table that maps any position to the neighboring positions.
// So for example, the neighbor to the West of position 28 is:
//		neighbor[28][dirs.W]
neighbor = list.init2d(56, 6, 0)
for pos in positions
	colRow = indexToColRow[pos]; col = colRow[0]; row = colRow[1]
	if inBounds(col+1, row) then neighbor[pos][dirs.E] = pos + 1
	if inBounds(col-1, row) then neighbor[pos][dirs.W] = pos - 1
	if row % 2 == 0 then		// even row
		neighbor[pos][dirs.NE] = colRowToIndex.get([col+1, row-1], 0)
		neighbor[pos][dirs.NW] = colRowToIndex.get([col, row-1], 0)
		neighbor[pos][dirs.SW] = colRowToIndex.get([col, row+1], 0)
		neighbor[pos][dirs.SE] = colRowToIndex.get([col+1, row+1], 0)
	else						// odd row
		neighbor[pos][dirs.NE] = colRowToIndex.get([col, row-1], 0)
		neighbor[pos][dirs.NW] = colRowToIndex.get([col-1, row-1], 0)
		neighbor[pos][dirs.SW] = colRowToIndex.get([col-1, row+1], 0)
		neighbor[pos][dirs.SE] = colRowToIndex.get([col, row+1], 0)
	end if
end for

// Return all the position indexes in the given triangle.
// points: list of position indexes, in order left, right, middle
allPointsInTriangle = function(points)
	posA = points[0]; posB = points[1]; posC = points[2]
	if indexToColRow[points[0]][1] < indexToColRow[posC][1] then
		dirLeft = dirs.NW
		dirRight = dirs.NE
	else
		dirLeft = dirs.SW
		dirRight = dirs.SE
	end if
	result = [posC]
	posA = posC; posB = posC
	while true
		posA = boardUtil.neighbor[posA][dirLeft]
		posB = boardUtil.neighbor[posB][dirRight]
		result += range(posA, posB)
		if posA == points[0] then break
	end while
	return result
end function

// Return a list of triangles for one player, or all players.
// Each entry in the list is a little map with:
//		player: P1, P2, P3, or P4
//		closed: true or false
//		points: list of position indexes, in order left, right, middle
findTriangles = function(player=null, closedOnly=false)
	result = []
	for pos in range(1, 55)
		p = pieces[pos]
		if not p then continue
		if player and p != player then continue
		// Look for triangles down (SE and SW) from here that matches p.
		posA = pos; posB = pos; closed = false
		while true
			posA = boardUtil.neighbor[posA][dirs.SW]
			posB = boardUtil.neighbor[posB][dirs.SE]
			if not posA or not posB then break
			if not closed then
				for p2 in range(posA, posB)
					if pieces[p2] != 0 and pieces[p2] != p then closed = true
				end for
			end if
			if pieces[posA] == p and pieces[posB] == p and (closed or not closedOnly) then
				result.push {"player":p, "closed":closed, 
				  "points": [posA, posB, pos]}
			end if
		end while
		// Now do it again, looking for upward (NE-NW) triangles.
		posA = pos; posB = pos; closed =  false
		while true
			posA = boardUtil.neighbor[posA][dirs.NW]
			posB = boardUtil.neighbor[posB][dirs.NE]
			if not posA or not posB then break
			if not closed then
				for p2 in range(posA, posB)
					if pieces[p2] != 0 and pieces[p2] != p then closed = true
				end for
			end if
			if pieces[posA] == p and pieces[posB] == p and (closed or not closedOnly) then
				result.push {"player":p, "closed":closed, 
				  "points": [posA, posB, pos]}
			end if
		end while		
	end for
	return result
end function

runUnitTests = function
	clear
	errorCount = 0
	assertEqual = function(actual, expected, note)
		if actual != expected then
			print "Unit test failure: expected " + expected + ", got " + actual
			outer.errorCount = errorCount + 1
		end if
	end function

	assertEqual neighbor[28][dirs.E], 29
	assertEqual neighbor[28][dirs.NE], 21
	assertEqual neighbor[28][dirs.NW], 20
	assertEqual neighbor[28][dirs.W], 27
	assertEqual neighbor[28][dirs.SW], 35
	assertEqual neighbor[28][dirs.SE], 36
	assertEqual neighbor[8][dirs.NE], 0
	assertEqual neighbor[8][dirs.NW], 3
	assertEqual neighbor[8][dirs.SE], 15

	if errorCount == 0 then
		print "All tests passed.  Hooray!"
	else
		print errorCount + " error" + "s" * (errorCount!=1) + " found."
	end if
end function

if locals == globals then runUnitTests
