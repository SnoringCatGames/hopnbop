@tool
class_name NPC
extends Character

func _enter_tree() -> void:
	super._enter_tree()
	G.level.register_npc(self)


func _exit_tree() -> void:
	super._exit_tree()
	G.level.deregister_npc(self)


func _ready() -> void:
	super._ready()


func _process_movement_and_actions() -> void:
	super._process_movement_and_actions()


func _collect_actions() -> void:
	if is_multiplayer_authority():
		# TODO: Add support for NPC actions.
		#super._collect_actions()
		pass
	else:
		# Don't update actions per-frame. Instead, actions are updated when
		# networked state is replicated.
		pass
