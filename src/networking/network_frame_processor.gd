@tool
class_name NetworkFrameProcessor
extends Node
## Helper node that enables any node to participate in frame-synchronous network
## processing.
##
## NetworkFrameProcessor acts as a bridge between NetworkFrameDriver and game
## logic nodes that need to run during network frame simulation but don't extend
## ReconcilableNetworkedState (i.e., they don't need to support server-mismatch
## detection and rollback).
##
## Usage pattern:
## 1. Add NetworkFrameProcessor as a child of your networked node
## 2. Set root_path to point to the node that implements _network_process()
## 3. NetworkFrameDriver will automatically call root._network_process() during
##	each network frame

## _network_process will be called on this node during network frame
##  simulations.
@export var root_path: NodePath:
    set(value):
        root_path = value
        update_configuration_warnings()

var root: Node:
    get:
        return get_node_or_null(root_path)


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
        warnings.append("root_path must be defined")
    elif not is_instance_valid(root):
        warnings.append("root_path does not point to a valid node")
    elif not root.has_method("_network_process"):
        warnings.append("The node at `Root Path` must have a `_network_process` method")

    return warnings
