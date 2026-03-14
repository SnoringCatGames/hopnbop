class_name SettingsBook
extends Node2D


@export var _side_panel_manager_scene: PackedScene

# Dictionary<Player, bool> — players inside the
# area that have not yet triggered the menu.
var _pending_players := {}


func _physics_process(_delta: float) -> void:
	for player in _pending_players:
		if (
			is_instance_valid(player)
			and player.surfaces.is_attaching_to_floor
		):
			_show_settings_ui(player)


func _on_area_2d_body_entered(body: Node2D) -> void:
	if not Netcode.ensure(body is Player):
		return
	_pending_players[body] = true
	if body.surfaces.is_attaching_to_floor:
		_show_settings_ui(body)


func _on_area_2d_body_exited(body: Node2D) -> void:
	if not Netcode.ensure(body is Player):
		return
	_pending_players.erase(body)


func _show_settings_ui(player: Player) -> void:
	if G.is_settings_ui_shown:
		return

	# Remove from pending so the menu cannot
	# re-trigger while the player stays in the area.
	# They must leave and re-enter to open again.
	_pending_players.erase(player)

	G.is_settings_ui_shown = true
	G.settings_ui_player = player

	var mgr: SidePanelManager = (
		_side_panel_manager_scene.instantiate())
	get_tree().root.add_child(mgr)
	mgr.open(player)
	mgr.closed.connect(
		_on_settings_panel_closed)


func _on_settings_panel_closed() -> void:
	G.is_settings_ui_shown = false
	G.settings_ui_player = null
