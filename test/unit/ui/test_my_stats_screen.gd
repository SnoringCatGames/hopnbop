extends GutTest
## MyStatsScreen against a stand-in BackendApiClient: when it asks for
## the player's stats, and what it shows for each reply. Before
## 2026-10-12 it read the account profile under a key that reply
## never had, and always said "No data".

const _SCENE := "res://src/ui/screens/my_stats_screen.tscn"
const _TEST_AUTH_FILE := "user://test_my_stats_screen/auth.cfg"
const _TOKEN_LIFETIME_SEC := 3600
const _WIN_COLOR := Color(0.6, 1.0, 0.6)
const _LOSS_COLOR := Color(1.0, 0.4, 0.4)


## Records the screen's requests instead of sending them.
class FakeBackend extends BackendApiClient:
	var stats_requests := 0

	func fetch_my_stats() -> void:
		stats_requests += 1


var _fake: FakeBackend
var _original_backend: BackendApiClient
var _original_token_store
var _original_screen: MyStatsScreen


func before_each() -> void:
	_original_backend = G.backend_api_client
	_original_token_store = Platform.token_store
	_original_screen = G.my_stats_screen
	_fake = FakeBackend.new()
	add_child_autofree(_fake)
	G.backend_api_client = _fake
	Platform.token_store = PlatformAuthTokenStore.new(_TEST_AUTH_FILE)


func after_each() -> void:
	G.backend_api_client = _original_backend
	Platform.token_store = _original_token_store
	G.my_stats_screen = _original_screen


func test_without_a_session_it_asks_the_player_to_sign_in() -> void:
	var screen := _open_screen(false)
	assert_eq(_fake.stats_requests, 0)
	var status: Label = screen.get_node("%StatusLabel")
	assert_true(status.visible)
	assert_eq(status.text, tr("STATS.SIGN_IN_REQUIRED"))


func test_a_signed_in_player_gets_their_stats() -> void:
	var screen := _open_screen(true)
	assert_eq(_fake.stats_requests, 1)
	assert_true(screen.get_node("%LoadingSpinner").visible)
	_fake.my_stats_received.emit({
		"best_score": 4210,
		"rank": 3,
		"matches": 12,
		"wins": 5,
		"kills": 30,
		"bumps": 41,
		"recent_matches": [
			{"is_winner": true, "score": 4210, "kills": 3, "bumps": 4},
			{"is_winner": false, "score": 900, "kills": 1, "bumps": 2},
		],
	})
	assert_false(screen.get_node("%LoadingSpinner").visible)
	var rows := _row_texts(screen)
	assert_eq(rows.slice(0, 6), [
		[tr("LEADERBOARD.BEST_SCORE"), "4210"],
		[tr("STATS.RANK"), "#3"],
		[tr("STATS.MATCHES"), "12"],
		[tr("STATS.WINS"), "5"],
		[tr("STATS.KILLS"), "30"],
		[tr("STATS.BUMPS"), "41"],
	])
	assert_eq(rows.slice(6), [
		[tr("STATS.RECENT_MATCHES")],
		["", tr("STATS.SCORE"), tr("STATS.KILLS"), tr("STATS.BUMPS")],
		[tr("STATS.WIN"), "4210", "3", "4"],
		[tr("STATS.LOSS"), "900", "1", "2"],
	])
	var results := _result_labels(screen)
	assert_eq(results[0].get_theme_color("font_color"), _WIN_COLOR)
	assert_eq(results[1].get_theme_color("font_color"), _LOSS_COLOR)


func test_a_new_player_sees_dashes_and_no_matches() -> void:
	var screen := _open_screen(true)
	_fake.my_stats_received.emit({
		"best_score": -1,
		"rank": 0,
		"matches": 0,
		"wins": 0,
		"kills": 0,
		"bumps": 0,
		"recent_matches": [],
	})
	var rows := _row_texts(screen)
	assert_eq(rows[0], [tr("LEADERBOARD.BEST_SCORE"), "-"])
	assert_eq(rows[1], [tr("STATS.RANK"), "-"])
	assert_eq(rows[-1], [tr("STATS.NO_MATCHES")])


func test_failures_say_what_happened() -> void:
	var screen := _open_screen(true)
	var status: Label = screen.get_node("%StatusLabel")
	_fake.my_stats_failed.emit(BackendApiClient.NOT_SIGNED_IN)
	assert_eq(status.text, tr("STATS.SIGN_IN_REQUIRED"))
	screen.on_open()
	_fake.my_stats_failed.emit("server down (status=503)")
	assert_true(status.visible)
	assert_eq(status.text, tr("LOADING.CONNECTION_FAILED"))
	assert_false(screen.get_node("%LoadingSpinner").visible)


func test_every_label_key_has_a_translation() -> void:
	for key in [
		"STATS.RANK",
		"STATS.MATCHES",
		"STATS.WINS",
		"STATS.KILLS",
		"STATS.BUMPS",
		"STATS.RECENT_MATCHES",
		"STATS.NO_MATCHES",
		"STATS.SCORE",
		"STATS.WIN",
		"STATS.LOSS",
		"STATS.SIGN_IN_REQUIRED",
	]:
		assert_ne(tr(key), key, "%s has no translation" % key)


## Instantiates the screen, visible, and opens it with or without a
## valid session.
func _open_screen(is_signed_in: bool) -> MyStatsScreen:
	if is_signed_in:
		Platform.token_store.jwt_token = "test.jwt.token"
		Platform.token_store.expires_at = (
			int(Time.get_unix_time_from_system()) + _TOKEN_LIFETIME_SEC)
	var screen: MyStatsScreen = load(_SCENE).instantiate()
	add_child_autofree(screen)
	screen.visible = true
	screen.on_open()
	return screen


## The texts of each content row: a stat row's label and value, a
## match row's four cells, or a lone heading's text.
func _row_texts(screen: MyStatsScreen) -> Array:
	var rows := []
	for child in screen.get_node("%ContentContainer").get_children():
		if child.is_queued_for_deletion() or child is HSeparator:
			continue
		if child is Label:
			rows.append([(child as Label).text])
			continue
		rows.append(child.get_children().map(
			func(label: Label) -> String: return label.text))
	return rows


## The result labels of the match rows, after the column headings.
func _result_labels(screen: MyStatsScreen) -> Array[Label]:
	var labels: Array[Label] = []
	var is_past_headings := false
	for child in screen.get_node("%ContentContainer").get_children():
		if not (child is HBoxContainer) or child.get_child_count() != 4:
			continue
		if not is_past_headings:
			is_past_headings = true
			continue
		labels.append(child.get_child(0))
	return labels
