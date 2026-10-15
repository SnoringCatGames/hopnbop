extends Node
## H37 probe recorder (h37-verify item 4d). Not part of the game. The
## scenario connects it to the matchmaking socket's signals and prints
## one line per event, so the run log shows what the socket received.

var count := 0


func on_note(n) -> void:
	count += 1
	print("H37REC note %d code=%s subject=%s persistent=%s" % [
		count, str(n.code), str(n.subject), str(n.persistent)])


func on_party_presence(p) -> void:
	print("H37REC party_presence %s" % str(p))


func on_closed() -> void:
	print("H37REC socket closed")