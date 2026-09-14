// triangoGame.ms
//
// TrianGO game state and rules: a port of game.py from the Python reference
// (triango/python; the copy in ML-work-2026/rl_triango is what the network
// was trained against).  In brief:
//
//   * Each player starts with 14 stones in hand; turns go in `players` order.
//   * A turn is either placing a stone from your hand on an empty point, or
//     capturing one of your full triangles.
//   * Perimeter rules, per player: on each perimeter you may occupy one end,
//     both ends, or only the center, and at most 6 perimeter points in all.
//   * A triangle is three of your stones on the corners of an equilateral
//     triangle along board lines, side >= 2.  It is full if any opponent
//     stone is inside it or on its border; only full triangles can be
//     captured.
//   * Capturing removes every stone in the triangle, corners included.  Your
//     own stones go back to your hand; opponents' are out of the game.
//   * A player with no legal move on their turn is skipped.  The game ends as
//     soon as at most one player can move; that player wins (or, if nobody
//     can, the player who just moved).
//
// A game is also a position map for triangoBoard and TriangoNet (it has
// board, hand, players, and toMove), so those work on it directly.
//
// Usage:
//
//     g = triangoGame.start([1, 2])      // players, in turn order
//     g.legalActions                     // placements 1-55, captures 56+
//     err = g.play(action)               // null, or why the move is illegal
//     g.winner                           // null until the game is over
//
// Players may be any distinct nonzero numbers (1-4, or bit flags like P1-P4
// in triango.ms).

import "importUtil"
ensureImport "triangoBoard"

Game = {}
Game.board = null		// list of 56: player at each point, or 0 (index 0 unused)
Game.hand = null		// map: player -> stones in hand
Game.players = null		// players in turn order
Game.toMove = null		// player to move; null once the game is over
Game.winner = null		// null until the game is over
Game.lastMover = null
Game.passed = null		// players skipped (unable to move) after the last move
Game.numMoves = 0
Game.captured = null	// map: player -> opponent stones this player captured
Game.lost = null		// map: player -> own stones captured by opponents
Game.tris = null		// map: player -> that player's triangles, in index order

// Start a new game.
start = function(players, firstPlayer=null)
	g = new Game
	g.players = players[:]
	g.board = [0] * 56
	g.hand = {}
	g.captured = {}
	g.lost = {}
	g.tris = {}
	for p in players
		g.hand[p] = triangoBoard.STONES_PER_PLAYER
		g.captured[p] = 0
		g.lost[p] = 0
		g.tris[p] = []
	end for
	if firstPlayer == null then firstPlayer = players[0]
	g.toMove = firstPlayer
	g.passed = []
	return g
end function

// An independent copy (for search).  Triangle lists are replaced rather than
// mutated, so they can be shared.
Game.copy = function
	c = new Game
	c.players = self.players
	c.board = self.board[:]
	c.hand = self.hand + {}
	c.captured = self.captured + {}
	c.lost = self.lost + {}
	c.tris = self.tris + {}
	c.toMove = self.toMove
	c.winner = self.winner
	c.lastMover = self.lastMover
	c.passed = self.passed[:]
	c.numMoves = self.numMoves
	return c
end function

Game.isOver = function
	return self.winner != null
end function

// Player's full triangles (capturable), in index order.
Game.fullTriangles = function(player=null)
	if player == null then player = self.toMove
	result = []
	for t in self.tris[player]
		if triangoBoard.isFull(self.board, t, player) then result.push t
	end for
	return result
end function

// All legal actions for the player to move: placements, then captures.
Game.legalActions = function
	if self.winner != null then return []
	p = self.toMove
	result = triangoBoard.legalPlacements(self, p)
	for t in self.fullTriangles(p)
		result.push triangoBoard.CAPTURE_BASE + t.index
	end for
	return result
end function

Game.hasLegalMove = function(player)
	if triangoBoard.legalPlacements(self, player) then return true
	for t in self.tris[player]
		if triangoBoard.isFull(self.board, t, player) then return true
	end for
	return false
end function

// Why player may not place at point, or null if they may.
Game.placementError = function(point, player=null)
	if player == null then player = self.toMove
	if not point isa number or point < 1 or point > triangoBoard.NUM_POINTS or
	  point != floor(point) then
		return point + " is not a point on the board"
	end if
	if self.board[point] then return "point " + point + " is occupied"
	if not self.hand[player] then return "no stones left to place"
	if triangoBoard.blockedPoints(self.board, player)[point] then
		if triangoBoard.perimeterCount(self.board, player) >= triangoBoard.MAX_PERIMETER_STONES then
			return "you already have " + triangoBoard.MAX_PERIMETER_STONES + " stones on perimeters"
		end if
		return "a perimeter may not have your stones on both its center and an end"
	end if
	return null
end function

// Play an action for the player to move.  Returns null on success, or a
// string saying why the action is illegal (in which case nothing changes).
Game.play = function(action)
	if self.winner != null then return "the game is over"
	p = self.toMove
	if action isa number and action >= triangoBoard.CAPTURE_BASE then
		if action >= triangoBoard.NUM_ACTIONS or action != floor(action) then
			return "no such action: " + action
		end if
		tri = triangoBoard.actionTriangle(action)
		ok = false
		for t in self.fullTriangles(p)
			if t.index == tri.index then ok = true
		end for
		if not ok then return "not a full triangle of the player to move"
		self._capture p, tri
	else
		e = self.placementError(action, p)
		if e then return e
		self._place p, action
	end if
	self.lastMover = p
	self.numMoves = self.numMoves + 1
	self._advance p
	return null
end function

Game._place = function(player, point)
	board = self.board
	board[point] = player
	self.hand[player] = self.hand[player] - 1
	added = []
	for t in triangoBoard.trianglesAtCorner[point]
		c = t.corners
		if board[c[0]] == player and board[c[1]] == player and board[c[2]] == player then
			added.push t
		end if
	end for
	if added then
		lst = self.tris[player] + added
		lst.sort "index"
		self.tris[player] = lst
	end if
end function

Game._capture = function(player, tri)
	board = self.board
	inTri = [0] * 56
	for pt in tri.points
		inTri[pt] = 1
	end for
	for q in self.players
		n = 0
		for pt in tri.points
			if board[pt] == q then n += 1
		end for
		if not n then continue
		// Triangles with a corner in the capture are gone.
		keep = []
		for t in self.tris[q]
			c = t.corners
			if not (inTri[c[0]] or inTri[c[1]] or inTri[c[2]]) then keep.push t
		end for
		self.tris[q] = keep
		if q == player then
			self.hand[q] = self.hand[q] + n
		else
			self.captured[player] = self.captured[player] + n
			self.lost[q] = self.lost[q] + n
		end if
	end for
	for pt in tri.points
		board[pt] = 0
	end for
end function

// Find the next player able to move, or end the game.
Game._advance = function(mover)
	n = self.players.len
	i = self.players.indexOf(mover)
	first = null
	skipped = []
	for k in range(1, n)
		q = self.players[(i + k) % n]
		if self.hasLegalMove(q) then
			if first != null then		// at least two players can move
				self.toMove = first
				self.passed = skipped
				return
			end if
			first = q
		else if first == null then
			skipped.push q
		end if
	end for
	if first == null then self.winner = mover else self.winner = first
	self.toMove = null
	self.passed = []
end function

// A short description of an action: the point, or C and the triangle's corners.
actionStr = function(action)
	if action >= triangoBoard.CAPTURE_BASE then
		return "C" + triangoBoard.actionTriangle(action).corners.join("-")
	end if
	return str(action)
end function
