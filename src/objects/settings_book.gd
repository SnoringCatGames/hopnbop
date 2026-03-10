class_name SettingsBook
extends Node2D


@export var _side_panel_manager_scene: PackedScene

const _REOPEN_COOLDOWN_SEC := 0.15

# Dictionary<Player, bool>
var intersecting_players := {}

var _last_closed_time := -INF


func _physics_process(_delta: float) -> void:
	for player in intersecting_players:
		if (
			is_instance_valid(player)
			and player.surfaces.just_attached_floor
		):
			_show_settings_ui(player)


func _on_area_2d_body_entered(body: Node2D) -> void:
	if not Netcode.ensure(body is Player):
		return
	intersecting_players[body] = true
	if body.surfaces.is_attaching_to_floor:
		_show_settings_ui(body)


func _on_area_2d_body_exited(body: Node2D) -> void:
	if not Netcode.ensure(body is Player):
		return
	intersecting_players.erase(body)


func _show_settings_ui(player: Player) -> void:
	# No-op if settings UI is already shown.
	if G.is_settings_ui_shown:
		return
	# No-op if closed too recently.
	var elapsed := (
		Time.get_ticks_msec() / 1000.0
		- _last_closed_time)
	if elapsed < _REOPEN_COOLDOWN_SEC:
		return
	G.is_settings_ui_shown = true
	G.settings_ui_player = player

	var mgr: SidePanelManager = (
		_side_panel_manager_scene.instantiate())
	get_tree().root.add_child(mgr)
	mgr.open(player)
	mgr.closed.connect(
		_on_settings_panel_closed)


func _on_settings_panel_closed() -> void:
	_last_closed_time = (
		Time.get_ticks_msec() / 1000.0)
	G.is_settings_ui_shown = false
	G.settings_ui_player = null
