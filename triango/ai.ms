// This is the Triango AI.
// It is built on top of the alpha-beta module; see:
// https://github.com/JoeStrout/miniscript-alphabeta

import "importUtil"
ensureImport "alphaBeta"

infinity = alphaBeta.infinity
players = ["0", "1"]
boardPositions = range(1, 55)

// Helper function to set a character of a string by index.
string.setAt = function(index, char)
	return self[:index] + char + self[index+1:]
end function

if globals.hasIndex("P1") then
	P1 = str(P1)
	P2 = str(P2)
	P3 = str(P3)
	P4 = str(P4)
else	//  (for testing in isolation)
	P1 = "1"; P2 = "2"; P3 = "4"; P4 = "8"
end if

BoardNode = new alphaBeta.Node
// Our board representation is a 56-character string;
// board[0] is not used;
// board[i] is "0" or the owner of the piece at that point.
// (We use stringified P1, P2, etc. from triango.ms for our players)
BoardNode.board = " " + "0" * 55
BoardNode.piecesLeft = null	// list: how many pieces still in the bucket
BoardNode.tris = null		// list: all triangles on the board

BoardNode.player = P1		// player to move next
BoardNode.winner = null		// player who has won, if any

BoardNode.initToStartingState = function
	self.board = " " + "." * 55
	self.piecesLeft = [14, 14]
	self.tris = []
end function

BoardNode.initFromGameState = function
	self.board = pieces.join("")
	self.piecesLeft = [
		buckets[1].myStones.len,
		buckets[2].myStones.len ]
	self.player = str(player)
	self.tris = boardUtil.findTriangles
end function

BoardNode.makeChild = function(pointToPlay)
	child = new BoardNode
	child.board = self.board.setAt(pointToPlay, self.player)
	if self.player == P1 then
		child.player = P2
		child.piecesLeft = [self.piecesLeft[0] - 1, self.piecesLeft[1]]
	else
		child.player = P1
		child.piecesLeft = [self.piecesLeft[0], self.piecesLeft[1] - 1]
	end if
	// ToDo: handle captures
	
	child.tris = self.tris[:]
	child.updateTrisAtPoint(pointToPlay)
	
	// precompute heuristic value (and winner), and store on the child
	// (so if we access it again, we don't redo all those calculations)
	child.heuristicValue = child.heuristicValue
	return child
end function

BoardNode.updateTrisAtPoint = function(pos)
	// Mark as closed any existing enemy triangles that enclose pos.
	// (ToDo)
	
	// Update self.tris with any additional triangles formed at pos.
	self.tris += boardUtil.findAllTrisAtPos(pos, self.board)
end function

// Return a list with the locations of all legal moves, or "C" for capture.
BoardNode.allLegalMoves = function
	result = []
	if self.piecesLeft[self.player == P2] > 0 then
		for i in boardPositions
			if self.board[i] == "0" then
				// ToDo: check outer edge rule
				result.push i
			end if
		end for
	end if
	// ToDo: add "C" if capture is possible
	
	return result
end function

// get child states of this node (i.e., states that represent
// the game after all possible moves of self.player
BoardNode.children = function
	result = []
	for i in self.allLegalMoves
		result.push self.makeChild(i)
	end for
	return result
end function

// get the heuristic value of this game state (< 0 if player 0
// is winning, > 0 if player 1 is winning)
BoardNode.heuristicValue = function
	score = 0
	for pl in players
		plSign = 1 - 2 * (pl == P1)
		// points for pieces still in the bucket
		score += plSign * 1 * self.piecesLeft[pl=="1"]
		// points for pieces out on the board
		qtyOnBoard = self.board.split(pl) - 1
		score += plSign * 1 * qtyOnBoard
	end for
	// points for triangles
	for t in self.tris
		plSign = 1 - 2 * (t.player == P1)
		score += plSign * (5 + 3 * t.closed)
	end for
	return score
end function

// return whether the game is over
BoardNode.isGameOver = function
	return self.winner != null
end function

// Return the best move for the current player
// as a board location, or "C" for capture.
BoardNode.pickMove = function(searchDepth=2)
	t0 = time
	bestMoves = []; bestScore = null
	for move in self.allLegalMoves
		imagine = self.makeChild(move)
		score = alphaBeta.alphaBeta(imagine, searchDepth)
		print "If I go at " + move + ", my worst result is " + score, ""
		if score == bestScore then
			bestMoves.push move
			print "    (also good)"
		else if not bestMoves or score > bestScore then
			print "    (New best!)"
			bestScore = score
			bestMoves = [move]
		else
			print
		end if
	end for
	if not bestMoves then
		print "I have no legal moves."
		return null
	end if
	pick = bestMoves[bestMoves.len * rnd]
	t1 = time
	print "So, I will go at " + pick + " (time: " + round(t1-t0) + " sec)"
	return pick
end function
