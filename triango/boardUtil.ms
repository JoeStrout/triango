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
globals.dir = {}
dir.E = 0
dir.NE = 1
dir.NW = 2
dir.W = 3
dir.SW = 4
dir.SE = 5

// A table that maps any position to the neighboring positions.
// So for example, the neighbor to the West of position 28 is:
//		neighbor[28][dir.W]
neighbor = list.init2d(56, 6, 0)
for pos in positions
	colRow = indexToColRow[pos]; col = colRow[0]; row = colRow[1]
	if inBounds(col+1, row) then neighbor[pos][dir.E] = pos + 1
	if inBounds(col-1, row) then neighbor[pos][dir.W] = pos - 1
	if row % 2 == 0 then		// even row
		neighbor[pos][dir.NE] = colRowToIndex.get([col+1, row-1], 0)
		neighbor[pos][dir.NW] = colRowToIndex.get([col, row-1], 0)
		neighbor[pos][dir.SW] = colRowToIndex.get([col, row+1], 0)
		neighbor[pos][dir.SE] = colRowToIndex.get([col+1, row+1], 0)
	else						// odd row
		neighbor[pos][dir.NE] = colRowToIndex.get([col, row-1], 0)
		neighbor[pos][dir.NW] = colRowToIndex.get([col-1, row-1], 0)
		neighbor[pos][dir.SW] = colRowToIndex.get([col-1, row+1], 0)
		neighbor[pos][dir.SE] = colRowToIndex.get([col, row+1], 0)
	end if
	
end for

runUnitTests = function
	clear
	errorCount = 0
	assertEqual = function(actual, expected, note)
		if actual != expected then
			print "Unit test failure: expected " + expected + ", got " + actual
			outer.errorCount = errorCount + 1
		end if
	end function

	assertEqual neighbor[28][dir.E], 29
	assertEqual neighbor[28][dir.NE], 21
	assertEqual neighbor[28][dir.NW], 20
	assertEqual neighbor[28][dir.W], 27
	assertEqual neighbor[28][dir.SW], 35
	assertEqual neighbor[28][dir.SE], 36
	assertEqual neighbor[8][dir.NE], 0
	assertEqual neighbor[8][dir.NW], 3
	assertEqual neighbor[8][dir.SE], 15

	if errorCount == 0 then
		print "All tests passed.  Hooray!"
	else
		print errorCount + " error" + "s" * (errorCount!=1) + " found."
	end if
end function

if locals == globals then runUnitTests
