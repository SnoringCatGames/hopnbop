extends GutTest
## H130: the adjective reveal must freeze and pop over the
## list that is on screen. At aspect 1.3 or more the HUD
## shows the vertical list and hides the horizontal one.
## The reveal used to read only the horizontal list, so the
## visible displays showed the new adjectives at once and
## the popups were parented to hidden displays.


const _HUD_SCENE := "res://src/ui/hud/hud.tscn"
const _CELEBRATION_SCENE := (
	"res://src/ui/celebration/match_end_celebration.tscn")
const _DISPLAY_SCENE := "res://src/ui/hud/player_display.tscn"
const _PLAYER_ID := 1

var _saved_is_server := false
var _saved_hud: Hud
var _saved_celebration: MatchEndCelebration
var _saved_match_state: GameMatchState
var _saved_game_panel: GamePanel
var _saved_level: Level
var _hud: Hud
var _celebration: MatchEndCelebration
var _fake_game_panel: GamePanel


func before_each() -> void:
	_saved_is_server = Netcode.is_server
	_saved_hud = G.hud
	_saved_celebration = G.celebration
	_saved_match_state = G.match_state
	_saved_game_panel = G.game_panel
	_saved_level = G.level
	Netcode.is_server = false
	G.match_state = GameMatchState.new()
	_fake_game_panel = GamePanel.new()
	G.game_panel = _fake_game_panel
	G.level = null


func after_each() -> void:
	Netcode.is_server = _saved_is_server
	G.hud = _saved_hud
	G.celebration = _saved_celebration
	G.match_state = _saved_match_state
	G.game_panel = _saved_game_panel
	G.level = _saved_level
	_hud = null
	_celebration = null
	if is_instance_valid(_fake_game_panel):
		_fake_game_panel.free()
	_fake_game_panel = null


func test_reveal_freezes_both_lists() -> void:
	var displays := await _set_up_reveal(true)
	_celebration.reveal_adjectives({_PLAYER_ID: "Swift"})
	assert_true(
		displays[0].is_adjective_frozen,
		"the hidden list is frozen in case of a resize")
	assert_true(
		displays[1].is_adjective_frozen,
		"the visible list is frozen so replication "
		+ "does not spoil the reveal")


func test_reveal_popup_opens_on_visible_list() -> void:
	var displays := await _set_up_reveal(true)
	_celebration.reveal_adjectives({_PLAYER_ID: "Swift"})
	await get_tree().create_timer(
		2.2, true, false, true).timeout
	assert_false(
		displays[0].is_adjective_hidden,
		"no popup opens on the hidden list")
	assert_true(
		displays[1].is_adjective_hidden,
		"the popup opens on the visible list")
	assert_true(
		_has_reveal_popup(displays[1]),
		"the popup is parented to the visible display")
	assert_false(
		_has_reveal_popup(displays[0]),
		"the popup is not parented to the hidden display")


## Builds a HUD with the vertical list showing (the wide
## window case when use_vertical is true, the narrow case
## otherwise), one display per list, and a celebration.
## Returns [horizontal display, vertical display].
func _set_up_reveal(
	use_vertical: bool,
) -> Array:
	var next_timer_id: int = Netcode.time._next_id
	_hud = load(_HUD_SCENE).instantiate()
	add_child_autofree(_hud)
	_celebration = load(_CELEBRATION_SCENE).instantiate()
	add_child_autofree(_celebration)
	await wait_process_frames(3)
	# The overhead labels tick on Netcode.time. That tick
	# outlives the HUD in this test, so cancel the timers
	# this HUD started.
	for timer_id in range(
		next_timer_id, Netcode.time._next_id
	):
		Netcode.time.clear_timeout(timer_id)
	var vertical: PlayerList = _hud.get_node(
		"MarginContainer/RightContent/PlayerListVertical")
	_hud.player_list.visible = not use_vertical
	vertical.visible = use_vertical
	_hud.set("_is_vertical_layout", use_vertical)
	var horizontal_display := _add_display(_hud.player_list)
	var vertical_display := _add_display(vertical)
	# Keep the injected displays. With no level, the lists
	# would otherwise drop them on the next refresh.
	for list: PlayerList in [_hud.player_list, vertical]:
		if G.match_state.players_updated.is_connected(
			list._update_displays
		):
			G.match_state.players_updated.disconnect(
				list._update_displays)
		if _fake_game_panel.lobby_players_updated.is_connected(
			list._update_displays
		):
			_fake_game_panel.lobby_players_updated.disconnect(
				list._update_displays)
	return [horizontal_display, vertical_display]


func _add_display(list: PlayerList) -> PlayerDisplay:
	var display: PlayerDisplay = (
		load(_DISPLAY_SCENE).instantiate())
	display.set_player_id(_PLAYER_ID)
	list.add_child(display)
	list._player_displays[_PLAYER_ID] = display
	return display


func _has_reveal_popup(display: PlayerDisplay) -> bool:
	for child in display.get_children():
		if child is AdjectiveRevealPopup:
			return true
	return false
