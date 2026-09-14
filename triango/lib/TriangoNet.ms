// TriangoNet.ms
//
// Inference for the AlphaZero TrianGO network trained in PyTorch
// (ML-work-2026/rl_triango): a 28 -> 128 hex-conv stem, six 128-channel
// residual blocks, and policy and value heads, evaluated through the
// intrinsic Matrix class (raylib-miniscript), with no scripted loop anywhere
// in the arithmetic.
//
// Weights come from `az_triango.msmx`, written by rl_triango/export_msmx.py.
// The exporter folds every BatchNorm into the conv ahead of it and bakes the
// heads' gathers and poolings into ordinary matrices, which is why nothing
// here mentions BatchNorm or triangles.  The layout below must agree with it.
//
//
// LAYOUT
//
// The net runs on a 9x9 grid embedding of the hex board, in which a point's
// six neighbors are its 3x3 neighborhood minus the (-1,-1) and (+1,+1)
// corners.  Activations are CELLS x channels, where the cells are the 55
// points plus the 14 off-board grid cells adjacent to them (the "halo"), 69 in
// all, ordered by grid row, then column.  Cells farther off the board would
// always be zero, and are left out.
//
// The halo is there because the trained net zeroes off-board cells only after
// the stem and after each residual block.  Inside a block, the first conv's
// output is nonzero just off the board, and the second conv reads it.  So the
// halo is zeroed after the stem and after every block, and nowhere else.
//
// A hex conv is then one im2col followed by one gemm:
//
//      cols  = 69 x (7*Cin)      each cell's 7-cell neighborhood, zero-padded
//      W     = (7*Cin) x Cout    row k*Cin + ci, k indexing HEX_OFFSETS
//      out   = cols * W + b      one gemm, bias broadcast by gemm's addend
//
// and a 1x1 conv is just `h * W + b`.  Each grid row's cells are a contiguous
// run of columns, so for a fixed offset the gather is one block copy per grid
// row: at most 63 copies per im2col, planned once, at load time.
//
//
// USAGE
//
//      net = TriangoNet.load
//      out = net.evaluateState(state)     // state: see triangoBoard.ms
//      out.logits       192 raw policy logits, by action (see triangoBoard)
//      out.values       win probability for each seat (seat 0 = to move)
//
// The logits are unmasked: use `priors` or `bestAction` to restrict them to
// the legal actions, since masking before the softmax is what keeps an
// illegal action from taking probability away from the legal ones.

import "importUtil"
ensureImport "matrixUtil"
ensureImport "triangoBoard"

NUM_PLANES = 28
CH = 128			// trunk channels
BLOCKS = 6			// residual blocks
GRID = 9			// the grid is GRID x GRID
NEG = -10000		// logit for impossible outputs (action 0, absent seats)
NUM_TRIS = triangoBoard.triangles.len

// Grid [dr, dc] steps to a cell's hex neighborhood: the 3x3 offsets in
// row-major order, minus the two corners.  Weight row blocks follow this
// order; export_msmx.py's HEX_OFFSETS must match.
HEX_OFFSETS = [[-1,0], [-1,1], [0,-1], [0,0], [0,1], [1,-1], [1,0]]

// Where `load` looks for the weights by default: next to the running script
// (raylib-miniscript), then the current directory (Mini Micro).
defaultPaths = ["az_triango.msmx"]
if env.hasIndex("MS_SCRIPT_DIR") then
	defaultPaths.insert 0, file.child(env.MS_SCRIPT_DIR, "az_triango.msmx")
end if


//----------------------------------------------------------------------
// Layout, computed from the board geometry (board.GRID_RC in the Python).
//----------------------------------------------------------------------

// gridRC[i]: [grid row, grid col] of point i (index 0 unused).  Axial hex
// coordinates relative to the center point 28, shifted to start at 0.
gridRC = [null]
_buildGrid = function
	tb = triangoBoard
	cx = tb.hx[28]
	cy = tb.rowOf[28]
	qs = []
	rs = []
	for i in range(1, tb.NUM_POINTS)
		qs.push (tb.hx[i] - cx - (tb.rowOf[i] - cy)) / 2
		rs.push tb.rowOf[i] - cy
	end for
	q0 = qs[:]; q0.sort
	r0 = rs[:]; r0.sort
	for i in qs.indexes
		gridRC.push [rs[i] - r0[0], qs[i] - q0[0]]
	end for
end function
_buildGrid

// cells: [grid row, grid col] of each cell, in activation-row order.
// pointCell[i]: the cell (activation row) of point i (index 0 unused).
// onBoard[c]: 1 if cell c is a point, 0 if it is in the halo.
// rowSpans[r]: [first cell, first grid col, count] for grid row r.
cells = []
pointCell = [null]
onBoard = []
rowSpans = []
_buildCells = function
	isCell = {}
	for i in range(1, triangoBoard.NUM_POINTS)
		rc = gridRC[i]
		for off in HEX_OFFSETS
			r = rc[0] + off[0]
			c = rc[1] + off[1]
			if r >= 0 and r < GRID and c >= 0 and c < GRID then isCell[r * GRID + c] = 1
		end for
	end for
	keys = isCell.indexes
	keys.sort
	cellOfKey = {}
	for k in keys.indexes
		cellOfKey[keys[k]] = k
		cells.push [floor(keys[k] / GRID), keys[k] % GRID]
		onBoard.push 0
	end for
	for i in range(1, triangoBoard.NUM_POINTS)
		c = cellOfKey[gridRC[i][0] * GRID + gridRC[i][1]]
		pointCell.push c
		onBoard[c] = 1
	end for
	for r in range(0, GRID - 1)
		first = null
		for k in cells.indexes
			if cells[k][0] != r then continue
			if first == null then first = k
			if cells[k][1] != cells[first][1] + k - first then
				print "TriangoNet: grid row " + r + " is not contiguous"
				exit 1
			end if
			count = k - first + 1
		end for
		rowSpans.push [first, cells[first][1], count]
	end for
end function
_buildCells
NUM_CELLS = cells.len

// The im2col copy plan: for each offset k and destination grid row r, the
// block [srcCell, dstCell, count, k] -- destination cells reading the source
// cells one offset away, where both exist.  Everything else in an im2col
// buffer is zero padding.
plan = []
_buildPlan = function
	for k in HEX_OFFSETS.indexes
		dr = HEX_OFFSETS[k][0]
		dc = HEX_OFFSETS[k][1]
		for r in range(0, GRID - 1)
			sr = r + dr
			if sr < 0 or sr >= GRID then continue
			d = rowSpans[r]
			s = rowSpans[sr]
			// Destination column col reads source column col + dc.
			lo = d[1]
			if s[1] - dc > lo then lo = s[1] - dc
			hi = d[1] + d[2]
			if s[1] + s[2] - dc < hi then hi = s[1] + s[2] - dc
			if lo >= hi then continue
			plan.push [s[0] + lo + dc - s[1], d[0] + lo - d[1], hi - lo, k]
		end for
	end for
end function
_buildPlan

// The planes that never change at a point: on_board, perimeter_end,
// perimeter_center (planes 4-6).
pointStatic = [null]
for _i in range(1, triangoBoard.NUM_POINTS)
	pointStatic.push [1, triangoBoard.isPerimeterEnd[_i], triangoBoard.isPerimeterCenter[_i]]
end for


//----------------------------------------------------------------------
// Loading.
//----------------------------------------------------------------------

// Names of the matrices after the stem and residual blocks, in file order.
HEAD_NAMES = ["pConvW", "pConvB", "placeW", "placeB", "triPool",
  "cap1W", "cap1B", "cap2W", "cap2B",
  "vConvW", "vConvB", "vMean", "vFc1Wv", "vFc1Wg", "vFc1B", "vFc2W", "vFc2B"]

// Load the weight blob.  Returns the net, or an error value.
load = function(path=null)
	if path == null then
		for path in defaultPaths
			if file.exists(path) then break
		end for
	end if
	rd = file.loadRaw(path)
	if rd == null then return err("TriangoNet: cannot read " + path)

	mats = []
	pos = 0
	while pos < rd.len
		m = Matrix.ofSize(1, 1)
		pos = m.readRawData(rd, "auto", pos)
		if pos isa error then return pos
		mats.push m
	end while

	expected = 2 + 4 * BLOCKS + HEAD_NAMES.len
	if mats.len != expected then
		return err("TriangoNet: expected " + expected + " matrices in " + path +
		  ", got " + mats.len)
	end if

	net = new self
	net.stem = mats[0:2]
	net.blocks = []
	i = 2
	for b in range(1, BLOCKS)
		net.blocks.push mats[i:i+4]
		i += 4
	end for
	net.w = {}
	for name in HEAD_NAMES
		net.w[name] = mats[i]
		i += 1
	end for

	// Catch a blob made for some other layout.
	if net.stem[0].rows != 7 * NUM_PLANES or net.blocks[0][0].rows != 7 * CH or
	  net.w.triPool.rows != 2 * NUM_TRIS or net.w.triPool.columns != NUM_CELLS then
		return err("TriangoNet: " + path + " does not match this layout")
	end if

	net.allocBuffers
	return net
end function


// Preallocate every buffer the forward pass needs, so that evaluating a
// position does no large allocation.
allocBuffers = function
	w = self.w
	n = NUM_CELLS
	hc = w.pConvW.columns		// policy head channels
	vc = w.vConvW.columns		// value head channels
	self.buf = {}
	b = self.buf
	b.x = Matrix.ofSize(n, NUM_PLANES)				// input planes
	b.stemCols = Matrix.ofSize(n, 7 * NUM_PLANES)	// im2col of the input
	b.cols = Matrix.ofSize(n, 7 * CH)				// im2col of the trunk
	b.block = Matrix.ofSize(0, 0)					// im2col scratch
	b.h = Matrix.ofSize(n, CH)						// trunk activation
	b.y = Matrix.ofSize(n, CH)						// residual branch
	b.p = Matrix.ofSize(n, hc)						// policy head conv
	b.place = Matrix.ofSize(n, 1)					// placement logit per cell
	b.pooled = Matrix.ofSize(2 * NUM_TRIS, hc)		// triangle poolings
	b.capH = Matrix.ofSize(NUM_TRIS, hc)			// capture hidden layer
	b.cap = Matrix.ofSize(NUM_TRIS, 1)				// capture logits
	b.v = Matrix.ofSize(n, vc)						// value head conv
	b.g = Matrix.ofSize(1, CH)						// mean trunk features
	b.vh = Matrix.ofSize(1, w.vFc1B.columns)		// value hidden layer
	b.value = Matrix.ofSize(1, w.vFc2B.columns)		// value logits
	maskRows = []
	for c in onBoard
		maskRows.push [c]
	end for
	b.mask = Matrix.fromList(maskRows)				// n x 1: 1 on board, 0 in halo
end function


//----------------------------------------------------------------------
// Inference.
//----------------------------------------------------------------------

// Gather each cell's hex neighborhood into `dest` (cells x 7*ch).  The plan
// writes the same blocks every time, and nothing else writes these buffers,
// so the zero padding set up at allocation never needs refilling.
im2col = function(src, dest, ch)
	blk = self.buf.block
	for step in plan
		src.getSub step[0], 0, step[2], ch, blk
		dest.setSub step[1], step[3] * ch, blk
	end for
	return dest
end function


// Encode a position (see triangoBoard.ms for the state map) into the input
// matrix, and return it.  The planes are those of rl_triango/encode.py
// (ENCODING_VERSION 1), with players relative to the player to move:
//
//     0-3   stones[seat]           8-11   empty_tri[seat]    16-19  hand[seat]/14
//     4     on_board               12-15  full_tri[seat]     20-23  perimeter_count[seat]/6
//     5     perimeter_end                                    24-27  seat[seat] in game
//     6     perimeter_center
//     7     legal_placement
//
// Halo rows are never written, and stay zero.
encode = function(state)
	tb = triangoBoard
	board = state.board
	seats = tb.seats(state)
	seatOf = {}
	for k in seats.indexes
		seatOf[seats[k]] = k
	end for

	// Planes 16-27 have the same value at every point.
	tail = [0] * 12
	for k in seats.indexes
		p = seats[k]
		tail[k] = state.hand[p] / tb.STONES_PER_PLAYER
		tail[4 + k] = tb.perimeterCount(board, p) / tb.MAX_PERIMETER_STONES
		tail[8 + k] = 1
	end for

	// Points inside or on each seat's empty and full triangles.
	emptyCov = []
	fullCov = []
	for k in range(0, 3)
		emptyCov.push [0] * 56
		fullCov.push [0] * 56
	end for
	for k in seats.indexes
		p = seats[k]
		for t in tb.trianglesOf(board, p)
			if tb.isFull(board, t, p) then cov = fullCov[k] else cov = emptyCov[k]
			for q in t.points
				cov[q] = 1
			end for
		end for
	end for

	legal = [0] * 56
	for q in tb.legalPlacements(state)
		legal[q] = 1
	end for

	x = self.buf.x
	e0 = emptyCov[0]; e1 = emptyCov[1]; e2 = emptyCov[2]; e3 = emptyCov[3]
	f0 = fullCov[0]; f1 = fullCov[1]; f2 = fullCov[2]; f3 = fullCov[3]
	for i in range(1, tb.NUM_POINTS)
		stones = [0, 0, 0, 0]
		if board[i] then stones[seatOf[board[i]]] = 1
		x.setRow pointCell[i], stones + pointStatic[i] + [legal[i],
		  e0[i], e1[i], e2[i], e3[i], f0[i], f1[i], f2[i], f3[i]] + tail
	end for
	return x
end function


// Evaluate an encoded position (default: the matrix `encode` filled).
// numPlayers is how many seats are in the game.
//
// Returns a map:
//     logits        192 raw policy logits, by action (logits[0] is NEG)
//     valueLogits   4 value logits by seat, NEG for seats not in the game
//     values        4 win probabilities by seat (softmax of valueLogits)
evaluate = function(x=null, numPlayers=2)
	b = self.buf
	w = self.w
	if x == null then x = b.x

	// Stem: hex conv 28 -> CH, relu, zero the halo.
	self.im2col x, b.stemCols, NUM_PLANES
	b.stemCols.gemm self.stem[0], self.stem[1], b.h
	b.h.relu
	b.h.elemMultiplyBy b.mask

	// Residual trunk.  The first conv's output is NOT masked (the second conv
	// reads its halo); the block's output is.
	for blk in self.blocks
		self.im2col b.h, b.cols, CH
		b.cols.gemm blk[0], blk[1], b.y
		b.y.relu
		self.im2col b.y, b.cols, CH
		b.cols.gemm blk[2], blk[3], b.y
		b.h.add b.y
		b.h.relu
		b.h.elemMultiplyBy b.mask
	end for

	// Policy head: 1x1 conv, relu; placement logit per cell; capture logits
	// from each triangle's [points-mean | corners-mean] features.
	b.h.gemm w.pConvW, w.pConvB, b.p
	b.p.relu
	b.p.gemm w.placeW, w.placeB, b.place
	w.triPool.gemm b.p, null, b.pooled
	b.pooled.reshape NUM_TRIS, 2 * b.p.columns		// O(1): rows 2t, 2t+1 side by side
	b.pooled.gemm w.cap1W, w.cap1B, b.capH
	b.pooled.reshape 2 * NUM_TRIS, b.p.columns		// restore for the next call
	b.capH.relu
	b.capH.gemm w.cap2W, w.cap2B, b.cap

	place = b.place.getColumn(0)
	logits = [NEG]
	for i in range(1, triangoBoard.NUM_POINTS)
		logits.push place[pointCell[i]]
	end for
	logits += b.cap.getColumn(0)

	// Value head: 1x1 conv, relu, flatten; dense layer over that plus the
	// mean trunk features; relu; dense to the 4 seats.
	vc = b.v.columns
	b.h.gemm w.vConvW, w.vConvB, b.v
	b.v.relu
	b.v.reshape 1, NUM_CELLS * vc					// O(1); cell-major, as exported
	w.vMean.gemm b.h, null, b.g
	b.g.gemm w.vFc1Wg, w.vFc1B, b.vh
	b.v.gemm w.vFc1Wv, b.vh, b.vh
	b.v.reshape NUM_CELLS, vc
	b.vh.relu
	b.vh.gemm w.vFc2W, w.vFc2B, b.value
	for k in range(numPlayers, b.value.columns - 1, 1)
		b.value.setElem 0, k, NEG
	end for
	valueLogits = b.value.getRow(0)
	b.value.softmax

	return {"logits": logits, "valueLogits": valueLogits, "values": b.value.getRow(0)}
end function


// Encode and evaluate a position.
evaluateState = function(state)
	return self.evaluate(self.encode(state), state.players.len)
end function


// The policy's probabilities for the given legal actions (a softmax over
// just those logits), as a list in the same order.
priors = function(logits, legal)
	if not legal then return []
	vals = []
	for a in legal
		vals.push logits[a]
	end for
	return Matrix.fromList([vals]).softmax.getRow(0)
end function


// The legal action the raw policy likes best (no search), or null if there
// are no legal actions.
bestAction = function(state)
	legal = triangoBoard.legalActions(state)
	if not legal then return null
	logits = self.evaluateState(state).logits
	best = legal[0]
	for a in legal
		if logits[a] > logits[best] then best = a
	end for
	return best
end function
