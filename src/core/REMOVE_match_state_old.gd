class_name MatchStateOld
extends RefCounted


signal players_updated
signal kills_updated
signal bumps_updated


## - We maintain both an Array of players as well as a redundant Dictionary of
##   players.
## - The Array is used for replicating state more efficiently from the server.
## - The Dictionary is then derived from the Array, and is used for more
##   efficient local look-ups.
var players: Array[PlayerMatchState] = []:
    set(value):
        players = value
        players_updated.emit()
# Dictionary<int, PlayerMatchState>
var players_by_id: Dictionary = {}

## Every even index marks a 2-player pair.
##
## Every even index is the killer, and every odd index is the killee for the
## prior index.
var kills: PackedInt32Array = []:
    set(value):
        kills = value
        kills_updated.emit()

## A bump happens when two bunnies collide, but neither dies.
##
## Every even index marks a 2-player pair.
var bumps: PackedInt32Array = []:
    set(value):
        bumps = value
        bumps_updated.emit()


func clear() -> void:
    players.clear()
    players_by_id.clear()
    kills.clear()
    bumps.clear()


func duplicate() -> MatchStateOld:
    var copy := MatchStateOld.new()
    copy.players = players.duplicate()
    copy.players_by_id = players_by_id.duplicate()
    copy.kills = kills.duplicate()
    copy.bumps = bumps.duplicate()
    return copy
