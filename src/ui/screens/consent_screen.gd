class_name ConsentScreen
extends PlatformConsentScreen
## Game-side thin wrapper around `PlatformConsentScreen`.
##
## Routes the addon screen's navigation signals through
## hopnbop's `G.*` autoloads + ScreensMain.ScreenType enum.
## Supplies the audio-wired focus / select hooks, the
## Netcode preview-mode auto-consent gate, the current
## legal-version resolver, and the game's icon-scale /
## icon-padding settings.


func _enter_tree() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	G.consent_screen = self
	super._enter_tree()
	consent_accepted.connect(_on_consent_accepted)
	language_picker_requested.connect(
		_on_language_picker_requested)
	terms_link_requested.connect(
		_on_terms_link_requested)
	privacy_link_requested.connect(
		_on_privacy_link_requested)


func _create_input_poller() -> PlatformAnyDeviceInputPoller:
	return AnyDeviceInputPoller.new()


func _should_auto_consent() -> bool:
	return (
		Netcode.is_preview
		and Netcode.is_client
		and Netcode.preview_client_number > 1
	)


func _get_current_legal_version() -> String:
	return LegalVersion.get_current()


func _get_icon_scale() -> float:
	return float(G.settings.icon_scale)


func _get_icon_padding() -> int:
	return int(G.settings.icon_padding)


func _play_focus_sound() -> void:
	if is_instance_valid(G.audio):
		G.audio.play_sound("focus")


func _play_select_sound() -> void:
	if is_instance_valid(G.audio):
		G.audio.play_sound("select")


func _on_consent_accepted() -> void:
	if G.settings.skip_auth:
		G.screens.client_open_screen(
			ScreensMain.ScreenType.LOBBY)
	else:
		G.screens.client_open_screen(
			ScreensMain.ScreenType.AUTH)


func _on_language_picker_requested() -> void:
	G.language_screen.set_return_screen(
		ScreensMain.ScreenType.CONSENT)
	G.screens.client_open_screen(
		ScreensMain.ScreenType.LANGUAGE)


func _on_terms_link_requested() -> void:
	_open_legal_screen(
		ScreensMain.ScreenType.TERMS)


func _on_privacy_link_requested() -> void:
	_open_legal_screen(
		ScreensMain.ScreenType.PRIVACY)


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
