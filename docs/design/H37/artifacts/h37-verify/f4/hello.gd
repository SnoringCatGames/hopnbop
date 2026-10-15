extends SceneTree
## H37 probe (h37-verify 4f): does this template run a -s script?
func _init() -> void:
	print("H37HELLO debug_build=%s editor=%s template=%s template_debug=%s" % [
		OS.is_debug_build(), OS.has_feature("editor"),
		OS.has_feature("template"), OS.has_feature("template_debug")])
	quit()
