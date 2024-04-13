// Classic triangle visualization style:
// Filled hexagons for capturing (closed) triangles,
// hex outlines for open triangles.

import "importUtil"
ensureImport "mathUtil"
ensureImport "listUtil"
ensureImport "boardUtil"

// Define a color for every combination of the 4 players:
// player 1 is worth 2^0, player2 worth 2^1, etc.
tintColors = ["#FF00FF"]*16
mix = function(colors)
	reds = []; greens = []; blues = []
	for c in colors
		rgb = color.toList(c)
		reds.push rgb[0]; greens.push rgb[1]; blues.push rgb[2]
	end for
	r = reds.sum
	g = greens.sum
	b = blues.sum
	return color.rgba(r, g, b, 150)
end function
tintColors[0] = color.clear
for i in range(1, 15)
	colors = []
	for p in [P1, P2, P3, P4]
		if bitAnd(p, i) then colors.push StoneSprite.tints[p]
	end for
	tintColors[i] = mix(colors)
end for

drawHex = function(disp, col, row, playerMask, closed)
	x = boardUtil.xForColRow(col, row)
	y = boardUtil.yForColRow(col, row)
	r = ceil(sqrt(3)/3 * boardUtil.xSpacing)
	pts = []
	ang = 60 * pi/180
	for i in range(0.5, 5.5)
		pts.push [round(x + r * cos(ang*i)), round(y + r * sin(ang*i))]
	end for
	color = tintColors[playerMask]
	if closed then
		disp.fillPoly pts, color
	else
		pts = mathUtil.offsetPoly(pts, -3)
		disp.drawPoly pts, color, 5
	end if
end function

updateCell = function(posIndex)
	colRow = boardUtil.indexToColRow[posIndex]
	drawHex triVisDisp[0], colRow[0], colRow[1], closedTris[posIndex], true
	drawHex triVisDisp[1], colRow[0], colRow[1], openTris[posIndex], false	
end function

//drawTri = function(posA, posB, posC, closed)
//	c = tintColors[player][:7] + "77"
//	g = triVisDisp[player]
//	// Assume that posA and posB are on the same row,
//	// and the triangle sides move towards posC, which
//	// is on a row by itself.
//	row = posA[1]
//	colA = posA[0]
//	colB = posB[0]
//	endRow = posC[1]
//	endCol = posC[0]
//	while true
//		for col in range(colA, colB)
//			drawHex g, col, row, c, closed
//		end for
//		if row == endRow then break
//		row += sign(endRow - row)		
//		if row % 2 then
//			colA += sign(endCol - colA)
//		else
//			colB += sign(endCol - colB)
//		end if
//	end while
//end function
//
//drawClosedTri = function(posA, posB, posC)
//	drawTri posA, posB, posC, true
//end function
//
//drawOpenTri = function(posA, posB, posC)
//	drawTri posA, posB, posC, false
//end function
