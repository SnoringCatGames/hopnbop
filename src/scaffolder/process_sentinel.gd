class_name ProcessSentinel
extends Node


signal pre_physics_process(delta: float)
signal post_physics_process(delta: float)
signal pre_process(delta: float)
signal post_process(delta: float)



var _pre_process_sentinel: _ProcessSentinelHelper
var _post_process_sentinel: _ProcessSentinelHelper


func _ready() -> void:
    var root := get_tree().root

    # Godot traverses the scene tree in pre-order traversal, so we place both
    # sentinel helper at the top layer, with one as the first child and one as
    # the last.

    _pre_process_sentinel = _ProcessSentinelHelper.new()
    _pre_process_sentinel.name = "PreProcessSentinel"
    _pre_process_sentinel.process_priority = Utils.MIN_INT
    _pre_process_sentinel.connect("physics_processed", _pre_physics_process)
    _pre_process_sentinel.connect("processed", _pre_process)
    root.add_child.call_deferred(_pre_process_sentinel)
    root.move_child.call_deferred(_pre_process_sentinel, 0)

    _post_process_sentinel = _ProcessSentinelHelper.new()
    _pre_process_sentinel.name = "PostProcessSentinel"
    _pre_process_sentinel.process_priority = Utils.MAX_INT
    _post_process_sentinel.connect("physics_processed", _post_physics_process)
    _post_process_sentinel.connect("processed", _post_process)
    root.add_child.call_deferred(_post_process_sentinel)


func _pre_physics_process(delta: float) -> void:
    pre_physics_process.emit(delta)


func _post_physics_process(delta: float) -> void:
    post_physics_process.emit(delta)


func _pre_process(delta: float) -> void:
    pre_process.emit(delta)


func _post_process(delta: float) -> void:
    post_process.emit(delta)


class _ProcessSentinelHelper extends Node:
    signal physics_processed(delta: float)
    signal processed(delta: float)


    func _physics_process(delta: float) -> void:
        physics_processed.emit(delta)

    func _process(delta: float) -> void:
        processed.emit(delta)
