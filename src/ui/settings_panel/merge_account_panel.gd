class_name MergeAccountPanel
extends SidePanel
## Pushed by LinkAccountRow when a link attempt returns
## PROVIDER_CONFLICT (the chosen provider is already on a different
## account). Explains the merge consequences in fuller copy than the
## prior ConfirmOverlay flow, then offers Merge / Cancel rows that
## drive `Platform.auth.confirm_merge` / `cancel_merge`. The panel
## owns the merge_completed signal subscription so it can pop itself
## on success or surface the failure inline. Stage 7.8.


@export var _back_row_scene: PackedScene
@export var icon_merge: Texture2D

var _provider: PlatformAuthApiClient.Provider
var _provider_display_name := ""
var _is_busy := false
# True if the user explicitly tapped Merge or Cancel. Lets
# `_exit_tree` decide whether the back-row pop path needs to call
# `cancel_merge` (to release the pending server-side merge token).
var _explicit_action_taken := false
var _merge_row: ActionRow
var _cancel_row: ActionRow


## Set the provider whose link attempt triggered the conflict.
## Call before add_child().
func configure(
	provider: PlatformAuthApiClient.Provider,
	provider_display_name: String,
) -> void:
	_provider = provider
	_provider_display_name = provider_display_name


func build_ui() -> void:
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	var back_row: BackRow = _back_row_scene.instantiate()
	back_row.setup(self)
	_row_container.add_child(back_row)
	_connect_row_clicked(back_row)

	var back_spacer := Control.new()
	back_spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(back_spacer)

	_add_header()
	_add_body()

	_add_merge_row()
	_add_cancel_row()

	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(bottom_spacer)

	Platform.auth.merge_completed.connect(_on_merge_completed)


func _exit_tree() -> void:
	if not is_instance_valid(Platform.auth):
		return
	# Back-row pop (user didn't tap Merge or Cancel) leaves the
	# server-side merge token pending. Release it so a future link
	# attempt against the same provider starts fresh.
	if not _explicit_action_taken:
		Platform.auth.cancel_merge()
	if Platform.auth.merge_completed.is_connected(
			_on_merge_completed):
		Platform.auth.merge_completed.disconnect(
			_on_merge_completed)


func _add_header() -> void:
	var header := Label.new()
	header.text = tr("MERGE.HEADER")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_row_container.add_child(header)

	var header_spacer := Control.new()
	header_spacer.custom_minimum_size = Vector2(0, 12)
	_row_container.add_child(header_spacer)


func _add_body() -> void:
	var body := Label.new()
	body.text = tr("MERGE.BODY") % _provider_display_name
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_row_container.add_child(body)

	var body_spacer := Control.new()
	body_spacer.custom_minimum_size = Vector2(0, 20)
	_row_container.add_child(body_spacer)


func _add_merge_row() -> void:
	_merge_row = ActionRow.new()
	_merge_row.setup_actions(_on_merge_pressed, _on_merge_pressed)
	_merge_row.setup_label(tr("MERGE.CONTINUE"), icon_merge)
	_row_container.add_child(_merge_row)
	_connect_row_clicked(_merge_row)


func _add_cancel_row() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_row_container.add_child(spacer)

	_cancel_row = ActionRow.new()
	_cancel_row.setup_actions(_on_cancel_pressed, _on_cancel_pressed)
	_cancel_row.setup_label(tr("CONFIRM.CANCEL"))
	_row_container.add_child(_cancel_row)
	_connect_row_clicked(_cancel_row)


func _on_merge_pressed() -> void:
	if _is_busy:
		return
	_is_busy = true
	_explicit_action_taken = true
	if is_instance_valid(_merge_row):
		_merge_row.disabled = true
	if is_instance_valid(_cancel_row):
		_cancel_row.disabled = true
	Platform.auth.confirm_merge()


func _on_cancel_pressed() -> void:
	if _is_busy:
		return
	_explicit_action_taken = true
	Platform.auth.cancel_merge()
	if is_instance_valid(manager):
		manager.pop_panel()


func _on_merge_completed(
	success: bool,
	error: String,
	_provider_str: String,
) -> void:
	if is_queued_for_deletion():
		return
	if success:
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.ACCOUNTS_MERGED"))
		if is_instance_valid(manager):
			manager.close_all()
		return

	_is_busy = false
	if is_instance_valid(_merge_row):
		_merge_row.disabled = false
	if is_instance_valid(_cancel_row):
		_cancel_row.disabled = false

	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.MERGE_FAILED") % error,
			ToastOverlay.Type.ERROR)
