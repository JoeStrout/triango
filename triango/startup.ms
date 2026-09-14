clear
print "Welcome to Triango!"
print
print "This is a work in progress."
print
while true
	qtyPlayers = input("Enter number of players (2-4; you are Red): ").val
	if 2 <= qtyPlayers <= 4 then break
end while

run "triango"
