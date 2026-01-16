class_name NPC
extends Character


func _enter_tree() -> void:
    super._enter_tree()
    G.level.on_npc_added(self)


func _exit_tree() -> void:
    super._exit_tree()
    G.level.on_npc_removed(self)


func _ready() -> void:
    super._ready()


func _network_process() -> void:
    super._network_process()


func _update_actions() -> void:
    if is_multiplayer_authority():
        # TODO: Add support for NPC actions.
        #super._update_actions()
        pass
    else:
        # Don't update actions per-frame. Instead, actions are updated when
        # networked state is replicated.
        pass
