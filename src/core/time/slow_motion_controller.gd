@tool
class_name SlowMotionController
extends Node
## -   Controls slow-motion.


signal slow_motion_toggled(is_enabled)

const GROUP_NAME_SLOW_MOTIONABLES := "slow_motionables"

const ENABLE_SLOW_MOTION_DURATION := 0.3
const DISABLE_SLOW_MOTION_DURATION := 0.2

var is_enabled := false:
    set(value): set_slow_motion_enabled(value)

var is_transitioning := false

var default_time_scale := 0.1
var gui_mode_time_scale := 0.02
var time_scale := default_time_scale
var tick_tock_tempo_multiplier := 25.0

var _slow_motionable_animators := []

var _tween: ScaffolderTween


func _init() -> void:
    _tween = ScaffolderTween.new(self)


func _parse_manifest(manifest: Dictionary) -> void:
    if manifest.has("default_time_scale"):
        self.default_time_scale = manifest.default_time_scale
        self.time_scale = default_time_scale
    if manifest.has("gui_mode_time_scale"):
        self.gui_mode_time_scale = manifest.gui_mode_time_scale


func set_slow_motion_enabled(value: bool) -> void:
    if value == is_enabled:
        # No change.
        return

    is_enabled = value
    is_transitioning = true

    _tween.stop_all()

    var next_time_scale: float
    var time_scale_duration: float
    var ease_name: String
    if is_enabled:
        next_time_scale = time_scale
        time_scale_duration = ENABLE_SLOW_MOTION_DURATION
        ease_name = "ease_in"
    else:
        next_time_scale = 1.0
        time_scale_duration = DISABLE_SLOW_MOTION_DURATION
        ease_name = "ease_out"

    # Update time scale.
    _tween.interpolate_method(
            self,
            "_set_time_scale",
            G.time.time_scale,
            next_time_scale,
            time_scale_duration,
            ease_name,
            0.0,
            TimeType.PLAY_PHYSICS)

    _tween.start()

    emit_signal("slow_motion_toggled", is_enabled)



func _get_time_scale() -> float:
    return G.time.time_scale


func _set_time_scale(value: float) -> void:
    # Update the main time_scale.
    G.time.time_scale = value

    # TODO: Remove this class?

    ## Update ScaffolderCharacterAnimators.
    #for animator in _slow_motionable_animators:
        #animator.match_rate_to_time_scale()
#
    #var slow_motionables: Array = \
        #Sc.utils.get_all_nodes_in_group(GROUP_NAME_SLOW_MOTIONABLES)
    #for node in slow_motionables:
        #if node is AnimatedSprite:
            #if !node.has_meta("non_slow_motion_speed_scale"):
                #node.set_meta("non_slow_motion_speed_scale", node.speed_scale)
            #node.speed_scale = \
                    #node.get_meta("non_slow_motion_speed_scale") * \
                    #G.time.time_scale
        #elif node is AnimationPlayer:
            #if !node.has_meta("non_slow_motion_speed_scale"):
                #node.set_meta("non_slow_motion_speed_scale", node.playback_speed)
            #node.playback_speed = \
                    #node.get_meta("non_slow_motion_speed_scale") * \
                    #G.time.time_scale
        #else:
            #push_error("SlowMotionController._set_time_scale")


func set_time_scale_for_node(node: Node) -> void:
    # TODO: Remove this class?

    pass

    #if node.has_method("match_rate_to_time_scale"):
        #node.match_rate_to_time_scale()
    #elif node is AnimatedSprite:
        #if !node.has_meta("non_slow_motion_speed_scale"):
            #node.set_meta("non_slow_motion_speed_scale", node.speed_scale)
        #node.speed_scale = \
                #node.get_meta("non_slow_motion_speed_scale") * \
                #G.time.time_scale
    #elif node is AnimationPlayer:
        #if !node.has_meta("non_slow_motion_speed_scale"):
            #node.set_meta("non_slow_motion_speed_scale", node.playback_speed)
        #node.playback_speed = \
                #node.get_meta("non_slow_motion_speed_scale") * \
                #G.time.time_scale
    #else:
        #push_error("SlowMotionController._set_time_scale")


func _on_music_transition_complete(is_active: bool) -> void:
    is_transitioning = false


func get_is_enabled_or_transitioning() -> bool:
    return is_enabled or is_transitioning


func add_animator(animator: Node2D) -> void:
    _slow_motionable_animators.push_back(animator)
    set_time_scale_for_node(animator)


func remove_animator(animator: Node2D) -> void:
    _slow_motionable_animators.erase(animator)
