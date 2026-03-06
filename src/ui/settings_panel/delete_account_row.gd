class_name DeleteAccountRow
extends SettingsRow
## A row that triggers account deletion with a
## confirmation step. First press shows "Are you
## sure?", second press confirms and deletes.


const _CONFIRM_TIMEOUT_SEC := 3.0

var _is_confirming := false
var _is_busy := false

@onready var _label: Label = %Label
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	super()
	_label.text = "Delete Account"
	_status_label.text = ""


func on_left() -> void:
	_activate()


func on_right() -> void:
	_activate()


func _activate() -> void:
	if _is_busy:
		return

	if not _is_confirming:
		_start_confirm()
		return

	_do_delete()


func _start_confirm() -> void:
	_is_confirming = true
	_label.modulate = Color(1.0, 0.4, 0.4)
	_status_label.text = "Are you sure?"
	_status_label.modulate = Color(1.0, 0.4, 0.4)

	# Auto-cancel after timeout.
	var timer := get_tree().create_timer(
		_CONFIRM_TIMEOUT_SEC
	)
	timer.timeout.connect(_cancel_confirm)


func _cancel_confirm() -> void:
	if not _is_confirming or _is_busy:
		return
	_is_confirming = false
	_label.modulate = Color.WHITE
	_status_label.text = ""


func _do_delete() -> void:
	_is_confirming = false
	_is_busy = true
	_status_label.text = "Deleting..."
	_status_label.modulate = Color(1.0, 0.4, 0.4)

	G.auth_client.delete_completed.connect(
		_on_delete_completed, CONNECT_ONE_SHOT
	)
	G.auth_client.delete_account()


func _on_delete_completed(
	success: bool,
	error: String,
) -> void:
	_is_busy = false
	_label.modulate = Color.WHITE

	if success:
		_status_label.text = "Deleted"
		_status_label.modulate = Color(0.6, 1.0, 0.6)
		# Return to auth screen.
		G.screens.client_open_screen(
			ScreensMain.ScreenType.AUTH
		)
	else:
		_status_label.text = error
		_status_label.modulate = Color(1.0, 0.4, 0.4)
