// A "Bucket" is a supply of stones for a particular player (plus
// any captured opponent stones, just for fun).  It'd be more proper
// to call it a "bowl," but "bucket" is more fun to say.

import "qa"

globals.Bucket = {}
Bucket.left = 0
Bucket.bottom = 0
Bucket.width = 122
Bucket.height = 300
Bucket.player = 1
Bucket.myStones = null
Bucket.prisoners = null

Bucket.draw = function
	g = boardDisp
	g.fillRect self.left, self.bottom, self.width, self.height, "#88888844"
	g.drawRect self.left, self.bottom, self.width, self.height, 
	  StoneSprite.tints[self.player], 2	
end function

Bucket.init = function
	self.myStones = []
	self.prisoners = []
	self.draw
	for i in range(0, 13)
		sp = new StoneSprite
		sp.tint = StoneSprite.tints[self.player]
		self.holdStone sp
	end for
end function

Bucket.holdStone = function(stone, isMine=true)
	if isMine then
		qa.assert stone.tint == StoneSprite.tints[self.player]
	else
		qa.assert stone.tint != StoneSprite.tints[self.player]
	end if
	
	stone.x = self.left + 32 + 60*(not isMine)
	if isMine then stones = self.myStones else stones = self.prisoners
	stone.y = self.bottom + 32 + (self.height-50)/14 * stones.len
	// ToDo: deal with case where we have more than 14 prisoners!
	stone.scale = [1, 0.75]
	stones.push stone
	sprites.removeVal stone
	sprites.push stone
	
	for s in self.myStones
		qa.assert s.x == self.left + 32
		qa.assert s.tint == StoneSprite.tints[self.player]
	end for
	for s in self.prisoners
		qa.assert s.x == self.left + 32 + 60
		qa.assert s.tint != StoneSprite.tints[self.player]
	end for
end function

Bucket.isEmpty = function
	return not self.myStones
end function

Bucket.playStone = function(posIndex)
	stone = self.myStones.pop
	stone.scale = 1
	stone.x = boardUtil.xForIndex(posIndex)
	stone.y = boardUtil.yForIndex(posIndex)
	return stone
end function
