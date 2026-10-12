extends SceneTree
## Agent harness entry point: the `-s` main-loop script that
## scripts/agent/run-game.ps1 hands to each Godot process.
##
## This script must not name an autoload (G, Netcode, Platform). Godot
## compiles a `-s` script before it registers the autoload globals, so
## naming one is a compile error. All game access lives in
## agent_driver.gd, which this script loads once the globals exist.
##
## Nothing under scripts/ is imported or exported (scripts/.gdignore).

const _DRIVER_PATH := "res://scripts/agent/agent_driver.gd"
const _EXIT_HARNESS_ERROR := 2


func _initialize() -> void:
	var driver_script: GDScript = load(_DRIVER_PATH)
	if driver_script == null:
		print(
			'AGENT_RESULT {"ok": false, "exit_code": 2,'
			+ ' "failures": [{"error": "agent_driver.gd failed to load"}]}'
		)
		quit(_EXIT_HARNESS_ERROR)
		return
	var driver: Node = driver_script.new()
	driver.name = "AgentDriver"
	# The autoloads are children of root but have not entered the tree
	# yet, so configure() lands its settings overrides and the offline
	# Platform config before G._enter_tree and G._ready read them.
	driver.call("configure")
	root.add_child(driver)


func _finalize() -> void:
	# Works around a crash on exit (0xC0000005) in every preview-mode
	# process. rollback_netcode's PerfTracker registers Performance
	# custom monitors backed by lambdas and never removes them, and the
	# engine evidently frees those callables after GDScript has shut
	# down. Removing them here, while GDScript is still alive, keeps the
	# exit code meaningful. A no-op once PerfTracker cleans up after
	# itself.
	for monitor_id in Performance.get_custom_monitor_names():
		Performance.remove_custom_monitor(monitor_id)
