class_name ConsentScreen
extends Screen
## Age gate and legal consent screen. Requires the
## player to confirm they are 13+ and accept the
## Terms of Service and Privacy Policy before
## proceeding to authentication.
##
## Supports keyboard/controller navigation via
## AnyDeviceInputPoller.


const _TERMS_URL := "https://hopnbop.net/terms"
const _PRIVACY_URL := "https://hopnbop.net/privacy"

@export_group("Checked Textures")
@export var tex_normal_checked: Texture2D
@export var tex_hovered_checked: Texture2D
@export var tex_pressed_checked: Texture2D

@export_group("Unchecked Textures")
@export var tex_normal_unchecked: Texture2D
@export var tex_hovered_unchecked: Texture2D
@export var tex_pressed_unchecked: Texture2D

var _age_checked := false
var _terms_checked := false

var _poller := AnyDeviceInputPoller.new()
var _focusable: Array[Control] = []
var _focused_index := 0

@export var _focus_style: StyleBoxTexture
@export var _unfocused_style: StyleBoxFlat


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

	# Flip arrows for RTL locales.
	var arrow_text := "<" if is_layout_rtl() else ">"
	%TermsLinkRow.get_node(
		"HBoxContainer/Arrow").text = arrow_text
	%PrivacyLinkRow.get_node(
		"HBoxContainer/Arrow").text = arrow_text

	# Connect mouse interactions for focusable
	# PanelContainer rows.
	_connect_row_mouse(%TermsLinkRow, 0)
	_connect_row_mouse(%PrivacyLinkRow, 1)
	_connect_row_mouse(%AgeRow, 2)
	_connect_row_mouse(%TermsRow, 3)


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
	if focused == %TermsLinkRow:
		OS.shell_open(_TERMS_URL)
	elif focused == %PrivacyLinkRow:
		OS.shell_open(_PRIVACY_URL)
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
