extends SceneTree

func _init() -> void:
	var a := Vector2(1, 2)
	var b := Vector2(3, 4)
	print("BEFORE")
	print(
		"LABEL XFORM MISMATCH:"
		+ " old_origin=%s"
		+ " native_origin=%s"
		+ " old_x=%s native_x=%s"
		+ " old_y=%s native_y=%s"
		% [a, b, a, b, a, b])
	print("AFTER")
	quit()
