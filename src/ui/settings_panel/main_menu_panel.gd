class_name MainMenuPanel
extends SidePanel
## Top-level main menu panel. Contains only a
## close row and trigger rows for sub-panels.


@export var _close_row_scene: PackedScene
@export var _quit_row_scene: PackedScene
@export var _sub_panel_trigger_row_scene: PackedScene
@export var _screen_trigger_row_scene: PackedScene
@export var _settings_panel_scene: PackedScene
@export var _level_pref_panel_scene: PackedScene
@export var _friends_panel_scene: PackedScene
@export var _party_lobby_panel_scene: PackedScene
@export var _account_panel_scene: PackedScene
@export var _info_panel_scene: PackedScene

@export_group("Row Icons")
@export var icon_settings: Texture2D
@export var icon_levels: Texture2D
@export var icon_friends: Texture2D
# TODO: replace with a dedicated party_icon.png asset.
# Currently reuses friends_icon.png as a placeholder
# per the multi-game roadmap Stage 5 sign-off.
@export var icon_party: Texture2D
@export var icon_account: Texture2D
@export var icon_info: Texture2D
@export var icon_leaderboard: Texture2D
@export var icon_my_stats: Texture2D
@export var icon_quit: Texture2D


func build_ui() -> void:
	# Top padding.
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 30)
	_row_container.add_child(top_spacer)

	# Close row.
	var close_row: CloseRow = (
		_close_row_scene.instantiate())
	close_row.setup(self)
	_row_container.add_child(close_row)
	_connect_row_clicked(close_row)

	# Spacer below close button.
	var close_spacer := Control.new()
	close_spacer.custom_minimum_size = (
		Vector2(0, 20))
	_row_container.add_child(close_spacer)

	# Account trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.ACCOUNT"),
		_account_panel_scene,
		icon_account)

	# Friends trigger (hidden for anonymous players).
	if not G.auth_token_store.is_anonymous:
		var friends_row := _add_sub_panel_trigger_row(
			tr("SETTINGS.FRIENDS"),
			_friends_panel_scene,
			icon_friends)
		_connect_friends_badge(friends_row)

		# Party trigger. Same anonymous gate as
		# Friends since parties are friend-driven.
		var party_row := _add_sub_panel_trigger_row(
			tr("SETTINGS.PARTY"),
			_party_lobby_panel_scene,
			icon_party)
		_connect_party_badge(party_row)

	# Settings trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.SETTINGS"),
		_settings_panel_scene,
		icon_settings)

	# Levels trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.LEVELS"),
		_level_pref_panel_scene,
		icon_levels)

	# Leaderboard screen trigger (all players).
	_add_screen_trigger_row(
		tr("SETTINGS.LEADERBOARD"),
		ScreensMain.ScreenType.LEADERBOARD,
		icon_leaderboard)

	# My Stats trigger (non-anonymous only).
	if not G.auth_token_store.is_anonymous:
		_add_screen_trigger_row(
			tr("SETTINGS.MY_STATS"),
			ScreensMain.ScreenType.MY_STATS,
			icon_my_stats)

	# Info trigger.
	_add_sub_panel_trigger_row(
		tr("SETTINGS.INFO"),
		_info_panel_scene,
		icon_info)

	# Quit row.
	var quit_row: QuitRow = (
		_quit_row_scene.instantiate())
	quit_row.set_icon(icon_quit)
	_row_container.add_child(quit_row)
	_connect_row_clicked(quit_row)

	# Bottom padding.
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = (
		Vector2(0, 30))
	_row_container.add_child(bottom_spacer)


func _add_sub_panel_trigger_row(
	display_name: String,
	panel_scene: PackedScene,
	icon: Texture2D = null,
) -> SubPanelTriggerRow:
	var row: SubPanelTriggerRow = (
		_sub_panel_trigger_row_scene.instantiate())
	if icon != null:
		row.set_icon(icon)
	row.setup(display_name, panel_scene, self)
	_row_container.add_child(row)
	_connect_row_clicked(row)
	return row


func _connect_friends_badge(
	row: SubPanelTriggerRow,
) -> void:
	if not is_instance_valid(row):
		return
	var poller := G.friends_notification_poller
	row.set_badge_visible(
		poller.unseen_count > 0)
	poller.unseen_count_changed.connect(
		func(count: int) -> void:
			if is_instance_valid(row):
				row.set_badge_visible(count > 0))


func _connect_party_badge(
	row: SubPanelTriggerRow,
) -> void:
	if not is_instance_valid(row):
		return
	var pm := G.party_manager
	if not is_instance_valid(pm):
		return
	row.set_badge_visible(
		pm.has_pending_invite())
	# party_updated also fires when the pending-
	# invite list changes (see PartyManager.
	# _remove_pending_invite and
	# _on_party_status_received).
	pm.party_updated.connect(
		func(_data: Dictionary) -> void:
			if is_instance_valid(row):
				row.set_badge_visible(
					pm.has_pending_invite()))
	pm.party_disbanded.connect(
		func() -> void:
			if is_instance_valid(row):
				row.set_badge_visible(
					pm.has_pending_invite()))
	pm.invite_received.connect(
		func(_inv: Dictionary) -> void:
			if is_instance_valid(row):
				row.set_badge_visible(true))


func _add_screen_trigger_row(
	display_name: String,
	screen_type: ScreensMain.ScreenType,
	icon: Texture2D = null,
) -> void:
	var row: ScreenTriggerRow = (
		_screen_trigger_row_scene.instantiate())
	if icon != null:
		row.set_icon(icon)
	row.setup(display_name, screen_type, self)
	_row_container.add_child(row)
	_connect_row_clicked(row)
