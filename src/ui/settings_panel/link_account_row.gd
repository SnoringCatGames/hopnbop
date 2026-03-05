class_name LinkAccountRow
extends SettingsRow
## A row for linking an OAuth provider to the
## current player account. Shows provider name
## and linked status. Left/right triggers the
## link flow when not yet linked.


var _provider: AuthClient.Provider
var _provider_name: String
var _is_linked := false
var _is_linking := false

@onready var _label: Label = %Label
@onready var _status_label: Label = %StatusLabel


func setup(
	provider: AuthClient.Provider,
	display_name: String,
	is_linked: bool,
) -> void:
	_provider = provider
	_provider_name = display_name
	_is_linked = is_linked


func _ready() -> void:
	super()
	_label.text = _provider_name
	_update_status()


func on_left() -> void:
	_try_link()


func on_right() -> void:
	_try_link()


func _try_link() -> void:
	if _is_linked or _is_linking:
		return

	_is_linking = true
	_status_label.text = "Linking..."

	G.auth_client.link_completed.connect(
		_on_link_completed, CONNECT_ONE_SHOT
	)
	G.auth_client.link_provider(_provider)


func _on_link_completed(
	success: bool,
	error: String,
	_provider_str: String,
) -> void:
	_is_linking = false
	if success:
		_is_linked = true
	_update_status()


func _update_status() -> void:
	if _is_linked:
		_status_label.text = "Linked"
		_status_label.modulate = Color(0.6, 1.0, 0.6)
	else:
		_status_label.text = "Link"
		_status_label.modulate = Color.WHITE
