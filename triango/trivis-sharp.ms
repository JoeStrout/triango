// Sharp triangle visualization style:
// Draws a triangle (possibly outset by some amount from the grid lines).

import "mathUtil"

tintColors = ["#FF2222", "#4444FF", "#00CC00", "#CCCCCC"]

outset = 20

drawClosedTri = function(posA, posB, posC)
	c = tintColors[player][:7] + "77"
	g = triVisDisp[player]
	g.color = c
	
	pts = []
	for pos in [posA, posB, posC]
		pts.push [xForColRow(pos[0], pos[1]), yForColRow(pos[0], pos[1])]
	end for
	pts = mathUtil.offsetPoly(pts, outset * sign(posA[1]-posC[1]))
	
	g.fillPoly pts
	
	// ..and in fact if we're manually mixing, we probably can't use that
	// at all.  Can we go pixel by pixel?
//	endX = pts[2][0]
//	for y in range(pts[0][1], pts[2][1])
//		for x in range(pts[0][0], pts[1][0])
//			g.setPixel x, y, c
//		end for
//		pts[0][0] += sign(endX - pts[0][0])
//		pts[1][0] += sign(endX - pts[1][0])
//	end for
	
end function

drawOpenTri = function(posA, posB, posC)
	c = tintColors[player][:7] + "77"
	g = triVisDisp[player]
	g.color = c
	
	pts = []
	for pos in [posA, posB, posC]
		pts.push [xForColRow(pos[0], pos[1]), yForColRow(pos[0], pos[1])]
	end for
	
	sgn = sign(posA[1]-posC[1])
	offset = outset - 4
	pts = mathUtil.offsetPoly(pts, offset * sgn)
	g.drawPoly pts, c, 4
	offset = -5
	pts = mathUtil.offsetPoly(pts, offset * sgn)
	g.drawPoly pts, c, 2
	offset = -3
	pts = mathUtil.offsetPoly(pts, offset * sgn)
	g.drawPoly pts, c, 1
	
	
	
	// ..and in fact if we're manually mixing, we probably can't use that
	// at all.  Can we go pixel by pixel?
//	endX = pts[2][0]
//	for y in range(pts[0][1], pts[2][1])
//		for x in range(pts[0][0], pts[1][0])
//			g.setPixel x, y, c
//		end for
//		pts[0][0] += sign(endX - pts[0][0])
//		pts[1][0] += sign(endX - pts[1][0])
//	end for
	
end function
