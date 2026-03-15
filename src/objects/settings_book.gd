class_name SettingsBook
extends Node2D


@export var _side_panel_manager_scene: PackedScene

# Dictionary<Player, bool> — players inside the
# area that have not yet triggered the menu.
var _pending_players := {}

var _badge_dot: Sprite2D
var _badge_tween: Tween


func _ready() -> void:
	_create_badge_dot()
	G.friends_notification_poller\
		.unseen_count_changed.connect(
			_on_unseen_count_changed)
	_on_unseen_count_changed(
		G.friends_notification_poller.unseen_count)


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
	G.side_panel_layer.add_child(mgr)
	mgr.open(player)
	mgr.closed.connect(
		_on_settings_panel_closed)


func _on_settings_panel_closed() -> void:
	G.is_settings_ui_shown = false
	G.settings_ui_player = null


func _create_badge_dot() -> void:
	# Create a small red circle texture for the
	# notification badge.
	var size := 5
	var image := Image.create(
		size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(
		size / 2.0, size / 2.0)
	var radius := size / 2.0
	for x in size:
		for y in size:
			var dist := Vector2(x, y)\
				.distance_to(center)
			if dist <= radius:
				image.set_pixel(
					x, y,
					Color(0.9, 0.15, 0.15, 1.0))
			else:
				image.set_pixel(
					x, y, Color(0, 0, 0, 0))

	var texture := ImageTexture\
		.create_from_image(image)
	_badge_dot = Sprite2D.new()
	_badge_dot.texture = texture
	_badge_dot.position = Vector2(14, -14)
	_badge_dot.visible = false
	_badge_dot.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST)
	add_child(_badge_dot)


func _on_unseen_count_changed(
	count: int,
) -> void:
	if not is_instance_valid(_badge_dot):
		return
	if count > 0:
		_badge_dot.visible = true
		_start_pulse_tween()
	else:
		_badge_dot.visible = false
		_stop_pulse_tween()


func _start_pulse_tween() -> void:
	_stop_pulse_tween()
	_badge_tween = create_tween()
	_badge_tween.set_loops()
	_badge_tween.tween_property(
		_badge_dot, "scale",
		Vector2(1.4, 1.4), 0.5)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	_badge_tween.tween_property(
		_badge_dot, "scale",
		Vector2(1.0, 1.0), 0.5)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)


func _stop_pulse_tween() -> void:
	if _badge_tween != null:
		_badge_tween.kill()
		_badge_tween = null
	if is_instance_valid(_badge_dot):
		_badge_dot.scale = Vector2(1.0, 1.0)
