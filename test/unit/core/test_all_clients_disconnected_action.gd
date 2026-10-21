extends GutTest
## H45: all-clients-dropped server decision. An unfinished
## match is cancelled with the runtime and the server waits
## out the reconnect grace; the old flat 12s quit landed
## inside the 30s reconnect window and told the runtime
## nothing, leaking the deployment and its match rows.


func test_unfinished_match_cancels_and_waits_out_grace() -> void:
	var action := GameSessionManager.all_clients_disconnected_action(false)
	assert_true(bool(action["cancel"]), "unfinished match is cancelled")
	assert_almost_eq(
		float(action["wait_sec"]),
		MatchStateSynchronizer.RECONNECT_GRACE_SEC,
		0.01,
		"wait covers the reconnect grace, not the old 12s",
	)
	assert_gt(float(action["wait_sec"]), 12.0, "longer than the old quit delay")


func test_finished_match_only_flushes() -> void:
	var action := GameSessionManager.all_clients_disconnected_action(true)
	assert_false(bool(action["cancel"]), "match_end already reported; no cancel")
	assert_almost_eq(
		float(action["wait_sec"]), 12.0, 0.01,
		"finished match keeps the report flush wait",
	)
