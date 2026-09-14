// netTest.ms
//
// Checks lib/TriangoNet.ms and lib/triangoBoard.ms against the reference
// positions and outputs that rl_triango/export_msmx.py writes alongside the
// weights (az_triango_ref.json): the cell layout, seats, legal actions, input
// planes, policy logits, and value.  Run with raylib-miniscript:
//
//     raylib-miniscript netTest.ms

import "importUtil"
ensureImport "json"
ensureImport "triangoBoard"
ensureImport "TriangoNet"

errors = 0
check = function(ok, note)
	if ok then return
	print "FAIL: " + note
	globals.errors = errors + 1
end function

maxAbsDiff = function(a, b)
	worst = 0
	for i in a.indexes
		d = abs(a[i] - b[i])
		if d > worst then worst = d
	end for
	return worst
end function

t0 = time
ref = json.parse(file.loadRaw(file.child(env.MS_SCRIPT_DIR, "az_triango_ref.json")))
print "Parsed reference data in " + round(time - t0, 2) + " s"

// Geometry and layout.
check triangoBoard.triangles.len == ref.num_actions - triangoBoard.CAPTURE_BASE, "triangle count"
check TriangoNet.HEX_OFFSETS == ref.hex_offsets, "hex offsets"
check TriangoNet.NUM_CELLS == ref.num_cells, "cell count"
check TriangoNet.cells == ref.cells, "cells"
check TriangoNet.rowSpans == ref.row_spans, "row spans"
check TriangoNet.pointCell[1:] == ref.point_rows, "point rows"
check TriangoNet.onBoard == ref.on_board, "on-board mask"

t0 = time
net = TriangoNet.load
if net isa error then
	print net
	exit 1
end if
print "Loaded weights in " + round(time - t0, 2) + " s"
print

tol = 1e-3
worst = {"planes": 0, "logits": 0, "values": 0}
encodeTime = 0
evalTime = 0
for idx in ref.positions.indexes
	pos = ref.positions[idx]
	note = "position " + idx

	players = range(1, pos.num_players)
	hand = {}
	for p in players
		hand[p] = pos.hand[p - 1]
	end for
	state = {"board": [0] + pos.board, "hand": hand, "players": players, "toMove": pos.to_move}

	check triangoBoard.seats(state) == pos.seats, note + ": seats"
	legal = triangoBoard.legalActions(state)
	legal.sort
	check legal == pos.legal, note + ": legal actions"

	t0 = time
	x = net.encode(state)
	encodeTime += time - t0
	d = 0
	for k in pos.planes.indexes
		plane = pos.planes[k]
		for i in plane.indexes
			e = abs(x.getElem(TriangoNet.pointCell[i + 1], k) - plane[i])
			if e > d then d = e
		end for
	end for
	check d < 1e-5, note + ": planes differ by " + d
	if d > worst.planes then worst.planes = d

	t0 = time
	out = net.evaluate(x, pos.num_players)
	evalTime += time - t0
	dl = maxAbsDiff(out.logits, pos.logits)
	dv = maxAbsDiff(out.valueLogits, pos.value_logits)
	dp = maxAbsDiff(out.values, pos.value_probs)
	check dl < tol, note + ": logits differ by " + dl
	check dv < tol and dp < tol, note + ": value differs by " + dv + " (logits), " + dp + " (probs)"
	if dl > worst.logits then worst.logits = dl
	if dv > worst.values then worst.values = dv

	probs = []
	for v in out.values[:pos.num_players]
		probs.push round(v, 3)
	end for
	print note + ": " + pos.num_players + " players, " + pos.moves.len + " moves, " +
	  legal.len + " legal; seat win probs " + probs + "; best action " +
	  net.bestAction(state)
end for

n = ref.positions.len
print
print "Max diffs: planes " + worst.planes + ", logits " + worst.logits +
  ", value logits " + worst.values
print "Average time: encode " + round(1000 * encodeTime / n, 1) + " ms, evaluate " +
  round(1000 * evalTime / n, 1) + " ms"
if errors == 0 then
	print "All checks passed."
else
	print errors + " check" + "s" * (errors != 1) + " failed."
end if
exit errors > 0
