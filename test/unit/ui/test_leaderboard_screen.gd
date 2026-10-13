extends GutTest
## LeaderboardScreen against a stand-in BackendApiClient: what it asks
## for when it opens, and what it shows for each reply. The stand-in
## replaces G.backend_api_client for each test and sends nothing, the
## way test_crash_reporter.gd replaces Platform.nakama_client.

const _SCENE := "res://src/ui/leaderboard_panel/leaderboard_panel.tscn"
const _TEST_AUTH_FILE := "user://test_leaderboard_screen/auth.cfg"
## The website's colors for ranks 1 to 3.
const _GOLD := Color(0.949, 0.788, 0.298)


## Records the screen's requests instead of sending them.
class FakeBackend extends BackendApiClient:
	var leaderboard_requests := 0
	var standing_requests := 0

	func fetch_leaderboard() -> void:
		leaderboard_requests += 1

	func fetch_own_standing() -> void:
		standing_requests += 1


var _fake: FakeBackend
var _original_backend: BackendApiClient
var _original_token_store
var _original_screen: LeaderboardScreen


func before_each() -> void:
	_original_backend = G.backend_api_client
	_original_token_store = Platform.token_store
	_original_screen = G.leaderboard_screen
	_fake = FakeBackend.new()
	add_child_autofree(_fake)
	G.backend_api_client = _fake
	Platform.token_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)


func after_each() -> void:
	G.backend_api_client = _original_backend
	Platform.token_store = _original_token_store
	G.leaderboard_screen = _original_screen


func test_opening_reads_the_public_list_and_tells_anonymous_players() -> void:
	var screen := _open_screen(true)
	assert_eq(_fake.leaderboard_requests, 1)
	assert_eq(
		_fake.standing_requests, 0,
		"an anonymous player is never listed, so their rank isn't asked")
	assert_true(screen.get_node("%LoadingSpinner").visible)
	var rank_label: Label = screen.get_node("%RankLabel")
	assert_true(rank_label.visible)
	assert_eq(rank_label.text, tr("LEADERBOARD.GUEST_HINT"))


func test_a_signed_in_player_sees_their_rank() -> void:
	var screen := _open_screen(false)
	assert_eq(_fake.standing_requests, 1)
	var rank_label: Label = screen.get_node("%RankLabel")
	assert_false(rank_label.visible, "nothing to say before the reply")
	_fake.own_standing_received.emit({"rank": 3, "best_score": 410})
	assert_true(rank_label.visible)
	assert_eq(rank_label.text, tr("LEADERBOARD.YOUR_RANK") % 3)
	_fake.own_standing_received.emit({"rank": 0, "best_score": 410})
	assert_false(rank_label.visible, "not on the leaderboard: no rank")


func test_rows_show_the_replys_entries_in_order() -> void:
	var screen := _open_screen(false)
	_fake.leaderboard_received.emit(_reply([
		[1, "Moonhopper", 4210],
		[2, "Bunny McBounce", 3895],
		[2, "Pip", 3895],
		[4, "Zap", 2750],
	]))
	assert_false(screen.get_node("%LoadingSpinner").visible)
	assert_eq(_row_texts(screen), [
		["1", "Moonhopper", "4210"],
		["2", "Bunny McBounce", "3895"],
		["2", "Pip", "3895"],
		["4", "Zap", "2750"],
	])
	var first_rank: Label = _row_labels(screen)[0][0]
	assert_eq(
		first_rank.get_theme_color("font_color"), _GOLD,
		"rank 1 is gold, as on the website")
	assert_false(screen.get_node("%StatusLabel").visible)


func test_player_names_are_shown_exactly_as_chosen() -> void:
	# A name is data: never translated, never parsed as markup.
	var screen := _open_screen(false)
	var names := [
		"SETTINGS.LEADERBOARD",
		"[b]bold[/b] <img src=x>",
		"مرحبا",
	]
	var entries := []
	for index in names.size():
		entries.append([index + 1, names[index], 10 - index])
	_fake.leaderboard_received.emit(_reply(entries))
	var rows := _row_labels(screen)
	for index in names.size():
		var name_label: Label = rows[index][1]
		assert_eq(name_label.text, names[index])
		assert_eq(
			name_label.auto_translate_mode,
			Node.AUTO_TRANSLATE_MODE_DISABLED,
			"a name must not be looked up as a translation key")
	assert_ne(
		tr(names[0]), names[0],
		"the first name really is a translation key")


func test_an_empty_board_says_no_scores_yet() -> void:
	var screen := _open_screen(false)
	_fake.leaderboard_received.emit(_reply([]))
	var status: Label = screen.get_node("%StatusLabel")
	assert_true(status.visible)
	assert_eq(status.text, tr("LEADERBOARD.NO_SCORES"))
	assert_eq(_row_texts(screen), [])


func test_a_failed_fetch_says_the_server_was_unreachable() -> void:
	var screen := _open_screen(false)
	_fake.leaderboard_failed.emit("HTTP 503")
	var status: Label = screen.get_node("%StatusLabel")
	assert_true(status.visible)
	assert_eq(status.text, tr("LOADING.CONNECTION_FAILED"))
	assert_false(screen.get_node("%LoadingSpinner").visible)


func test_a_hidden_screen_ignores_replies() -> void:
	var screen := _open_screen(false)
	screen.visible = false
	_fake.leaderboard_received.emit(_reply([[1, "Late", 1]]))
	assert_eq(_row_texts(screen), [])


func test_the_headers_are_translation_keys_with_translations() -> void:
	var screen := _open_screen(false)
	var keys := {
		"%PlayerHeader": "LEADERBOARD.PLAYER",
		"%ScoreHeader": "LEADERBOARD.BEST_SCORE",
	}
	for path: String in keys:
		var key: String = keys[path]
		assert_eq(screen.get_node(path).text, key)
		assert_ne(tr(key), key, "%s has no translation" % key)
	assert_eq(
		screen.get_node("%ScopeLabel").text, tr("SETTINGS.LEADERBOARD"))
	for key in [
		"LEADERBOARD.NO_SCORES",
		"LEADERBOARD.YOUR_RANK",
		"LEADERBOARD.GUEST_HINT",
	]:
		assert_ne(tr(key), key, "%s has no translation" % key)


## Instantiates the screen, visible, and opens it as the anonymous
## or signed-in player.
func _open_screen(is_anonymous: bool) -> LeaderboardScreen:
	Platform.token_store.is_anonymous = is_anonymous
	var screen: LeaderboardScreen = load(_SCENE).instantiate()
	add_child_autofree(screen)
	screen.visible = true
	screen.on_open()
	return screen


## A leaderboard_received payload from [rank, name, score] triples.
func _reply(rows: Array) -> Dictionary:
	var entries: Array[Dictionary] = []
	for row: Array in rows:
		entries.append(
			{"rank": row[0], "display_name": row[1], "score": row[2]})
	return {
		"ok": true,
		"entries": entries,
		"operator": "best",
		"sort_order": "desc",
		"generated_at": "2026-10-12T04:09:20Z",
	}


## The labels of each shown row: [rank, name, score].
func _row_labels(screen: LeaderboardScreen) -> Array:
	var rows := []
	for child in screen.get_node("%ContentContainer").get_children():
		if child.is_queued_for_deletion():
			continue
		var row: HBoxContainer = child.find_children(
			"*", "HBoxContainer", true, false)[0]
		rows.append(row.get_children())
	return rows


func _row_texts(screen: LeaderboardScreen) -> Array:
	var rows := []
	for labels: Array in _row_labels(screen):
		rows.append(labels.map(
			func(label: Label) -> String: return label.text))
	return rows
