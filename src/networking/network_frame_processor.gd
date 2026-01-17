@tool
class_name NetworkFrameProcessor
extends Node
## This controls whether the node at root_path will have its _network_process
## method called during network frame simulations.


## _network_process will be called on this node during network frame
##  simulations.
@export var root_path: NodePath:
    set(value):
        root_path = value
        update_configuration_warnings()

var root: Node:
    get: return get_node_or_null(root_path)


func _enter_tree() -> void:
    if Engine.is_editor_hint():
        return
    G.network.frame_driver.add_network_frame_processor(self)


func _exit_tree() -> void:
    if Engine.is_editor_hint():
        return
    G.network.frame_driver.remove_network_frame_processor(self)


func _ready() -> void:
    # Auto-populate root_path when first placed in a scene.
    if Engine.is_editor_hint() and root_path.is_empty():
        root_path = self.get_path_to(owner)
    update_configuration_warnings()


func _network_process() -> void:
    root._network_process()


func _get_configuration_warnings() -> PackedStringArray:
    var warnings := []

    if root_path.is_empty():
        warnings.push_back("root_path must be defined")
    elif not is_instance_valid(root):
        warnings.push_back("root_path does not point to a valid node")
    elif not root.has_method("_network_process"):
        warnings.push_back(
            "The node at `Root Path` must have a `_network_process` method")

    return warnings
