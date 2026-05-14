class_name ScreenFocusNavigator
extends PlatformScreenFocusNavigator
## Game-side focus navigator that auto-wires the
## focus-move sound callback against G.audio.
##
## Thin subclass of PlatformScreenFocusNavigator. All
## navigation behavior lives in the platform base; this
## subclass exists purely to keep callers terse: they
## construct ScreenFocusNavigator.new() and get the
## hopnbop focus sound for free.


func _init() -> void:
	set_focus_moved_callback(_play_focus_sound)


func _play_focus_sound() -> void:
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")
