class_name PlayerStatePanel
extends PanelContainer

## Definition for each stat row:
## [display_label, property_name, format].
## format: "int", "sec", or "float".
const _STAT_DEFS: Array[Array] = [
	["Kills", "kill_count", "int"],
	["Deaths", "death_count", "int"],
	["Bumps", "bump_count", "int"],
	["Jumps", "jump_count", "int"],
	["Crown", "crown_time_sec", "sec"],
	["Regicide", "regicide_count", "int"],
	["Springs", "spring_launch_count", "int"],
	["Water", "water_time_sec", "sec"],
	["W. Jumps", "water_jump_count", "int"],
	["Ice", "ice_time_sec", "sec"],
	["Dir Chgs", "direction_change_count", "int"],
	["Avg Hgt", "average_height", "float"],
]

@export var toast_scene: PackedScene
@export var toast_fade_duration := 0.5
@export var toast_fade_delay := 1.5
@export var show_extra_debug_info := false

var player_id: int = 0
var player: Player
var player_match_state: GamePlayerState
var replaceable_toast: PlayerStatePanelToast = null

# Maps property_name -> value Label node.
var _stat_value_labels := {}


func _ready() -> void:
	if Netcode.is_server:
		return

	_build_stats_ui()

	%IsDescendingThroughFloorsRow.visible = show_extra_debug_info
	#%IsAscendingThroughCeilingsRow.visible = show_extra_debug_info
	#%IsAttachingToWalkThroughWallsRow.visible = show_extra_debug_info
	%IsOnFloorRow.visible = show_extra_debug_info
	%IsOnCeilingRow.visible = show_extra_debug_info
	%IsOnWallRow.visible = show_extra_debug_info


func clear() -> void:
	%Actions.text = ""
	%Position.text = ""
	%Velocity.text = ""
	%AttachmentSide.text = ""


func _process(_delta: float) -> void:
	if Netcode.is_server:
		return
	if not is_visible_in_tree():
		return

	_update_stats_display()

	if not is_instance_valid(player):
		player = G.get_player(player_id)

	if not is_instance_valid(player):
		clear()
		return

	%Actions.text = CharacterActionState.get_debug_label_from_actions_bitmask(
		player.actions.current_actions_bitmask,
	)
	%Position.text = Utils.get_vector_string(player.position, 1)
	%Velocity.text = Utils.get_vector_string(player.velocity, 1)

	%AttachmentSide.text = SurfaceSide.get_string(player.surfaces.attachment_side)

	%IsDescendingThroughFloors.text = str(player.surfaces.is_descending_through_floors)
	#%IsAscendingThroughCeilings.text = str(player.surfaces.is_ascending_through_ceilings)
	#%IsAttachingToWalkThroughWalls.text = str(player.surfaces.is_attaching_to_walk_through_walls)

	%IsOnFloor.text = str(player.is_on_floor())
	%IsOnCeiling.text = str(player.is_on_ceiling())
	%IsOnWall.text = str(player.is_on_wall())


func _physics_process(_delta: float) -> void:
	if not is_visible_in_tree:
		return
	if not is_instance_valid(player):
		return

	if player.surfaces.just_changed_attachment_side:
		add_toast(
			"Attached to %s" %
			SurfaceSide.get_string(player.surfaces.attachment_side),
			true,
		)


func add_toast(text: String, replaceable: bool = false) -> void:
	# If this is a replaceable toast and we have an old one, remove it.
	if replaceable and is_instance_valid(replaceable_toast):
		replaceable_toast.queue_free()
		replaceable_toast = null

	var toast: PlayerStatePanelToast = toast_scene.instantiate()
	toast.text = text
	%Toasts.add_child(toast)
	%Toasts.move_child(toast, 0)

	# Cache this toast if it's replaceable.
	if replaceable:
		replaceable_toast = toast

	var tween = get_tree().create_tween()
	tween.tween_property(toast, "modulate:a", 0, toast_fade_duration).set_delay(toast_fade_delay)
	await tween.step_finished
	if is_instance_valid(toast):
		toast.queue_free()

	# Clear the cached reference if this was the replaceable toast.
	if replaceable and toast == replaceable_toast:
		replaceable_toast = null


func _build_stats_ui() -> void:
	for entry in _STAT_DEFS:
		var label_text: String = entry[0]
		var stat_key: String = entry[1]

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var name_label := Label.new()
		name_label.text = label_text + ": "
		name_label.size_flags_horizontal = \
			Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var value_label := Label.new()
		value_label.horizontal_alignment = \
			HORIZONTAL_ALIGNMENT_RIGHT
		value_label.text = "-"
		row.add_child(value_label)

		%StatsSection.add_child(row)
		_stat_value_labels[stat_key] = value_label


func _update_stats_display() -> void:
	var stats: PlayerMatchStats = \
		G.match_state.get_player_stats(player_id)
	if stats == null:
		for key in _stat_value_labels:
			_stat_value_labels[key].text = "-"
		return

	for entry in _STAT_DEFS:
		var stat_key: String = entry[1]
		var fmt: String = entry[2]
		var value = stats.get(stat_key)
		var label: Label = _stat_value_labels[stat_key]
		match fmt:
			"sec":
				label.text = "%.1fs" % value
			"float":
				label.text = "%.1f" % value
			_:
				label.text = str(value)
