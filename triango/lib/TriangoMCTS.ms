// TriangoMCTS.ms
//
// PUCT Monte Carlo tree search over the TrianGO network: a port of az/mcts.py
// from ML-work-2026/rl_triango, for one tree at a time.
//
// Values are per player, not signed: an evaluation gives every player's
// probability of winning (a map, player -> value).  Each node belongs to the
// player to move there, and its edge statistics are from that player's point
// of view: W[i] sums the mover's share of every simulation through
// actions[i].  With no sign flipping, the same code handles 2-4 players and
// turns skipped by players who cannot move.
//
// Unvisited children get "first play urgency": the node's mean value so far,
// minus fpuReduction.  Root Dirichlet noise is left out; it is for self-play
// training, and only weakens actual play.
//
// The search is incremental, like the Connect-4 MCTS.ms: a network
// evaluation takes around 20 ms, so `step` runs as many simulations as fit in
// a time budget and returns, letting the caller draw a frame in between.
// Call `begin`, then `step` until it returns true, then `bestMove`.  Or, when
// nothing needs drawing, just call `search`.

import "importUtil"
ensureImport "triangoBoard"

net = null				// a TriangoNet, set by the caller
sims = 100				// root visits per search
cPuct = 1.25			// values are in [0, 1]
fpuReduction = 0.1
root = null
game = null				// copy of the position being searched
evals = 0				// network evaluations for this search

newNode = function
	return {"mover": null, "actions": null, "P": null, "N": null, "W": null,
	  "total": 0, "wsum": 0, "children": {}, "terminal": null}
end function

// Network evaluation: the legal actions, their priors (the policy softmaxed
// over just those actions), and the value map.
evaluate = function(g)
	out = self.net.evaluateState(g)
	self.evals = self.evals + 1
	actions = g.legalActions
	seats = triangoBoard.seats(g)
	value = {}
	for k in seats.indexes
		value[seats[k]] = out["values"][k]
	end for
	return {"actions": actions, "priors": self.net.priors(out.logits, actions), "value": value}
end function

// Value map for a finished game.
outcome = function(g)
	value = {}
	for p in g.players
		value[p] = (p == g.winner)
	end for
	return value
end function

expandNode = function(node, mover, ev)
	node.mover = mover
	node.actions = ev.actions
	node.P = ev.priors
	node.N = [0] * ev.actions.len
	node.W = [0] * ev.actions.len
	node.total = 0
	node.wsum = ev.value[mover]		// includes this node's own evaluation
end function

// PUCT: the index maximizing Q + cPuct * P * sqrt(total + 1) / (1 + N).
selectIndex = function(node)
	fpu = node.wsum / (node.total + 1) - self.fpuReduction
	c = self.cPuct * sqrt(node.total + 1)
	N = node.N
	W = node.W
	P = node.P
	best = -1e18
	bestI = 0
	for i in N.indexes
		n = N[i]
		if n > 0 then q = W[i] / n else q = fpu
		score = q + c * P[i] / (1 + n)
		if score > best then
			best = score
			bestI = i
		end if
	end for
	return bestI
end function

backup = function(path, value)
	for step in path
		node = step[0]
		i = step[1]
		v = value[node.mover]
		node.N[i] = node.N[i] + 1
		node.W[i] = node.W[i] + v
		node.total = node.total + 1
		node.wsum = node.wsum + v
	end for
end function

// Start a search from game g (a triangoGame; it is not modified).  The root
// is evaluated immediately, so even a tiny search has a real policy.
begin = function(g)
	self.game = g.copy
	self.root = self.newNode
	self.evals = 0
	self.expandNode self.root, self.game.toMove, self.evaluate(self.game)
end function

finished = function
	return self.root.total >= self.sims or self.root.actions.len < 2
end function

// One simulation: descend by PUCT to an unexpanded node, evaluate it (or
// score the finished game), and back the value up the path.
simulate = function
	node = self.root
	g = self.game.copy
	path = []
	while node.actions != null
		i = self.selectIndex(node)
		path.push [node, i]
		g.play node.actions[i]
		if not node.children.hasIndex(i) then node.children[i] = self.newNode
		node = node.children[i]
		if g.winner != null then
			if node.terminal == null then node.terminal = self.outcome(g)
			self.backup path, node.terminal
			return
		end if
	end while
	ev = self.evaluate(g)
	self.expandNode node, g.toMove, ev
	self.backup path, ev.value
end function

// Run simulations until the search is complete or `budget` seconds are spent.
// Returns true when the search is done.  A budget of 0 runs exactly one
// simulation per call; null runs the search to completion in one go.
step = function(budget = 0.012)
	t0 = time
	while not self.finished
		self.simulate
		if budget != null and time - t0 >= budget then break
	end while
	return self.finished
end function

// Convenience: run a whole search from g and return the chosen action.
search = function(g)
	self.begin g
	self.step null
	return self.bestMove
end function

// The most-visited action -- AlphaZero's greedy choice.  (With a single
// legal action there is nothing to search, and that action is returned.)
bestMove = function
	best = -1
	bestI = 0
	for i in self.root.N.indexes
		if self.root.N[i] > best then
			best = self.root.N[i]
			bestI = i
		end if
	end for
	return self.root.actions[bestI]
end function

// The root player's estimated win probability, from the search so far.
rootValue = function
	return self.root.wsum / (self.root.total + 1)
end function

// Root visit counts, as a map: action -> visits.
visitCounts = function
	result = {}
	for i in self.root.actions.indexes
		result[self.root.actions[i]] = self.root.N[i]
	end for
	return result
end function
