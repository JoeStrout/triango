# TrianGO in Python

Rules engine, terminal game, and neural-network plumbing for TrianGO.
Requires Python 3.10+; `encode.py` also needs numpy.

| File | Purpose |
|---|---|
| `board.py` | Geometry (points, neighbors, perimeters, triangles, symmetries, 9×9 grid) and terminal rendering |
| `game.py` | `GameState`: rules, legal actions, playing moves |
| `encode.py` | Network input encoding, legal-action masks, value targets, symmetry transforms |
| `play.py` | Play in the terminal: `python3 play.py -n 2 -r B` (Blue moves randomly) |
| `bench.py` | Move-generation benchmark with behavior checksums (`--save`, `--compare`, `--profile`) |
| `test_*.py` | Tests: `python3 -m unittest` |

## Shared contract

Code on every machine (search, self-play, training) must agree on these.

**Points** are numbered 1–55, row by row from the top, as in Figure 4 of the
manual. Point 28 is the center.

**Players** are `RED=1, BLUE=2, GREEN=3, WHITE=4`, moving in that order; a
game with *n* players uses the first *n*.

**Actions** are ints in `range(NUM_ACTIONS)`, with `NUM_ACTIONS = 192`:
- `0` is unused and never legal.
- `1`–`55` place a stone on that point.
- `56 + k` (`CAPTURE_BASE + k`) captures triangle `board.TRIANGLES[k]`.

The order of `TRIANGLES` (136 of them) is part of the contract; don't
change `board._build_triangles` without retraining.

**Symmetries**: the board has 12 (six rotations about point 28 and six
reflections). `board.POINT_PERM[s][i]` is where point `i` goes under
symmetry `s`; `game.ACTION_PERM[s][a]` is where action `a` goes;
`GameState.transformed(s)` applies one to a whole state. For arrays,
`encode.transform_points`, `transform_grid`, and `transform_policy` do the
same. Index 0 is the identity.

**Network input** (`encode.py`, `ENCODING_VERSION = 1`): 28 planes over the
55 points, either in point form `(28, 55)` or on the 9×9 grid `(28, 9, 9)`.
Players are relative to the player to move (seat 0 = to move). Planes:
stones by seat, board/perimeter markers, legal placements, empty- and
full-triangle coverage by seat, stones in hand, perimeter counts, and which
seats are in play. See the docstring in `encode.py` for exact definitions.
In grid form, a point's six neighbors are the 3×3 neighborhood minus two
corners (`encode.HEX_KERNEL_MASK`).

**Value targets** are one-hot over the 4 seats, relative to the player to
move (`encode.value_target`).

## Rule interpretations

See the docstring at the top of `game.py`. In brief: capturing is optional
unless you have no stones to place; a player with no legal move is skipped;
the game ends when at most one player can move.
