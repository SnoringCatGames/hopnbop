class_name LinkRow
extends SettingsRow
## A row that opens a URL in the browser.


var _url := ""
var _display_name := ""
var _icon_texture: Texture2D
var _icon_scale := -1

@onready var _icon: TextureRect = %Icon
@onready var _label: Label = %Label
@onready var _arrow: TextureRect = %Arrow


## Set an icon to display before the label. Call
## before add_child().
func set_icon(
	tex: Texture2D,
	scale: int = -1,
) -> void:
	_icon_texture = tex
	_icon_scale = scale


func setup(
	display_name: String,
	url: String,
) -> void:
	_url = url
	_display_name = display_name


func _ready() -> void:
	super()
	_label.text = _display_name
	_apply_icon(_icon, _icon_texture, _icon_scale)
	_setup_chevron(_arrow)


func on_left() -> void:
	_open()


func on_right() -> void:
	_open()


func _open() -> void:
	if not _url.is_empty():
		OS.shell_open(_url)
