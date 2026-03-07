class_name SettingsRow
extends PanelContainer
## Base class for rows in the settings panel.
## Each row can be focused and responds to
## left/right input. Shows focus border on
## keyboard focus or mouse hover.


@warning_ignore("unused_signal")
signal value_changed
signal clicked

var _focus_style: StyleBoxTexture = preload(
	"res://src/ui/settings_panel/"
	+ "focus_border_stylebox.tres")
var _unfocused_style: StyleBoxFlat = preload(
	"res://src/ui/settings_panel/"
	+ "unfocused_stylebox.tres")

var _is_mouse_hovered := false

var is_focused := false:
	set(value):
		is_focused = value
		_update_focus_style()


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_update_focus_style()


## Called when the player presses left.
func on_left() -> void:
	pass


## Called when the player presses right.
func on_right() -> void:
	pass


func _on_mouse_entered() -> void:
	_is_mouse_hovered = true
	_update_focus_style()
	_on_hover_changed()


func _on_mouse_exited() -> void:
	_is_mouse_hovered = false
	_update_focus_style()
	_on_hover_changed()


## Override in subclasses for type-specific
## hover effects.
func _on_hover_changed() -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			accept_event()
			clicked.emit()


func _update_focus_style() -> void:
	if is_focused or _is_mouse_hovered:
		add_theme_stylebox_override(
			"panel", _focus_style)
	else:
		add_theme_stylebox_override(
			"panel", _unfocused_style)
