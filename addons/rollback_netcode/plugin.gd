@tool
extends EditorPlugin
## Rollback Netcode plugin for Godot 4.x.
##
## This plugin provides client-side prediction with server reconciliation for
## multiplayer games. It implements frame-synchronous simulation with rollback
## buffer and NTP-like frame synchronization.


func _enter_tree() -> void:
	# Register NetworkOrchestrator as Netcode autoload.
	add_autoload_singleton("Netcode", "res://addons/rollback_netcode/core/network_orchestrator.gd")

	# Get version from plugin.cfg via static function.
	var NetcodeScript = preload("res://addons/rollback_netcode/core/network_orchestrator.gd")
	print("Rollback Netcode plugin v%s loaded" % NetcodeScript.get_version())


func _exit_tree() -> void:
	# Remove Netcode autoload.
	remove_autoload_singleton("Netcode")
	print("Rollback Netcode plugin unloaded")
