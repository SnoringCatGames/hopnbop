class_name LegalLinkRow
extends SettingsRow
## A row that opens a URL in the browser.


var _url := ""
var _display_name := ""

@onready var _label: Label = %Label
@onready var _arrow_label: Label = %ArrowLabel


func setup(
	display_name: String,
	url: String,
) -> void:
	_url = url
	_display_name = display_name


func _ready() -> void:
	super()
	_label.text = _display_name
	_arrow_label.text = ">"


func on_left() -> void:
	_open()


func on_right() -> void:
	_open()


func _open() -> void:
	if not _url.is_empty():
		OS.shell_open(_url)
