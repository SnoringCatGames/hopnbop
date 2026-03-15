class_name QuitRow
extends SettingsRow
## A row that quits the application when activated.


var _icon_texture: Texture2D

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label


## Set an icon to display before the label. Call
## before add_child().
func set_icon(tex: Texture2D) -> void:
	_icon_texture = tex


func _ready() -> void:
	super()
	_label.text = tr("SETTINGS.QUIT")
	_apply_icon(_icon, _icon_texture)


func on_left() -> void:
	get_tree().quit()


func on_right() -> void:
	get_tree().quit()
