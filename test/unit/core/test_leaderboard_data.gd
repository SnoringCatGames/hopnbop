extends GutTest
## The in-game leaderboard's and My Stats' data path: the URL of the
## platform runtime's public leaderboard route, and how
## BackendApiClient reads that route's reply and the stats RPCs'
## replies. Pure functions only; nothing here touches the network.

const _PUBLIC_PATH := "/snoringcat/leaderboard"
const _PROD_BASE_URL := "https://nakama.snoringcat.games"
const _PLATFORM_FIELDS: Array[String] = [
	"nakama_scheme",
	"nakama_host",
	"nakama_port",
]
const _HTTP_OK := 200

var _client: BackendApiClient
var _saved_platform := {}


func before_each() -> void:
	_client = BackendApiClient.new()
	for field in _PLATFORM_FIELDS:
		_saved_platform[field] = Platform.get(field)


func after_each() -> void:
	_client.free()
	for field in _PLATFORM_FIELDS:
		Platform.set(field, _saved_platform[field])


func test_public_leaderboard_url_needs_no_credential() -> void:
	var url: String = Platform.get_public_leaderboard_url("ffa", 100)
	assert_eq(
		url,
		"%s%s?game_id=%s&leaderboard=ffa&limit=100"
		% [_PROD_BASE_URL, _PUBLIC_PATH, Platform.game_id],
	)
	assert_eq(Platform.PUBLIC_LEADERBOARD_PATH, _PUBLIC_PATH)
	assert_false(url.contains("http_key"), url)
	assert_false(url.contains("/v2/rpc/"), url)


func test_public_leaderboard_url_encodes_its_arguments() -> void:
	var url: String = Platform.get_public_leaderboard_url("a b&c", 7)
	assert_string_contains(url, "leaderboard=a%20b%26c&limit=7")


func test_base_url_keeps_a_port_other_than_the_default() -> void:
	# Before SDK 0.7.0 the port was dropped, so a local stack's URLs
	# went to port 80.
	var cases := [
		["http", "127.0.0.1", 7350, "http://127.0.0.1:7350"],
		["http", "127.0.0.1", 80, "http://127.0.0.1"],
		["https", "nakama.example", 443, "https://nakama.example"],
		["https", "nakama.example", 8443, "https://nakama.example:8443"],
	]
	for case_values: Array in cases:
		Platform.nakama_scheme = case_values[0]
		Platform.nakama_host = case_values[1]
		Platform.nakama_port = case_values[2]
		assert_eq(Platform.get_nakama_base_url(), case_values[3])
		assert_true(
			Platform.get_version_check_url().begins_with(case_values[3]),
			"the version check shares the base URL")


func test_parse_reads_entries_in_board_order() -> void:
	var parsed := _client.parse_public_leaderboard(_HTTP_OK, JSON.stringify({
		"version": 1,
		"game_id": "hopnbop",
		"leaderboard": "ffa",
		"sort_order": "desc",
		"operator": "best",
		"next_reset_at": null,
		"generated_at": "2026-10-12T04:09:20Z",
		"entries": [
			{"rank": 1, "display_name": "Moonhopper", "score": 4210},
			{"rank": 2, "display_name": "  Bunny  ", "score": 3895},
			{"rank": 2, "display_name": "Pip", "score": 3895},
		],
	}))
	assert_true(parsed.ok, str(parsed))
	assert_eq(parsed.entries, [
		{"rank": 1, "display_name": "Moonhopper", "score": 4210},
		{"rank": 2, "display_name": "Bunny", "score": 3895},
		{"rank": 2, "display_name": "Pip", "score": 3895},
	])
	assert_eq(parsed.operator, "best")
	assert_eq(parsed.sort_order, "desc")
	assert_eq(parsed.generated_at, "2026-10-12T04:09:20Z")
	assert_true(parsed.entries[0].rank is int, "ranks are ints")
	assert_true(parsed.entries[0].score is int, "scores are ints")


func test_parse_rejects_a_failed_request() -> void:
	for status in [0, 400, 429, 503]:
		var parsed := _client.parse_public_leaderboard(
			status, '{"version":1,"entries":[]}')
		assert_false(parsed.ok, "status %d" % status)
		assert_string_contains(str(parsed.error), str(status))


func test_parse_rejects_an_unexpected_body() -> void:
	var bodies := [
		"",
		"not json",
		"[]",
		'{"entries":[]}',
		'{"version":2,"entries":[]}',
		'{"version":"1","entries":[]}',
		'{"version":1}',
		'{"version":1,"entries":{}}',
	]
	for body: String in bodies:
		var parsed := _client.parse_public_leaderboard(_HTTP_OK, body)
		assert_false(parsed.ok, "accepted %s" % body)


func test_parse_drops_malformed_entries() -> void:
	var parsed := _client.parse_public_leaderboard(_HTTP_OK, JSON.stringify({
		"version": 1,
		"entries": [
			"not an object",
			{"rank": 1, "score": 9},
			{"rank": 1, "display_name": "   ", "score": 9},
			{"rank": "1", "display_name": "Text Rank", "score": 9},
			{"rank": 1, "display_name": "No Score"},
			{"rank": 1, "display_name": 7, "score": 9},
			{"rank": 2, "display_name": "Kept", "score": 8},
		],
	}))
	assert_true(parsed.ok)
	assert_eq(parsed.entries, [
		{"rank": 2, "display_name": "Kept", "score": 8},
	])


func test_standing_reads_rank_and_best_score() -> void:
	assert_eq(
		_client.parse_player_standing(
			{"player_id": "p", "best_score": 410.0, "rank": 3.0}),
		{"rank": 3, "best_score": 410},
	)


func test_standing_without_a_record() -> void:
	var expected := {"rank": 0, "best_score": -1}
	# The runtime's reply before the first match.
	assert_eq(
		_client.parse_player_standing({
			"player_id": "p",
			"best_score": null,
			"rank": null,
			"rating": 1500.0,
			"matches": 0.0,
		}),
		expected,
	)
	# A runtime older than best_score and rank: rating alone is not
	# a best score.
	assert_eq(
		_client.parse_player_standing({"rating": 1500.0}), expected)
	assert_eq(_client.parse_player_standing(null), expected)
	assert_eq(_client.parse_player_standing("nope"), expected)


func test_my_stats_use_the_runtimes_totals() -> void:
	var stats := _client.build_my_stats(
		{"best_score": 4210.0, "rank": 1.0},
		{
			"matches": [
				_match(100, true, 4210, 3, 4),
				_match(300, false, 900, 1, 2),
				_match(200, true, 1200, 2, 0),
			],
			"totals": {
				"matches": 70.0, "wins": 30.0, "kills": 99.0, "bumps": 120.0,
			},
		},
	)
	assert_eq(stats.best_score, 4210)
	assert_eq(stats.rank, 1)
	assert_eq(
		[stats.matches, stats.wins, stats.kills, stats.bumps],
		[70, 30, 99, 120],
	)
	assert_eq(stats.recent_matches, [
		{"is_winner": false, "score": 900, "kills": 1, "bumps": 2},
		{"is_winner": true, "score": 1200, "kills": 2, "bumps": 0},
		{"is_winner": true, "score": 4210, "kills": 3, "bumps": 4},
	], "newest first")


func test_my_stats_total_the_listed_matches_without_totals() -> void:
	# A runtime older than the totals field.
	var stats := _client.build_my_stats(
		{"rating": 1500.0, "matches": 0.0},
		{"matches": [
			_match(1, true, 10, 2, 3),
			_match(2, false, 5, 1, 1),
			"junk",
		]},
	)
	assert_eq(stats.best_score, -1)
	assert_eq(stats.rank, 0)
	assert_eq(
		[stats.matches, stats.wins, stats.kills, stats.bumps],
		[2, 1, 3, 4],
	)


func test_my_stats_list_the_newest_matches_only() -> void:
	var matches: Array = []
	for index in range(BackendApiClient.MY_STATS_RECENT_MATCHES + 5):
		matches.append(_match(index, index % 2 == 0, index, 0, 0))
	var stats := _client.build_my_stats({}, {"matches": matches})
	var recent: Array = stats.recent_matches
	assert_eq(recent.size(), BackendApiClient.MY_STATS_RECENT_MATCHES)
	var newest: int = matches.size() - 1
	assert_eq(recent[0].score, newest, "the newest match comes first")


func test_my_stats_ignore_a_malformed_reply() -> void:
	var stats := _client.build_my_stats(null, "nope")
	assert_eq(stats, {
		"best_score": -1,
		"rank": 0,
		"recent_matches": [],
		"matches": 0,
		"wins": 0,
		"kills": 0,
		"bumps": 0,
	})


## A get_match_history entry, as the runtime sends it.
func _match(
	ended_at: int,
	is_winner: bool,
	score: int,
	kills: int,
	bumps: int,
) -> Dictionary:
	return {
		"match_id": "req-%d" % ended_at,
		"ended_at": float(ended_at),
		"is_winner": is_winner,
		"score": float(score),
		"kills": float(kills),
		"bumps": float(bumps),
	}
