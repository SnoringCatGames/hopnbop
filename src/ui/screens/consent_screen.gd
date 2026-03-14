class_name ConsentScreen
extends Screen
## Age gate and legal consent screen. Requires the
## player to confirm they are 13+ and accept the
## Terms of Service and Privacy Policy before
## proceeding to authentication.
##
## Supports keyboard/controller navigation via
## AnyDeviceInputPoller.


const _LANGUAGE_ROW_MIN_WIDTH := 200.0
const _LANGUAGE_SCROLL_HEIGHT := 200.0

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

@export_group("Checked Textures")
@export var tex_normal_checked: Texture2D
@export var tex_hovered_checked: Texture2D
@export var tex_pressed_checked: Texture2D

@export_group("Unchecked Textures")
@export var tex_normal_unchecked: Texture2D
@export var tex_hovered_unchecked: Texture2D
@export var tex_pressed_unchecked: Texture2D

@export_group("Row Icons")
@export var icon_language: Texture2D
@export var icon_terms: Texture2D
@export var icon_privacy: Texture2D

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat

var _age_checked := false
var _terms_checked := false
var _is_language_overlay_shown := false

var _poller := AnyDeviceInputPoller.new()
var _focusable: Array[Control] = []
var _focused_index := 0

var _language_arrow: TextureRect
var _terms_arrow: TextureRect
var _privacy_arrow: TextureRect


func _enter_tree() -> void:
	super._enter_tree()
	G.consent_screen = self


func _ready() -> void:
	%AgeCheckBox.pressed.connect(
		_on_age_pressed)
	%TermsCheckBox.pressed.connect(
		_on_terms_pressed)
	%ContinueButton.pressed.connect(
		_on_continue_pressed)

	%AgeCheckBox.mouse_entered.connect(
		_update_checkbox_textures)
	%AgeCheckBox.mouse_exited.connect(
		_update_checkbox_textures)
	%TermsCheckBox.mouse_entered.connect(
		_update_checkbox_textures)
	%TermsCheckBox.mouse_exited.connect(
		_update_checkbox_textures)

	# Scale checkboxes 2x.
	if tex_normal_checked != null:
		var cb_size := (
			tex_normal_checked.get_size() * 2)
		%AgeCheckBox.custom_minimum_size = cb_size
		%TermsCheckBox.custom_minimum_size = cb_size
	%AgeCheckBox.stretch_mode = (
		TextureButton.STRETCH_KEEP_ASPECT_CENTERED)
	%TermsCheckBox.stretch_mode = (
		TextureButton.STRETCH_KEEP_ASPECT_CENTERED)

	# Set row icons.
	_setup_row_icon(
		%LanguageRow.get_node(
			"HBoxContainer/Icon"),
		icon_language)
	_setup_row_icon(
		%TermsLinkRow.get_node(
			"HBoxContainer/Icon"),
		icon_terms)
	_setup_row_icon(
		%PrivacyLinkRow.get_node(
			"HBoxContainer/Icon"),
		icon_privacy)

	# Store arrow refs before _setup_chevron wraps
	# them in a MarginContainer via padding.
	_language_arrow = %LanguageRow.get_node(
		"HBoxContainer/Arrow")
	_terms_arrow = %TermsLinkRow.get_node(
		"HBoxContainer/Arrow")
	_privacy_arrow = %PrivacyLinkRow.get_node(
		"HBoxContainer/Arrow")

	# Set up chevron icons on arrow rows.
	_setup_chevron(_language_arrow)
	_setup_chevron(_terms_arrow)
	_setup_chevron(_privacy_arrow)

	# Connect mouse interactions for focusable
	# PanelContainer rows.
	_connect_row_mouse(%LanguageRow, 0)
	_connect_row_mouse(%TermsLinkRow, 1)
	_connect_row_mouse(%PrivacyLinkRow, 2)
	_connect_row_mouse(%AgeRow, 3)
	_connect_row_mouse(%TermsRow, 4)


func on_open() -> void:
	super.on_open()

	# Preview mode secondary clients auto-consent.
	if (Netcode.is_preview
			and Netcode.is_client
			and Netcode.preview_client_number > 1):
		_auto_consent_and_skip()
		return

	# Already consented for current legal version.
	if G.auth_token_store.has_valid_consent(
		AuthTokenStore.LEGAL_VERSION,
	):
		_navigate_to_auth()
		return

	# Show consent UI.
	_is_language_overlay_shown = false
	_age_checked = false
	_terms_checked = false
	%ContinueButton.disabled = true
	_update_checkbox_textures()

	_build_focusable_list()
	_poller.prime()


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


func _build_focusable_list() -> void:
	_focusable.clear()
	_focusable.append(%LanguageRow)
	_focusable.append(%TermsLinkRow)
	_focusable.append(%PrivacyLinkRow)
	_focusable.append(%AgeRow)
	_focusable.append(%TermsRow)
	_focusable.append(%ContinueButton)
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
		if ctrl is Button:
			if i == _focused_index:
				ctrl.grab_focus()
			else:
				ctrl.release_focus()
		elif ctrl is PanelContainer:
			if i == _focused_index:
				ctrl.add_theme_stylebox_override(
					"panel", _focus_style)
			else:
				ctrl.add_theme_stylebox_override(
					"panel", _unfocused_style)


func _activate_focused() -> void:
	if _focusable.is_empty():
		return
	var focused: Control = (
		_focusable[_focused_index])
	if _is_language_overlay_shown:
		_activate_language_option(focused)
		return
	if focused == %LanguageRow:
		_open_language_overlay()
	elif focused == %TermsLinkRow:
		_open_legal_screen(ScreensMain.ScreenType.TERMS)
	elif focused == %PrivacyLinkRow:
		_open_legal_screen(
			ScreensMain.ScreenType.PRIVACY)
	elif focused == %AgeRow:
		_on_age_pressed()
	elif focused == %TermsRow:
		_on_terms_pressed()
	elif focused == %ContinueButton:
		if not %ContinueButton.disabled:
			_on_continue_pressed()


func _connect_row_mouse(
	row: PanelContainer,
	focus_index: int,
) -> void:
	row.gui_input.connect(
		func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb: InputEventMouseButton = (
					event)
				if (mb.pressed
						and mb.button_index
						== MOUSE_BUTTON_LEFT):
					_focused_index = focus_index
					_update_focus()
					_activate_focused())
	row.mouse_entered.connect(
		func() -> void:
			_focused_index = focus_index
			_update_focus())


func _open_language_overlay() -> void:
	_is_language_overlay_shown = true
	# Hide static consent children.
	for child in %ContentBox.get_children():
		child.visible = false
	_build_language_options()
	_poller.prime()
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _close_language_overlay() -> void:
	_is_language_overlay_shown = false
	# Remove dynamic language rows.
	var children := %ContentBox.get_children()
	for child in children:
		if child.has_meta("is_language_row"):
			%ContentBox.remove_child(child)
			child.queue_free()
	# Show static consent children.
	for child in %ContentBox.get_children():
		child.visible = true
	_update_rtl_arrows()
	_build_focusable_list()
	_poller.prime()
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _build_language_options() -> void:
	_focusable.clear()

	# Back row.
	var back_row := _create_back_row()
	back_row.set_meta("is_language_row", true)
	%ContentBox.add_child(back_row)
	_connect_row_mouse(
		back_row, _focusable.size())
	_focusable.append(back_row)

	# Spacer between back and options.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.set_meta("is_language_row", true)
	%ContentBox.add_child(spacer)

	# Scrollable language list.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(
		_LANGUAGE_ROW_MIN_WIDTH,
		_LANGUAGE_SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED)
	scroll.set_meta("is_language_row", true)
	%ContentBox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override(
		"separation", 8)
	scroll.add_child(list)

	# One row per supported locale.
	var current_locale := (
		G.local_settings.get_locale())
	for locale in LocalSettings.SUPPORTED_LOCALES:
		var native_name: String = (
			_LOCALE_DISPLAY_NAMES.get(
				locale, locale))
		var is_current := (
			locale == current_locale)
		var row := _create_language_option(
			locale, native_name, is_current)
		list.add_child(row)
		_connect_row_mouse(
			row, _focusable.size())
		_focusable.append(row)

	# Bottom padding outside scroll area.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 40))
	bottom_spacer.set_meta(
		"is_language_row", true)
	%ContentBox.add_child(bottom_spacer)

	_focused_index = 0
	_update_focus()


func _create_back_row() -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(
		_LANGUAGE_ROW_MIN_WIDTH, 0)
	row.add_theme_stylebox_override(
		"panel", _unfocused_style)
	row.set_meta("is_back", true)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	hbox.add_theme_constant_override(
		"separation", 8)
	row.add_child(hbox)

	var arrow := TextureRect.new()
	arrow.texture = G.settings.chevron_icon
	arrow.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE)
	arrow.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	var back_chevron_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	arrow.custom_minimum_size = back_chevron_size
	if not is_layout_rtl():
		arrow.pivot_offset = back_chevron_size / 2.0
		arrow.scale.x = -1.0
	hbox.add_child(arrow)

	var label := Label.new()
	label.text = tr("SETTINGS.LANGUAGE")
	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	hbox.add_child(label)

	return row


func _create_language_option(
	locale: String,
	native_name: String,
	is_current: bool,
) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(
		_LANGUAGE_ROW_MIN_WIDTH, 0)
	row.add_theme_stylebox_override(
		"panel", _unfocused_style)
	row.set_meta("locale", locale)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE)
	hbox.add_theme_constant_override(
		"separation", 8)
	row.add_child(hbox)

	var check_label := Label.new()
	if is_current:
		check_label.text = "✓"
	else:
		check_label.text = ""
	check_label.custom_minimum_size = (
		Vector2(20, 0))
	hbox.add_child(check_label)

	var name_label := Label.new()
	name_label.text = native_name
	name_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL)
	hbox.add_child(name_label)

	return row


func _activate_language_option(
	focused: Control,
) -> void:
	if focused.has_meta("is_back"):
		_close_language_overlay()
		return
	if not focused.has_meta("locale"):
		return
	var locale: String = (
		focused.get_meta("locale"))
	G.local_settings.set_locale(locale)
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")
	_close_language_overlay()


func _setup_row_icon(
	icon_rect: TextureRect,
	tex: Texture2D,
) -> void:
	if tex != null:
		icon_rect.texture = tex
		icon_rect.custom_minimum_size = (
			tex.get_size()
			* G.settings.icon_scale)
		_wrap_icon_with_padding(icon_rect)
		icon_rect.show()
	else:
		icon_rect.hide()


func _setup_chevron(rect: TextureRect) -> void:
	rect.texture = G.settings.chevron_icon
	rect.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE)
	rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	var icon_size := (
		G.settings.chevron_icon.get_size()
		* G.settings.icon_scale)
	rect.custom_minimum_size = icon_size
	_wrap_icon_with_padding(rect)
	rect.scale.x = 1.0
	if is_layout_rtl():
		rect.pivot_offset = icon_size / 2.0
		rect.scale.x = -1.0


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


func _update_rtl_arrows() -> void:
	_setup_chevron(_language_arrow)
	_setup_chevron(_terms_arrow)
	_setup_chevron(_privacy_arrow)


func _on_age_pressed() -> void:
	_age_checked = not _age_checked
	_update_state()


func _on_terms_pressed() -> void:
	_terms_checked = not _terms_checked
	_update_state()


func _update_state() -> void:
	_update_checkbox_textures()
	%ContinueButton.disabled = not (
		_age_checked and _terms_checked)
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")


func _update_checkbox_textures() -> void:
	_apply_texture(
		%AgeCheckBox, _age_checked)
	_apply_texture(
		%TermsCheckBox, _terms_checked)


func _apply_texture(
	btn: TextureButton,
	is_checked: bool,
) -> void:
	var is_hovered := (
		btn.get_global_rect().has_point(
			btn.get_global_mouse_position()))
	if is_checked:
		btn.texture_normal = (
			tex_hovered_checked
			if is_hovered
			else tex_normal_checked)
	else:
		btn.texture_normal = (
			tex_hovered_unchecked
			if is_hovered
			else tex_normal_unchecked)


func _on_continue_pressed() -> void:
	G.auth_token_store.consent_accepted_at = (
		int(Time.get_unix_time_from_system()))
	G.auth_token_store.consent_legal_version = (
		AuthTokenStore.LEGAL_VERSION)
	G.auth_token_store.save_tokens()
	_navigate_to_auth()


func _open_legal_screen(
	screen_type: ScreensMain.ScreenType,
) -> void:
	var screen: LegalDocScreen = (
		G.screens.get_screen_from_type(
			screen_type) as LegalDocScreen)
	if not is_instance_valid(screen):
		return
	screen.set_return_screen(
		ScreensMain.ScreenType.CONSENT)
	G.screens.client_open_screen(screen_type)


func _navigate_to_auth() -> void:
	if G.settings.skip_auth:
		G.screens.client_open_screen(
			ScreensMain.ScreenType.LOBBY)
	else:
		G.screens.client_open_screen(
			ScreensMain.ScreenType.AUTH)


func _auto_consent_and_skip() -> void:
	G.auth_token_store.consent_accepted_at = (
		int(Time.get_unix_time_from_system()))
	G.auth_token_store.consent_legal_version = (
		AuthTokenStore.LEGAL_VERSION)
	G.auth_token_store.save_tokens()
	_navigate_to_auth()
