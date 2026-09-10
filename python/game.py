"""TrianGO game state and rules.

Rules (from the manual), as implemented here:

  * Each player starts with 14 stones in hand.  Turns go in order
    Red, Blue, Green, White (clockwise), using only as many as are playing.
  * A turn is either placing a stone from your hand on an empty point, or
    capturing one of your full triangles.
  * Perimeter rules, per player: on each perimeter (double line) you may
    occupy one end, both ends, or only the center -- never the center plus
    an end.  And you may have at most 6 stones on perimeter points in total.
  * A triangle is three of your stones at the corners of an equilateral
    triangle whose sides run along board lines, with side length >= 2
    (so it covers at least 6 points).  It is "full" if any opponent stone
    is inside it or on its border, and only full triangles can be captured.
  * Capturing removes every stone inside and on the border of the triangle
    (corners included).  Your own stones go back to your hand; opponent
    stones are out of the game for good.
  * A player with no legal move on their turn is skipped.  The game ends as
    soon as at most one player is able to move; that player wins (or, if
    nobody can move, the player who just moved wins).  In a two-player game
    this means you lose when you cannot move on your turn.

Actions are ints: 1-55 place a stone on that point; CAPTURE_BASE + k
captures TRIANGLES[k].  (0 is unused.)
"""

from board import (
    BIT, EMPTY, NUM_POINTS, PERIMETER_CONFLICT, PERIMETER_MASK,
    MAX_PERIMETER_STONES, PLAYERS, PLAYER_NAMES, STONES_PER_PLAYER,
    TRIANGLES, Board, popcount,
)

CAPTURE_BASE = NUM_POINTS + 1
NUM_ACTIONS = CAPTURE_BASE + len(TRIANGLES)


def is_capture(action):
    return action >= CAPTURE_BASE


def capture_action(tri):
    return CAPTURE_BASE + tri.index


def action_triangle(action):
    return TRIANGLES[action - CAPTURE_BASE]


def action_str(action):
    if is_capture(action):
        return "C" + action_triangle(action).name()
    return str(action)


class IllegalMove(Exception):
    pass


class GameState:
    def __init__(self, num_players=2, first_player=PLAYERS[0]):
        if not 2 <= num_players <= 4:
            raise ValueError("TrianGO is for 2 to 4 players")
        self.players = PLAYERS[:num_players]
        if first_player not in self.players:
            raise ValueError(f"{first_player} is not playing")
        self.board = Board()
        # The following are indexed by player (index 0 unused).
        self.masks = [0] * 5       # bitmask of each player's stones on the board
        self.hand = [0] * 5        # stones available to place
        self.captured = [0] * 5    # opponent stones this player has captured
        self.lost = [0] * 5        # this player's stones captured by opponents
        for p in self.players:
            self.hand[p] = STONES_PER_PLAYER
        self.to_move = first_player  # None once the game is over
        self.winner = None
        self.last_mover = None
        self.passed = []           # players skipped (unable to move) after the last move
        self.num_moves = 0

    @classmethod
    def from_board(cls, board, num_players=2, to_move=PLAYERS[0], hand=None):
        """Set up a position (for testing).  By default each player's hand
        is 14 minus their stones on the board; pass hand={player: n} to
        override."""
        s = cls(num_players, to_move)
        for i in range(1, NUM_POINTS + 1):
            p = board[i]
            if p == EMPTY:
                continue
            if p not in s.players:
                raise ValueError(f"{PLAYER_NAMES[p]} is not playing")
            s.board.points[i] = p
            s.masks[p] |= BIT[i]
            s.hand[p] -= 1
        if hand:
            for p, n in hand.items():
                s.hand[p] = n
        return s

    @classmethod
    def from_string(cls, board_str, num_players=2, to_move=PLAYERS[0], hand=None):
        return cls.from_board(Board.from_string(board_str), num_players, to_move, hand)

    def copy(self):
        s = GameState.__new__(GameState)
        s.players = self.players
        s.board = self.board.copy()
        s.masks = self.masks[:]
        s.hand = self.hand[:]
        s.captured = self.captured[:]
        s.lost = self.lost[:]
        s.to_move = self.to_move
        s.winner = self.winner
        s.last_mover = self.last_mover
        s.passed = self.passed[:]
        s.num_moves = self.num_moves
        return s

    # ----- queries -----

    @property
    def is_over(self):
        return self.winner is not None

    def occupied_mask(self):
        m = 0
        for p in self.players:
            m |= self.masks[p]
        return m

    def stones_on_board(self, player):
        return popcount(self.masks[player])

    def perimeter_count(self, player):
        return popcount(self.masks[player] & PERIMETER_MASK)

    def placement_error(self, point, player=None):
        """Return why player may not place at point, or None if they may."""
        p = self.to_move if player is None else player
        if not (isinstance(point, int) and 1 <= point <= NUM_POINTS):
            return f"{point} is not a point on the board"
        if self.board[point] != EMPTY:
            return f"point {point} is occupied"
        if self.hand[p] == 0:
            return f"{PLAYER_NAMES[p]} has no stones left to place"
        if PERIMETER_MASK & BIT[point]:
            if self.masks[p] & PERIMETER_CONFLICT[point]:
                return "a perimeter may not have your stones on both its center and an end"
            if self.perimeter_count(p) >= MAX_PERIMETER_STONES:
                return f"you already have {MAX_PERIMETER_STONES} stones on perimeters"
        return None

    def legal_placements(self, player=None):
        p = self.to_move if player is None else player
        if self.hand[p] == 0:
            return []
        own = self.masks[p]
        occupied = self.occupied_mask()
        perimeter_full = self.perimeter_count(p) >= MAX_PERIMETER_STONES
        result = []
        for i in range(1, NUM_POINTS + 1):
            b = BIT[i]
            if occupied & b:
                continue
            if PERIMETER_MASK & b and (perimeter_full or own & PERIMETER_CONFLICT[i]):
                continue
            result.append(i)
        return result

    def triangles(self, player):
        """All of player's triangles, as a list of (Triangle, is_full)."""
        own = self.masks[player]
        opp = self.occupied_mask() & ~own
        return [(t, bool(t.mask & opp)) for t in TRIANGLES
                if own & t.corner_mask == t.corner_mask]

    def full_triangles(self, player=None):
        p = self.to_move if player is None else player
        own = self.masks[p]
        opp = self.occupied_mask() & ~own
        return [t for t in TRIANGLES
                if own & t.corner_mask == t.corner_mask and t.mask & opp]

    def legal_actions(self, player=None):
        if self.is_over:
            return []
        p = self.to_move if player is None else player
        return self.legal_placements(p) + [capture_action(t) for t in self.full_triangles(p)]

    def has_legal_move(self, player):
        return bool(self.legal_placements(player) or self.full_triangles(player))

    # ----- making moves -----

    def play(self, action):
        """Apply action for the player to move (mutates this state)."""
        if self.is_over:
            raise IllegalMove("the game is over")
        p = self.to_move
        if is_capture(action):
            if not CAPTURE_BASE <= action < NUM_ACTIONS:
                raise IllegalMove(f"no such action: {action}")
            tri = action_triangle(action)
            if tri not in self.full_triangles(p):
                raise IllegalMove(f"{tri.name()} is not a full triangle of {PLAYER_NAMES[p]}")
            self._capture(p, tri)
        else:
            err = self.placement_error(action, p)
            if err:
                raise IllegalMove(err)
            self.board.points[action] = p
            self.masks[p] |= BIT[action]
            self.hand[p] -= 1
        self.last_mover = p
        self.num_moves += 1
        self._advance(p)

    def _capture(self, player, tri):
        for q in self.players:
            removed = self.masks[q] & tri.mask
            if not removed:
                continue
            n = popcount(removed)
            self.masks[q] &= ~removed
            if q == player:
                self.hand[q] += n
            else:
                self.captured[player] += n
                self.lost[q] += n
        for i in tri.points:
            self.board.points[i] = EMPTY

    def _advance(self, mover):
        movable = [q for q in self.players if self.has_legal_move(q)]
        self.passed = []
        if len(movable) <= 1:
            self.winner = movable[0] if movable else mover
            self.to_move = None
            return
        n = len(self.players)
        i = self.players.index(mover)
        for k in range(1, n + 1):
            q = self.players[(i + k) % n]
            if q in movable:
                self.to_move = q
                return
            self.passed.append(q)
