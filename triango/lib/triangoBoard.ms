// triangoBoard.ms
//
// TrianGO board geometry and position queries, matching the Python reference
// (triango/python, copied into ML-work-2026/rl_triango): point numbering, the
// six perimeters, and the 136 triangles in the order that defines the neural
// network's capture actions.  This is only what TriangoNet needs to encode a
// position and interpret its output; it is not a full rules engine (there is
// no move application here).
//
// A position is described by a small map, independent of how the game code
// represents players:
//
//     board     list of 56; board[i] is the player at point i, or 0
//               (board[0] is unused)
//     hand      map (or list) indexed by player: stones in hand
//     players   the players in the game, in turn order
//     toMove    the player to move
//
// Players may be any nonzero numbers (1-4, or bit flags like P1-P4 in
// triango.ms).
//
// Actions, as the network numbers them: 1-55 place a stone on that point;
// CAPTURE_BASE + k captures triangles[k].  Action 0 is unused.

NUM_POINTS = 55
NUM_ROWS = 9
STONES_PER_PLAYER = 14
MAX_PERIMETER_STONES = 6
CAPTURE_BASE = 56
NUM_ACTIONS = 192

// Inclusive column range for each row (the same scheme as boardUtil.ms).
rowCols = [[2,4], [1,6], [0,6], [0,7], [0,6], [0,7], [0,6], [1,6], [2,4]]

// rowOf[i], colOf[i], hx[i] for point i (index 0 unused).  hx is the
// horizontal position in half-steps, 2*col - (row % 2), so that the six
// neighbors of a point are at hx +- 2 in the same row, or hx +- 1 in the
// rows above and below.
rowOf = [null]
colOf = [null]
hx = [null]
_indexAt = {}		// key: row*100 + hx + 10; value: point
for _row in range(0, NUM_ROWS - 1)
	for _col in range(rowCols[_row][0], rowCols[_row][1])
		rowOf.push _row
		colOf.push _col
		hx.push 2 * _col - _row % 2
		_indexAt[_row * 100 + hx[-1] + 10] = rowOf.len - 1
	end for
end for

// The point at half-step position h in the given row, or 0 if none.
pointAt = function(h, row)
	if row < 0 or row >= NUM_ROWS then return 0
	key = row * 100 + h + 10
	if _indexAt.hasIndex(key) then return _indexAt[key]
	return 0
end function

// The six perimeters (double lines), each as [end, center, end].
perimeters = [[1,2,3], [4,10,17], [9,16,24], [32,40,47], [39,46,52], [53,54,55]]
perimeterPoints = []
isPerimeterEnd = [0] * 56
isPerimeterCenter = [0] * 56
for _per in perimeters
	perimeterPoints += _per
	isPerimeterEnd[_per[0]] = 1
	isPerimeterCenter[_per[1]] = 1
	isPerimeterEnd[_per[2]] = 1
end for

// The points of the triangle with the given apex, extending down (dy = 1) or
// up (dy = -1) with side length n, row by row from the apex; or null if it
// does not fit on the board.
_trianglePoints = function(apex, dy, n)
	h = hx[apex]
	row = rowOf[apex]
	pts = []
	for k in range(0, n)
		for j in range(0, k)
			p = pointAt(h - k + 2 * j, row + dy * k)
			if not p then return null
			pts.push p
		end for
	end for
	return pts
end function

// Every equilateral triangle whose sides run along board lines, with side
// length >= 2.  The ORDER of this list is part of the network's contract
// (board._build_triangles in the Python); don't change it.  Each entry is a
// map with index, corners (sorted), points (sorted, corners included), size.
triangles = []
trianglesAtCorner = []		// trianglesAtCorner[i]: triangles with a corner at i
for _i in range(0, NUM_POINTS)
	trianglesAtCorner.push []
end for
for _apex in range(1, NUM_POINTS)
	for _dy in [1, -1]
		for _n in range(2, NUM_ROWS - 1)
			_pts = _trianglePoints(_apex, _dy, _n)
			if _pts == null then continue
			_corners = [_apex, _pts[-(_n + 1)], _pts[-1]]
			_corners.sort
			_pts.sort
			_t = {"index": triangles.len, "corners": _corners, "points": _pts, "size": _n}
			triangles.push _t
			for _c in _corners
				trianglesAtCorner[_c].push _t
			end for
		end for
	end for
end for

// The triangle captured by a capture action.
actionTriangle = function(action)
	return triangles[action - CAPTURE_BASE]
end function

// The players in seat order: the player to move first, then the rest in
// turn order.  (The network sees players relative to the player to move.)
seats = function(state)
	i = state.players.indexOf(state.toMove)
	return state.players[i:] + state.players[:i]
end function

// How many of player's stones are on perimeter points.
perimeterCount = function(board, player)
	count = 0
	for p in perimeterPoints
		if board[p] == player then count += 1
	end for
	return count
end function

// Player's triangles: those with player's stones on all three corners, in
// index order.
trianglesOf = function(board, player)
	result = []
	for t in triangles
		c = t.corners
		if board[c[0]] == player and board[c[1]] == player and board[c[2]] == player then
			result.push t
		end if
	end for
	return result
end function

// Whether triangle t (one of player's) is full: some other player has a
// stone inside it or on its border.  Only full triangles can be captured.
isFull = function(board, t, player)
	for p in t.points
		q = board[p]
		if q and q != player then return true
	end for
	return false
end function

// A list of 56 flags: 1 where the perimeter rules forbid player to place,
// whether or not the point is empty.  On each perimeter a player may occupy
// one end, both ends, or only the center, and at most 6 perimeter points in
// all.
blockedPoints = function(board, player)
	blocked = [0] * 56
	if perimeterCount(board, player) >= MAX_PERIMETER_STONES then
		for p in perimeterPoints
			blocked[p] = 1
		end for
		return blocked
	end if
	for per in perimeters
		if board[per[1]] == player then
			blocked[per[0]] = 1
			blocked[per[2]] = 1
		end if
		if board[per[0]] == player or board[per[2]] == player then blocked[per[1]] = 1
	end for
	return blocked
end function

// The points where player (default: the player to move) may place a stone.
legalPlacements = function(state, player=null)
	if player == null then player = state.toMove
	if not state.hand[player] then return []
	board = state.board
	blocked = blockedPoints(board, player)
	result = []
	for i in range(1, NUM_POINTS)
		if not board[i] and not blocked[i] then result.push i
	end for
	return result
end function

// All legal actions for the player to move: placements, then captures of
// that player's full triangles.
legalActions = function(state)
	player = state.toMove
	result = legalPlacements(state, player)
	for t in trianglesOf(state.board, player)
		if isFull(state.board, t, player) then result.push CAPTURE_BASE + t.index
	end for
	return result
end function


runUnitTests = function
	errorCount = 0
	assertEqual = function(actual, expected, note)
		if actual != expected then
			print "Unit test failure (" + note + "): expected " + expected + ", got " + actual
			outer.errorCount = errorCount + 1
		end if
	end function

	assertEqual rowOf.len, NUM_POINTS + 1, "point count"
	assertEqual pointAt(hx[28] + 2, rowOf[28]), 29, "east of 28"
	assertEqual pointAt(hx[28] - 1, rowOf[28] + 1), 35, "southwest of 28"
	assertEqual triangles.len, NUM_ACTIONS - CAPTURE_BASE, "triangle count"
	assertEqual triangles[0].corners, [1, 11, 13], "first triangle"
	assertEqual triangles[0].points, [1, 5, 6, 11, 12, 13], "first triangle points"

	board = [0] * 56
	for p in [1, 11, 13]
		board[p] = 1
	end for
	assertEqual trianglesOf(board, 1).len, 1, "one triangle"
	assertEqual isFull(board, triangles[0], 1), false, "empty triangle"
	board[5] = 2
	assertEqual isFull(board, triangles[0], 1), true, "full triangle"
	state = {"board": board, "hand": {1: 11, 2: 13}, "players": [1, 2], "toMove": 1}
	assertEqual legalActions(state)[-1], CAPTURE_BASE, "capture is legal"
	assertEqual legalPlacements(state).indexOf(2), null, "perimeter center blocked"
	assertEqual seats({"players": [1, 2, 3], "toMove": 2}), [2, 3, 1], "seats"

	if errorCount == 0 then
		print "All tests passed."
	else
		print errorCount + " error" + "s" * (errorCount != 1) + " found."
	end if
end function

if locals == globals then runUnitTests
