class_name AuthScreen
extends PlatformAuthScreen
## Game-side thin wrapper around `PlatformAuthScreen`.
##
## Subscribes to the addon screen's navigation +
## state-reset signals and routes them through hopnbop's
## `G.*` autoloads. Plugs in hopnbop's audio-wired focus
## navigator and the Netcode preview-mode force-anonymous
## check.


func _enter_tree() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	G.auth_screen = self
	super._enter_tree()
	lobby_navigation_requested.connect(
		_on_lobby_navigation_requested)
	force_anonymous_state_reset_requested.connect(
		_on_force_anonymous_state_reset)


func _create_navigator() -> PlatformScreenFocusNavigator:
	return ScreenFocusNavigator.new()


func _should_force_anonymous() -> bool:
	return (
		Netcode.is_preview
		and Netcode.is_client
		and Netcode.preview_client_number > 1
	)


func _on_lobby_navigation_requested() -> void:
	G.screens.client_open_screen(
		ScreensMain.ScreenType.LOBBY)


func _on_force_anonymous_state_reset() -> void:
	G.profile_image_cache.clear()
	G.friends_notification_poller.reset()
	G.party_manager.reset()
	G.client_session.clear_latest_state()
