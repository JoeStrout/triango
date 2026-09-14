// gameTest.ms
//
// Checks lib/triangoGame.ms against reference games from the Python rules
// (rules_ref.txt, written by rl_triango/export_rules_ref.py): after every
// ply, the board, hands, captures, player to move, winner, skipped players,
// and legal actions must all match.  Needs no network or display.

import "importUtil"
ensureImport "triangoBoard"
ensureImport "triangoGame"

// Find a data file next to this script, or in the current directory.
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

byPlayer = function(m)
	result = []
	for p in range(1, 4)
		if m.hasIndex(p) then result.push m[p] else result.push 0
	end for
	return result
end function

errors = 0
fail = function(note)
	print "FAIL: " + note
	globals.errors = errors + 1
end function

// Compare the game to one "ply" record; returns true if they match.
matches = function(g, fields, note)
	board = ""
	for i in range(1, triangoBoard.NUM_POINTS)
		board += str(g.board[i])
	end for
	toMove = g.toMove
	if toMove == null then toMove = 0
	winner = g.winner
	if winner == null then winner = 0
	legal = g.legalActions
	legal.sort
	got = [board, byPlayer(g.hand), byPlayer(g.captured), byPlayer(g.lost),
	  toMove, winner, g.passed, legal]
	want = [fields[1], ints(fields[2]), ints(fields[3]), ints(fields[4]),
	  fields[5].val, fields[6].val, ints(fields[7]), ints(fields[8])]
	names = ["board", "hand", "captured", "lost", "toMove", "winner", "passed", "legal"]
	ok = true
	for k in names.indexes
		if got[k] != want[k] then
			fail note + ": " + names[k] + " is " + got[k] + ", expected " + want[k]
			ok = false
		end if
	end for
	return ok
end function

t0 = time
lines = file.readLines(dataPath("rules_ref.txt"))
if lines == null then
	print "Cannot read rules_ref.txt"
	exit 1
end if

gameCount = 0
plyCount = 0
g = null
broken = false
for line in lines
	if line.indexOf("game ") == 0 then
		gameCount += 1
		g = triangoGame.start(range(1, line[5:].val))
		broken = false
		continue
	end if
	if line.indexOf("ply ") != 0 or broken then continue
	fields = line[4:].split("|")
	action = fields[0].val
	note = "game " + gameCount + ", ply " + g.numMoves
	if action != 0 then
		note += " (" + triangoGame.actionStr(action) + ")"
		e = g.play(action)
		if e != null then fail note + ": play says " + e
		plyCount += 1
	end if
	// After the first mismatch in a game, the rest of it is noise.
	if not matches(g, fields, note) then broken = true
end for

print gameCount + " games, " + plyCount + " plies replayed in " + round(time - t0, 2) + " s"
if errors == 0 then
	print "All checks passed."
else
	print errors + " check" + "s" * (errors != 1) + " failed."
end if
exit errors > 0
