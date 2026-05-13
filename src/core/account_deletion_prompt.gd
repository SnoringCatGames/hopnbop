class_name AccountDeletionPrompt
extends Node
## Stage 1.5 cancellation surface. On every auth_completed
## success this node queries the runtime's
## `get_account_deletion_status` RPC; if the response says the
## caller has an active queue row, it opens a ConfirmOverlay
## that lets the user cancel the pending deletion before the
## hourly hard-delete cron picks it up.
##
## Lives game-side rather than in the addon because the prompt
## reaches into `G.confirm_layer` and `G.settings.
## confirm_overlay_scene` (game-owned UI surfaces). The runtime
## side of the flow lives in
## `third_party/snoringcat-platform/runtime/account.go`.


## Already-shown dedup. The auth_completed signal fires on every
## successful refresh, not just on initial sign-in. We don't
## want to re-pop the dialog every time the JWT refreshes
## (every ~60 min). Cleared when the cancellation RPC succeeds.
var _prompt_shown_for_session := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	(Platform.auth as PlatformAuthApiClient).auth_completed.connect(
		_on_auth_completed)


func _on_auth_completed(success: bool, _error: String) -> void:
	if not success:
		return
	if _prompt_shown_for_session:
		return
	# Anonymous users can't have a queued deletion (delete_account
	# requires a session and the queue row is keyed by user_id),
	# but their token_store flag is the cheapest pre-check.
	if Platform.token_store == null:
		return
	if Platform.token_store.is_anonymous:
		return
	_check_status()


func _check_status() -> void:
	var session: NakamaSession = (
		Platform.build_session_from_store())
	if session == null:
		return
	var result = await (Platform.get_nakama_client()
		.rpc_async(session, "get_account_deletion_status", ""))
	if result.is_exception():
		# Pre-1.5 runtimes don't know this RPC; treat as
		# "no pending deletion" so old servers don't pop a
		# spurious dialog. Other failure modes (network blip,
		# 5xx) are also non-fatal: the user can sign in again
		# later and we'll re-check.
		return
	var data: Variant = JSON.parse_string(result.payload)
	if not (data is Dictionary):
		return
	if not bool(data.get("pending", false)):
		return
	_prompt_shown_for_session = true
	_show_prompt(data)


func _show_prompt(status: Dictionary) -> void:
	if not is_instance_valid(G.confirm_layer):
		return
	if (G.settings == null
			or G.settings.confirm_overlay_scene == null):
		return
	var scheduled_for: int = int(status.get("scheduled_for", 0))
	var message: String
	if scheduled_for > 0:
		var when := _format_scheduled_for(scheduled_for)
		message = (
			tr("CONFIRM.ACCOUNT_DELETION_PENDING")
				% when)
	else:
		message = tr("CONFIRM.ACCOUNT_DELETION_PENDING_NO_DATE")
	var dialog: ConfirmOverlay = (
		G.settings.confirm_overlay_scene.instantiate())
	G.confirm_layer.add_child(dialog)
	dialog.open(
		message,
		tr("CONFIRM.CANCEL_DELETION"),
		_on_cancel_pressed,
		tr("CONFIRM.KEEP_DELETION"),
		func() -> void: pass,
	)


func _on_cancel_pressed() -> void:
	var session: NakamaSession = (
		Platform.build_session_from_store())
	if session == null:
		return
	var result = await (Platform.get_nakama_client()
		.rpc_async(session, "cancel_account_deletion", ""))
	if result.is_exception():
		if is_instance_valid(G.toast_overlay):
			G.toast_overlay.show_toast(
				tr("TOAST.ACCOUNT_DELETION_CANCEL_FAILED"),
				ToastOverlay.Type.ERROR,
			)
		return
	# Allow re-prompt on the next session in case the user
	# accidentally re-queues. The success path stays out of the
	# loop for *this* session, though.
	_prompt_shown_for_session = true
	if is_instance_valid(G.toast_overlay):
		G.toast_overlay.show_toast(
			tr("TOAST.ACCOUNT_DELETION_CANCELLED"))


## Renders the scheduled_for timestamp as a local-date string.
## Best-effort — the runtime sends a unix timestamp so a stable
## render across locales is hard without a full date-format
## library. Fall back to ISO when Godot's Time helper trips.
func _format_scheduled_for(unix_sec: int) -> String:
	var dt := Time.get_datetime_string_from_unix_time(
		unix_sec, true)
	if dt.is_empty():
		return str(unix_sec)
	# Strip the time portion (we only care about the day) so the
	# message reads "scheduled for 2026-06-12" rather than
	# "scheduled for 2026-06-12T15:33:22".
	var t_index := dt.find("T")
	if t_index > 0:
		return dt.substr(0, t_index)
	return dt
