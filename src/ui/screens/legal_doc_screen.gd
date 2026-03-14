class_name LegalDocScreen
extends Screen
## Full-screen viewer for in-game legal documents.
## Matches the logo-top-half layout of ConsentScreen
## and AuthScreen. Scrollable via up/down input on
## any device. The back row unlocks only after the
## user has scrolled to the bottom.


enum DocType {
	TERMS,
	PRIVACY,
	DATA_DELETION,
}

const _FILE_NAMES := {
	DocType.TERMS: "terms.txt",
	DocType.PRIVACY: "privacy.txt",
	DocType.DATA_DELETION: "data_deletion.txt",
}

const _TITLE_KEYS := {
	DocType.TERMS: "CONSENT.TERMS_OF_SERVICE",
	DocType.PRIVACY: "CONSENT.PRIVACY_POLICY",
	DocType.DATA_DELETION: "SETTINGS.DATA_DELETION_POLICY",
}

const _SCROLL_STEP := 240

@export var doc_type: DocType = DocType.TERMS

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _back_unlocked := false
var _poller := AnyDeviceInputPoller.new()


func _enter_tree() -> void:
	super._enter_tree()
	match doc_type:
		DocType.TERMS:
			G.terms_screen = self
		DocType.PRIVACY:
			G.privacy_screen = self
		DocType.DATA_DELETION:
			G.data_deletion_screen = self


func _ready() -> void:
	_setup_back_row()
	%BackRow.gui_input.connect(_on_back_row_gui_input)


func on_open() -> void:
	super.on_open()
	%TitleLabel.text = tr(_TITLE_KEYS[doc_type])
	%Content.text = _load_content()
	%ScrollContainer.scroll_vertical = 0
	_back_unlocked = false
	_update_back_row_style()
	_poller.prime()


func _process(_delta: float) -> void:
	if not visible:
		return

	_poller.poll(_delta)

	if _poller.up_just:
		_scroll(-_SCROLL_STEP)
	elif _poller.down_just:
		_scroll(_SCROLL_STEP)
	elif ((_poller.trigger_just
				or _poller.left_just
				or _poller.right_just)
			and _back_unlocked):
		_on_back_pressed()

	if not _back_unlocked and _is_at_scroll_bottom():
		_back_unlocked = true
		_update_back_row_style()


## Set where the back row navigates to. Call before
## opening this screen.
func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


func _on_back_pressed() -> void:
	G.screens.client_open_screen(
		_return_screen_type)


func _on_back_row_gui_input(
	event: InputEvent,
) -> void:
	if not _back_unlocked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			_on_back_pressed()


func _scroll(amount: int) -> void:
	%ScrollContainer.scroll_vertical = (
		%ScrollContainer.scroll_vertical + amount)


func _is_at_scroll_bottom() -> bool:
	# Guard: layout not yet calculated.
	if %ScrollContainer.size.y == 0:
		return false
	var bar: VScrollBar = (
		%ScrollContainer.get_v_scroll_bar())
	# Content fits without scrolling.
	if bar.max_value <= bar.page:
		return true
	return (
		bar.value >= bar.max_value - bar.page - 1.0)


func _update_back_row_style() -> void:
	if _back_unlocked:
		%BackRow.add_theme_stylebox_override(
			"panel", _focus_style)
	else:
		%BackRow.add_theme_stylebox_override(
			"panel", _unfocused_style)


func _setup_back_row() -> void:
	_update_back_row_style()
	var arrow: TextureRect = (
		%BackRow.get_node("HBoxContainer/Arrow"))
	arrow.texture = G.settings.chevron_icon
	arrow.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE)
	arrow.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	var icon_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	var pad: float = G.settings.icon_padding * 2.0
	var total_size := icon_size + Vector2(pad, pad)
	arrow.custom_minimum_size = total_size
	if not is_layout_rtl():
		arrow.pivot_offset = total_size / 2.0
		arrow.scale.x = -1.0


func _load_content() -> String:
	var locale := G.local_settings.get_locale()
	var file_name: String = _FILE_NAMES[doc_type]
	var locale_path := (
		"res://legal/%s/%s" % [locale, file_name])
	var fallback_path := (
		"res://legal/en/%s" % file_name)
	if FileAccess.file_exists(locale_path):
		return FileAccess.get_file_as_string(
			locale_path)
	return FileAccess.get_file_as_string(
		fallback_path)
