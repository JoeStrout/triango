clear
print "Welcome to Triango!"
print
print "This is a work in progress."
print
while true
	qtyPlayers = input("Enter number of players (1-4): ").val
	if 1 <= qtyPlayers <= 4 then break
end while

run "triango"
