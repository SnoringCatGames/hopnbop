class_name PlayerDisplay
extends VBoxContainer
## Individual player info panel showing adjective, name, and score.


var player_id: int = 0


func set_player_id(p_player_id: int) -> void:
	player_id = p_player_id


func _process(_delta: float) -> void:
	_update_display()


func _update_display() -> void:
	if player_id == 0:
		return

	var player_match_state := G.get_player_match_state(player_id)
	if not player_match_state:
		return

	# Update name.
	%Name.text = player_match_state.bunny_name

	# Placeholder adjective and score (will be added to PlayerMatchState later).
	%Adjective.text = "Brave"
	%Score.text = "Score: 0"
