class_name LegalLinkRow
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
	if _icon_texture != null:
		_icon.texture = _icon_texture
		if _icon_scale > 0:
			var width := (
				G.settings.get_icon_display_width())
			_icon.custom_minimum_size = (
				Vector2(width, width))
		else:
			_icon.custom_minimum_size = (
				_icon_texture.get_size()
				* G.settings.icon_scale)
		_icon.show()
	else:
		_icon.hide()
	_setup_chevron(_arrow)


func on_left() -> void:
	_open()


func on_right() -> void:
	_open()


func _open() -> void:
	if not _url.is_empty():
		OS.shell_open(_url)


func _setup_chevron(rect: TextureRect) -> void:
	rect.texture = G.settings.chevron_icon
	var chevron_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	rect.custom_minimum_size = chevron_size
	if is_layout_rtl():
		rect.pivot_offset = chevron_size / 2.0
		rect.scale.x = -1.0
