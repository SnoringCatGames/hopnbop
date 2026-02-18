class_name PlayerPortrayal
extends SubViewportContainer
## Renders a player's visual appearance for UI display.
## Contains a BunnyAnimator in a SubViewport, configured
## with the player's body type, costume, and outline
## color.


## The animation to play (e.g., "Rest", "Walk").
@export var default_animation: StringName = &"Rest"

var _animator: BunnyAnimator = null
var _viewport: SubViewport = null
var _outline_color := Color.WHITE


func _ready() -> void:
	_viewport = %SubViewport
	_animator = %Animator


## Configures the portrayal to match a player's
## appearance. Call after the scene is in the tree.
func apply_player_state(
	player_match_state: GamePlayerState,
) -> void:
	if not is_instance_valid(player_match_state):
		return
	if not is_instance_valid(_animator):
		return

	_outline_color = player_match_state.outline_color

	# Apply body type and costume.
	var body_type_index: int = \
		player_match_state.body_type_index
	var body_type_config: BodyTypeConfig = null
	if (body_type_index >= 0 and
			body_type_index < \
				G.settings.body_types.size()):
		body_type_config = \
			G.settings.body_types[body_type_index]

	var costume_index: int = \
		player_match_state.costume_index
	var costume_config: CostumeConfig = null
	if (costume_index >= 0 and
			costume_index < \
				G.settings.costumes.size()):
		costume_config = \
			G.settings.costumes[costume_index]

	_animator.apply_appearance(
		body_type_config, costume_config)

	# Store crown costume for later toggling.
	if is_instance_valid(G.settings.crown_costume):
		_animator.set_crown_costume(
			G.settings.crown_costume)

	# Apply outline color.
	_apply_outline_color()

	# Play default animation.
	_animator.play(default_animation)


## Stops the animation and restarts it after a delay.
func play_after_delay(delay: float) -> void:
	if not is_instance_valid(_animator):
		return
	_animator.stop()
	get_tree().create_timer(delay).timeout.connect(
		func():
			if is_instance_valid(_animator):
				_animator.play(default_animation))


## Shows or hides the crown overlay.
func set_crown_visible(p_is_visible: bool) -> void:
	if is_instance_valid(_animator):
		_animator.set_crown_visible(p_is_visible)


func _apply_outline_color() -> void:
	# Apply outline to the CanvasGroup so the shader
	# sees the combined silhouette of all layers.
	var group := _animator.outline_group
	if not is_instance_valid(group):
		return
	if not is_instance_valid(group.material):
		return

	group.material = group.material.duplicate()
	var shader_material := \
		group.material as ShaderMaterial
	if not is_instance_valid(shader_material):
		return

	shader_material.set_shader_parameter(
		"outline_color", _outline_color)
	shader_material.set_shader_parameter(
		"outline_width", 1.0)
	shader_material.set_shader_parameter(
		"outline_enabled", true)
