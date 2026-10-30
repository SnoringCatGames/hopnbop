extends GutTest
## H51: the loading screen's phases after matchmaking. It used
## to fall between the matchmaking phase text and a bare
## "Connecting..." with no notion of where the wait was; now
## GameSessionManager drives CONNECTING (until this client's
## IDs are assigned) and WAITING (until the match starts), and
## the label follows the phase.
##
## The screen is the real scene; statuses are driven through the
## same entry points the game uses (start_phase,
## _on_matchmaking_progress, show_matchmaking_failure).


const _SCENE := "res://src/ui/screens/loading_screen.tscn"


var _screen: LoadingScreen
var _original_loading_screen: LoadingScreen


func before_each() -> void:
	_original_loading_screen = G.loading_screen
	_screen = load(_SCENE).instantiate()
	add_child_autofree(_screen)


func after_each() -> void:
	G.loading_screen = _original_loading_screen


func _label_text() -> String:
	_screen.update_status_message()
	var label: Label = _screen.get_node("%Label")
	return label.text


func test_connecting_phase_names_the_wait() -> void:
	_screen.start_phase(
		LoadingScreen.ConnectionPhase.CONNECTING, 2)
	assert_eq(
		_label_text(), tr("LOADING.CONNECTING") + " (0s)")


func test_waiting_phase_names_the_wait() -> void:
	_screen.start_phase(
		LoadingScreen.ConnectionPhase.WAITING, 4)
	assert_eq(
		_label_text(), tr("LOADING.WAITING_FOR_PLAYERS"))


func test_matchmaking_phase_still_shows_before_connecting() -> void:
	_screen._on_matchmaking_progress("searching", 1.0, -1.0)
	assert_true(
		_label_text().begins_with(tr("LOADING.SEARCHING")))


func test_connecting_wins_over_the_matchmaking_phase() -> void:
	_screen._on_matchmaking_progress("searching", 1.0, -1.0)
	_screen.start_phase(
		LoadingScreen.ConnectionPhase.CONNECTING, 2)
	assert_eq(
		_label_text(), tr("LOADING.CONNECTING") + " (0s)")


func test_failure_offers_a_way_back_to_the_lobby() -> void:
	_screen.show_matchmaking_failure("LOADING.NO_MATCH_FOUND")
	var retry: Button = _screen.get_node("%RetryButton")
	var cancel: Button = _screen.get_node("%CancelButton")
	assert_true(retry.visible, "retry offered")
	assert_true(cancel.visible, "cancel leaves for the lobby (H19)")


func test_failure_overrides_the_connection_phase() -> void:
	_screen.start_phase(
		LoadingScreen.ConnectionPhase.CONNECTING, 2)
	_screen.show_matchmaking_failure("LOADING.NO_MATCH_FOUND")
	assert_eq(_label_text(), tr("LOADING.NO_MATCH_FOUND"))
