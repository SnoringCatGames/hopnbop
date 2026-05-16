class_name DeleteAccountConfirmPanel
extends SidePanel
## Two-step confirmation panel for account deletion. The user
## must type a localized verify word (e.g. "DELETE") into the
## input row before the Confirm button enables. Body copy spells
## out the 30-day grace period so the user knows the action is
## recoverable until then.


@export var _back_row_scene: PackedScene
@export var _text_input_row_scene: PackedScene
@export var _delete_icon: Texture2D

var _verify_input: TextInputRow
var _confirm_row: ActionRow
## Set on _ready by tr("CONFIRM.DELETE_ACCOUNT_VERIFY_WORD")
## (already uppercased per the translation table). User input is
## stripped + uppercased before comparison so Latin locales can
## accept lowercase too.
var _verify_word := ""
var _is_busy := false


func build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Back row.
	var back_row: BackRow = (
		_back_row_scene.instantiate())
	back_row.setup(self)
	_row_container.add_child(back_row)
	_connect_row_clicked(back_row)

	# Spacer below back button.
	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = (
		Vector2(0, 20))
	_row_container.add_child(back_spacer)

	# Header (non-focusable). Mirrors the original
	# CONFIRM.DELETE_ACCOUNT one-liner so the user still sees the
	# top-level "you're about to delete your account" framing
	# above the grace-period explanation.
	var header := Label.new()
	header.text = tr("CONFIRM.DELETE_ACCOUNT")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override(
		"font_color", Color(1.0, 1.0, 1.0))
	_row_container.add_child(header)

	var header_spacer := Control.new()
	header_spacer.custom_minimum_size = Vector2(0, 8)
	_row_container.add_child(header_spacer)

	# Body copy explaining the grace period (non-focusable).
	var body := Label.new()
	body.text = tr("CONFIRM.DELETE_ACCOUNT_DETAIL")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(
		"font_color", Color(0.85, 0.85, 0.85))
	_row_container.add_child(body)

	var body_spacer := Control.new()
	body_spacer.custom_minimum_size = Vector2(0, 16)
	_row_container.add_child(body_spacer)

	# Verify-word prompt (non-focusable label above the input).
	_verify_word = tr(
		"CONFIRM.DELETE_ACCOUNT_VERIFY_WORD")
	var prompt := Label.new()
	prompt.text = (
		tr("CONFIRM.DELETE_ACCOUNT_TYPE_PROMPT")
		% _verify_word)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_row_container.add_child(prompt)

	# Text input row.
	_verify_input = (
		_text_input_row_scene.instantiate())
	_verify_input.setup(_verify_word, 0)
	_verify_input.text_changed.connect(
		_on_input_changed)
	_verify_input.submitted.connect(
		_on_confirm_pressed)
	_row_container.add_child(_verify_input)
	_connect_row_clicked(_verify_input)

	var input_spacer := Control.new()
	input_spacer.custom_minimum_size = Vector2(0, 8)
	_row_container.add_child(input_spacer)

	# Confirm row. Disabled until input matches verify word.
	_confirm_row = ActionRow.new()
	_confirm_row.setup_action(_on_confirm_pressed)
	_confirm_row.setup_label(
		tr("CONFIRM.DELETE_ACCOUNT_CONFIRM_BUTTON"),
		_delete_icon)
	_confirm_row.disabled = true
	_row_container.add_child(_confirm_row)
	_connect_row_clicked(_confirm_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


func _on_input_changed(text: String) -> void:
	if not is_instance_valid(_confirm_row):
		return
	# Latin-locale convention accepts lowercase by upcasing the
	# user's input before comparison. Non-Latin scripts (Chinese,
	# Japanese, etc.) are unaffected — to_upper() is the identity
	# function on those code points.
	var normalized := text.strip_edges().to_upper()
	_confirm_row.disabled = (
		_is_busy
		or normalized != _verify_word.strip_edges().to_upper())


func _on_confirm_pressed() -> void:
	if _is_busy:
		return
	if not is_instance_valid(_confirm_row):
		return
	if _confirm_row.disabled:
		return
	_is_busy = true
	_confirm_row.disabled = true

	Platform.auth.delete_completed.connect(
		_on_delete_completed, CONNECT_ONE_SHOT)
	Platform.auth.delete_account()


func _on_delete_completed(
	success: bool,
	error: String,
) -> void:
	if is_queued_for_deletion():
		return
	_is_busy = false

	if is_instance_valid(manager):
		manager.close_all()

	if success:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.ACCOUNT_DELETE_QUEUED"),
				ToastOverlay.Type.SUCCESS,
			)
		G.screens.client_open_screen(
			ScreensMain.ScreenType.CONSENT,
		)
	else:
		G.log.error(
			"Account deletion failed: %s" % error)
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.DELETE_FAILED") % error,
				ToastOverlay.Type.ERROR,
			)
