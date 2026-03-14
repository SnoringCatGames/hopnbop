class_name LanguageScreen
extends Screen
## Full-screen language selector. Displays one row
## per supported locale. Navigates back to a caller-
## specified screen when the close button is pressed
## or a language is selected.
##
## Supports keyboard/controller navigation via
## AnyDeviceInputPoller.


const _LOCALE_DISPLAY_NAMES := {
	"en": "English",
	"zh": "中文",
	"es": "Español",
	"hi": "हिन्दी",
	"ar": "العربية",
	"fr": "Français",
	"pt": "Português",
	"ru": "Русский",
	"ja": "日本語",
	"de": "Deutsch",
	"ko": "한국어",
	"it": "Italiano",
	"th": "ไทย",
}

@export var icon_checkmark: Texture2D

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat

var _return_screen_type := (
	ScreensMain.ScreenType.UNKNOWN)
var _poller := AnyDeviceInputPoller.new()
var _focusable: Array[Control] = []
var _focused_index := 0


func _enter_tree() -> void:
	super._enter_tree()
	G.language_screen = self


func _ready() -> void:
	%CloseRow.gui_input.connect(
		_on_close_row_gui_input)
	%Icon.custom_minimum_size = (
		%Icon.texture.get_size() * 2)


func on_open() -> void:
	super.on_open()
	_build_language_list()
	_build_focusable_list()
	_scroll_to_current_locale()
	_poller.prime()


func _unhandled_input(
	event: InputEvent,
) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"close_menu"):
		get_viewport().set_input_as_handled()
		_close()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _focusable.is_empty():
		return

	_poller.poll(_delta)

	if _poller.up_just:
		_move_focus(-1)
	elif _poller.down_just:
		_move_focus(1)
	elif (_poller.left_just
			or _poller.right_just
			or _poller.trigger_just):
		_activate_focused()


## Set which screen to return to when the user
## closes or selects a language. Call before opening.
func set_return_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	_return_screen_type = screen_type


func _build_language_list() -> void:
	for child in %LanguageList.get_children():
		child.free()

	var current_locale := (
		G.local_settings.get_locale())
	for locale in LocalSettings.SUPPORTED_LOCALES:
		var native_name: String = (
			_LOCALE_DISPLAY_NAMES.get(
				locale, locale))
		var is_current := locale == current_locale
		var row := _create_language_row(
			locale, native_name, is_current)
		%LanguageList.add_child(row)


func _build_focusable_list() -> void:
	_focusable.clear()
	for child in %LanguageList.get_children():
		if child is PanelContainer:
			_focusable.append(
				child as PanelContainer)
	_focusable.append(%CloseRow)
	_focused_index = 0
	_update_focus()


func _move_focus(direction: int) -> void:
	if _focusable.is_empty():
		return
	_focused_index = (
		(_focused_index + direction)
		% _focusable.size())
	if _focused_index < 0:
		_focused_index += _focusable.size()
	_update_focus()
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _update_focus() -> void:
	for i in _focusable.size():
		var ctrl: Control = _focusable[i]
		if ctrl is PanelContainer:
			if i == _focused_index:
				ctrl.add_theme_stylebox_override(
					"panel", _focus_style)
				%ScrollContainer.ensure_control_visible(
					ctrl)
			else:
				ctrl.add_theme_stylebox_override(
					"panel", _unfocused_style)


func _activate_focused() -> void:
	if _focusable.is_empty():
		return
	var focused: Control = (
		_focusable[_focused_index])
	if focused == %CloseRow:
		_close()
		return
	if not focused.has_meta("locale"):
		return
	var locale: String = focused.get_meta("locale")
	G.local_settings.set_locale(locale)
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")
	_close()


func _close() -> void:
	G.screens.client_open_screen(_return_screen_type)


func _scroll_to_current_locale() -> void:
	var current_locale := (
		G.local_settings.get_locale())
	for i in _focusable.size():
		var ctrl: Control = _focusable[i]
		if (ctrl.has_meta("locale")
				and ctrl.get_meta("locale")
				== current_locale):
			_focused_index = i
			_update_focus()
			return


func _create_language_row(
	locale: String,
	native_name: String,
	is_current: bool,
) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override(
		"panel", _unfocused_style)
	row.set_meta("locale", locale)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	var check_icon := TextureRect.new()
	check_icon.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE)
	check_icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	check_icon.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	if icon_checkmark != null:
		check_icon.custom_minimum_size = (
			icon_checkmark.get_size()
			* G.settings.icon_scale)
	check_icon.texture = (
		icon_checkmark if is_current else null)
	hbox.add_child(check_icon)
	_wrap_icon_with_padding(check_icon)

	var name_label := Label.new()
	name_label.text = native_name
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	hbox.add_child(name_label)

	row.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if (mb.pressed
						and mb.button_index
						== MOUSE_BUTTON_LEFT):
					_activate_for_row(row))
	row.mouse_entered.connect(
		func() -> void:
			var idx := _focusable.find(row)
			if idx >= 0:
				_focused_index = idx
				_update_focus())

	return row


func _activate_for_row(row: PanelContainer) -> void:
	var idx := _focusable.find(row)
	if idx >= 0:
		_focused_index = idx
		_update_focus()
	_activate_focused()


func _wrap_icon_with_padding(
	icon_rect: TextureRect,
) -> void:
	var pad := G.settings.icon_padding
	if pad <= 0:
		return
	var parent := icon_rect.get_parent()
	var mc: MarginContainer
	if parent is MarginContainer:
		mc = parent as MarginContainer
	else:
		mc = MarginContainer.new()
		mc.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE)
		parent.add_child(mc)
		parent.move_child(
			mc, icon_rect.get_index())
		icon_rect.reparent(mc)
	mc.add_theme_constant_override(
		"margin_left", pad)
	mc.add_theme_constant_override(
		"margin_right", pad)
	mc.add_theme_constant_override(
		"margin_top", pad)
	mc.add_theme_constant_override(
		"margin_bottom", pad)


func _on_close_row_gui_input(
	event: InputEvent,
) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.pressed
				and mb.button_index
				== MOUSE_BUTTON_LEFT):
			_close()
