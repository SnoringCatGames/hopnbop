extends GutTest
## The Log Out row is always offered (H63): with an expired access
## token the player still has to be able to forget this device, and
## log_out clears locally when the server announce fails. It used
## to be hidden in exactly that state, stranding the identity.


const _PANEL_PATH := "res://src/ui/settings_panel/account_panel.tscn"
const _TEST_AUTH_FILE := (
	"user://test_account_panel_log_out.cfg")


var _original_store: PlatformAuthTokenStore


func before_each() -> void:
	_original_store = Platform.token_store


func after_each() -> void:
	Platform.token_store = _original_store


func test_log_out_row_offered_with_an_expired_token() -> void:
	_install_store(int(Time.get_unix_time_from_system()) - 60)

	var panel := _build_panel()

	assert_not_null(_find_log_out_row(panel),
		"expired token still gets the Log Out row")


func test_log_out_row_offered_with_a_valid_token() -> void:
	_install_store(int(Time.get_unix_time_from_system()) + 3600)

	var panel := _build_panel()

	assert_not_null(_find_log_out_row(panel))


## A non-guest store whose access token expired an hour ago or
## expires an hour from now.
func _install_store(expires_at: int) -> void:
	var store := PlatformAuthTokenStore.new(_TEST_AUTH_FILE)
	store.provider = "google"
	store.player_id = "test-player"
	store.expires_at = expires_at
	store.jwt_token = "test.jwt.token"
	Platform.token_store = store


func _build_panel() -> AccountPanel:
	var panel: AccountPanel = load(_PANEL_PATH).instantiate()
	add_child_autofree(panel)
	panel.build_ui()
	return panel


func _find_log_out_row(node: Node) -> LogOutRow:
	for child in node.get_children():
		if child is LogOutRow:
			return child
		var found := _find_log_out_row(child)
		if found != null:
			return found
	return null
