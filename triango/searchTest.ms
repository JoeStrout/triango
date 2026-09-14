// searchTest.ms
//
// Checks lib/TriangoMCTS.ms against Python MCTS searches (the "search" lines
// of rules_ref.txt, written by rl_triango/export_rules_ref.py --ckpt): from
// the same positions, with the same number of simulations, the root visit
// counts should match.  (The networks agree to about 1e-5, so an occasional
// near-tie can go the other way and shift a visit or two.)  Then plays one
// quick game of the net against itself, to time a full search.

import "importUtil"
ensureImport "triangoBoard"
ensureImport "triangoGame"
ensureImport "TriangoNet"
ensureImport "TriangoMCTS"

dataPath = function(name)
	if env.hasIndex("MS_SCRIPT_DIR") then
		p = file.child(env.MS_SCRIPT_DIR, name)
		if file.exists(p) then return p
	end if
	return name
end function

ints = function(s)
	result = []
	for w in s.split(" ")
		if w != "" then result.push w.val
	end for
	return result
end function

net = TriangoNet.load
if net isa error then
	print net
	exit 1
end if
TriangoMCTS.net = net

// Collect the games (as action lists) and the reference searches.
games = []
searches = []
for line in file.readLines(dataPath("rules_ref.txt"))
	if line.indexOf("game ") == 0 then
		games.push {"players": line[5:].val, "actions": []}
	else if line.indexOf("ply ") == 0 then
		a = line[4:].split("|")[0].val
		if a then games[-1].actions.push a
	else if line.indexOf("search ") == 0 then
		f = line[7:].split("|")
		searches.push {"where": ints(f[0]), "actions": ints(f[1]), "visits": ints(f[2])}
	end if
end for
if not searches then
	print "No reference searches in rules_ref.txt (export it with --ckpt)."
	exit 1
end if

errors = 0
exact = 0
for s in searches
	gi = s.where[0]; ply = s.where[1]; sims = s.where[2]
	g = triangoGame.start(range(1, games[gi].players))
	for a in games[gi].actions[:ply]
		g.play a
	end for
	TriangoMCTS.sims = sims
	t0 = time
	TriangoMCTS.begin g
	TriangoMCTS.step null
	dt = time - t0
	counts = TriangoMCTS.visitCounts
	visits = []
	for a in s.actions
		if counts.hasIndex(a) then visits.push counts[a] else visits.push -1
	end for
	diff = 0
	for i in visits.indexes
		diff += abs(visits[i] - s.visits[i])
	end for
	note = "game " + gi + " ply " + ply + ": "
	if TriangoMCTS.root.actions.len != s.actions.len then
		print "FAIL " + note + "root has " + TriangoMCTS.root.actions.len +
		  " actions, expected " + s.actions.len
		errors += 1
	else if diff == 0 then
		exact += 1
		print note + "visit counts match (" + round(dt, 2) + " s, " +
		  TriangoMCTS.evals + " evals)"
	else
		print note + "visit counts differ by " + diff + " in total"
		print "    got      " + visits
		print "    expected " + s.visits
		if diff > sims / 4 then errors += 1
	end if
end for
print exact + " of " + searches.len + " searches match exactly."

// Time full-size searches over a short self-play game.
TriangoMCTS.sims = 100
g = triangoGame.start([1, 2])
t0 = time
moves = 0
while not g.isOver and moves < 6
	a = TriangoMCTS.search(g)
	print "  " + g.toMove + " plays " + triangoGame.actionStr(a) +
	  " (win prob " + round(TriangoMCTS.rootValue, 3) + ")"
	g.play a
	moves += 1
end while
print "Average " + round((time - t0) / moves, 2) + " s per 100-simulation move"

if errors == 0 then
	print "All checks passed."
else
	print errors + " check" + "s" * (errors != 1) + " failed."
end if
exit errors > 0
