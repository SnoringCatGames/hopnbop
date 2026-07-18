class_name PlayerDisplay
extends PanelContainer
## Individual player info panel showing adjective, name, and score.

# Floating score popup settings.
const _POPUP_MIN_SCORE_CHANGE := 10
const _POPUP_OFFSET := Vector2(-15.0, 0.0) # Small gap right of score.
const _POPUP_INITIAL_SCALE := 0.1
const _POPUP_TARGET_SCALE := 1.95
const _POPUP_OVERSHOOT_SCALE := 2.8
const _POPUP_GROW_DURATION_SEC := 0.12
const _POPUP_SETTLE_DURATION_SEC := 0.6
const _POPUP_FADE_IN_DURATION_SEC := 0.1
const _POPUP_VISIBLE_DURATION_SEC := 0.9
const _POPUP_FADE_OUT_DURATION_SEC := 0.3
const _POPUP_SLIDE_OFFSET := Vector2(15.0, -25.0) # Drift right and up.

# Score counter animation settings.
const _SCORE_INCREMENT_INTERVAL_SEC := 0.02
const _PROFILE_IMAGE_SIZE := 32

var player_id: int = 0
var is_adjective_hidden := false
var is_adjective_frozen := false

var _displayed_score: int = 0
var _target_score: int = 0
var _score_update_timer: float = 0.0
var _has_initialized_score: bool = false
var _profile_image: ProfileImageDisplay
var _is_profile_image_set := false
var _crown_label: Label

# Display-only mode: render from party-member data instead of live
# match state. Used for remote party members shown in the lobby, who
# have no spawned player / match state on this client.
var _is_display_only := false
var _party_member: Dictionary = {}


func _ready() -> void:
	_profile_image = ProfileImageDisplay.new()
	_profile_image.image_size = _PROFILE_IMAGE_SIZE
	_profile_image.size_flags_horizontal = (
		Control.SIZE_SHRINK_CENTER)
	$VBoxContainer.add_child(_profile_image)
	$VBoxContainer.move_child(_profile_image, 0)

	# Party-leader crown, sits above the profile image. Hidden
	# unless this display's player is the current party's leader.
	# Matches the ★ used in the party side panel.
	_crown_label = Label.new()
	_crown_label.text = "★"
	_crown_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	_crown_label.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.3))
	_crown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crown_label.visible = false
	$VBoxContainer.add_child(_crown_label)
	$VBoxContainer.move_child(_crown_label, 0)


func set_player_id(p_player_id: int) -> void:
	player_id = p_player_id
	_is_display_only = false
	_has_initialized_score = false
	_is_profile_image_set = false


## Render this display from party-member data (user_id, display_name /
## username, role) rather than a live match player. Used for remote
## party members shown in the lobby nameplate row. No score; leader
## crown driven by the member's role; anonymous avatar (remote members
## carry no avatar URL in party state).
func set_party_member(member: Dictionary) -> void:
	_is_display_only = true
	_party_member = member
	player_id = 0
	# Render immediately so the nameplate appears at once; _process
	# keeps it current after that.
	_update_display_only()


func _process(delta: float) -> void:
	_update_display(delta)


func _update_display(delta: float) -> void:
	if _is_display_only:
		_update_display_only()
		return
	if player_id == 0:
		return

	var player_match_state := G.get_player_match_state(player_id)
	if not player_match_state:
		return

	# Set profile image once when state is available.
	if not _is_profile_image_set:
		_profile_image.set_player(
			player_id,
			G.get_peer_anonymous_color(
				player_match_state.peer_id))
		_is_profile_image_set = true

	# Update name and adjective.
	%Name.text = player_match_state.bunny_name
	if not is_adjective_frozen:
		%Adjective.text = (
			player_match_state.adjective)
	%Adjective.visible = not is_adjective_hidden

	# Crown the party leader's nameplate.
	_crown_label.visible = _resolve_is_display_leader()

	# Hide score in lobby.
	%Score.visible = not G.is_lobby_active

	# Handle score updates.
	var actual_score: int = player_match_state.score
	if actual_score != _target_score:
		var score_delta := actual_score - _target_score
		_target_score = actual_score

		var min_score_change_for_popup := (
			1
			if G.settings.use_simple_score
			else _POPUP_MIN_SCORE_CHANGE
		)

		# On first assignment, snap immediately.
		if not _has_initialized_score:
			_displayed_score = actual_score
			_has_initialized_score = true
		# Spawn popup for any qualifying score increase.
		if score_delta >= min_score_change_for_popup:
			_spawn_score_popup(score_delta)

	# Animate displayed score toward target.
	if _displayed_score != _target_score:
		_score_update_timer += delta
		while (_score_update_timer
			>= _SCORE_INCREMENT_INTERVAL_SEC
			and _displayed_score != _target_score):
			_score_update_timer -= _SCORE_INCREMENT_INTERVAL_SEC
			if _displayed_score < _target_score:
				_displayed_score += 1
			else:
				_displayed_score -= 1

	%Score.text = "%d" % _displayed_score

	# White in lobby, player color in match.
	var label_color := (
		Color.WHITE if G.is_lobby_active
		else player_match_state.label_color
	)
	%Name.add_theme_color_override(
		"font_color", label_color)
	%Adjective.add_theme_color_override(
		"font_color", label_color)
	%Score.add_theme_color_override(
		"font_color", label_color)

	var outline_color := (
		Color.TRANSPARENT if G.is_lobby_active
		else player_match_state.outline_color
	)
	%Name.add_theme_color_override(
		"font_outline_color", outline_color)
	%Adjective.add_theme_color_override(
		"font_outline_color", outline_color)
	%Score.add_theme_color_override(
		"font_outline_color", outline_color)


## Whether this display's player belongs to the current party's
## leader account. Drives the leader crown.
func _resolve_is_display_leader() -> bool:
	if not is_instance_valid(G.party_manager):
		return false
	if not G.party_manager.is_in_party():
		return false
	var leader_id: String = (
		G.party_manager.current_party.get("leader_id", ""))
	if leader_id.is_empty():
		return false
	var account_id := _resolve_account_id()
	return not account_id.is_empty() and account_id == leader_id


## The Nakama account id backing this display's player, or "" when it
## can't be resolved. In a networked match the server distributes a
## player_id -> backend account map; in the lobby every player is
## local and shares this client's account.
func _resolve_account_id() -> String:
	if (G.is_networked_level_active
			and is_instance_valid(G.client_session)):
		return str(
			G.client_session.backend_player_id_map.get(
				player_id, ""))
	if G.is_lobby_active:
		return Platform.token_store.player_id
	return ""


func _update_display_only() -> void:
	var display_name: String = _party_member.get("display_name", "")
	if display_name.is_empty():
		display_name = _party_member.get("username", "")
	if display_name.is_empty():
		display_name = _party_member.get("user_id", "")
	%Name.text = display_name
	%Name.add_theme_color_override("font_color", Color.WHITE)
	%Name.add_theme_color_override(
		"font_outline_color", Color.TRANSPARENT)
	%Adjective.visible = false
	%Score.visible = false
	# The member's role tells us the leader directly (no account-id
	# resolution needed for a party member).
	_crown_label.visible = (
		_party_member.get("role", "") == "leader")
	# Anonymous, per-member-tinted avatar: remote party members carry
	# no avatar URL in party state, so we can't show their real image.
	if not _is_profile_image_set:
		var uid: String = _party_member.get("user_id", "")
		_profile_image.set_from_url(
			hash(uid), "", _member_color(uid))
		_is_profile_image_set = true


func _member_color(uid: String) -> Color:
	if uid.is_empty():
		return Color(0.5, 0.5, 0.5)
	var hue := float(hash(uid) % 360) / 360.0
	return Color.from_hsv(hue, 0.5, 0.9)


func _spawn_score_popup(score_delta: int) -> void:
	# Create a wrapper that escapes PanelContainer layout.
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.top_level = true

	# Create popup label.
	var popup := Label.new()
	popup.text = "+%d" % score_delta
	popup.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER)
	popup.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER)

	# Copy styling from score label.
	popup.add_theme_constant_override(
		"outline_size",
		%Score.get_theme_constant("outline_size")
	)
	var label_color: Color = (
		%Score.get_theme_color("font_color"))
	popup.add_theme_color_override(
		"font_color", label_color)
	var outline_color: Color = (
		%Score.get_theme_color(
			"font_outline_color"))
	popup.add_theme_color_override(
		"font_outline_color", outline_color)

	# Add wrapper as child of PlayerDisplay, then label as child of wrapper.
	add_child(wrapper)
	wrapper.add_child(popup)

	# Position wrapper at the right edge of the score label, vertically
	# centered.
	var score_rect: Rect2 = %Score.get_global_rect()
	wrapper.position = Vector2(
		score_rect.position.x + score_rect.size.x,
		score_rect.get_center().y,
	)

	# Small offset gap from score label edge.
	popup.position = _POPUP_OFFSET

	# Defer pivot_offset assignment until label size is calculated.
	_setup_popup_pivot.call_deferred(popup)

	# Initial state.
	popup.scale = Vector2.ONE * _POPUP_INITIAL_SCALE
	popup.modulate.a = 0.0

	# Animate.
	var tween := create_tween()
	tween.set_parallel(true)

	# Fade in.
	tween.tween_property(
		popup, "modulate:a", 1.0, _POPUP_FADE_IN_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Scale: quick grow to overshoot.
	tween.tween_property(
		popup, "scale",
		Vector2.ONE * _POPUP_OVERSHOOT_SCALE,
		_POPUP_GROW_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Scale: elastic settle back to target.
	tween.tween_property(
		popup, "scale",
		Vector2.ONE * _POPUP_TARGET_SCALE,
		_POPUP_SETTLE_DURATION_SEC
	).set_ease(Tween.EASE_OUT).set_trans(
		Tween.TRANS_ELASTIC,
	).set_delay(_POPUP_GROW_DURATION_SEC)

	# Slide away and up (relative to popup's current position).
	var total_duration := (
		_POPUP_VISIBLE_DURATION_SEC
		+ _POPUP_FADE_OUT_DURATION_SEC)
	tween.tween_property(
		popup, "position",
		_POPUP_SLIDE_OFFSET,
		total_duration
	).as_relative().set_ease(
		Tween.EASE_IN_OUT,
	).set_trans(Tween.TRANS_QUAD)

	# Fade out after delay.
	tween.tween_property(
		popup, "modulate:a", 0.0, _POPUP_FADE_OUT_DURATION_SEC
	).set_ease(Tween.EASE_IN).set_trans(
		Tween.TRANS_QUAD,
	).set_delay(_POPUP_VISIBLE_DURATION_SEC)

	# Cleanup - free the wrapper (which also frees the popup child).
	tween.tween_callback(
		wrapper.queue_free,
	).set_delay(total_duration)


func _setup_popup_pivot(popup: Label) -> void:
	# Center the pivot for proper scaling from center.
	popup.pivot_offset = popup.size / 2.0
	# Adjust position so label appears centered on calculated position.
	popup.position -= popup.size / 2.0


