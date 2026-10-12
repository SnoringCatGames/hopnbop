extends GutTest
## Unit tests for PreviewSessionProvider's stand-in session ids.
##
## NetworkConnector reuses a player_id whenever a declared session_id
## was seen before in the match, so the ids preview clients send must
## never collide across clients. Two clients that both sent
## DEBUG_SESSION_0 shared player_id 1, and the second client got no
## bunny.


func test_ids_differ_between_preview_clients() -> void:
	var client_1_ids := PreviewSessionProvider.make_debug_session_ids(1, 1)
	var client_2_ids := PreviewSessionProvider.make_debug_session_ids(2, 1)
	assert_ne(client_1_ids[0], client_2_ids[0])


func test_ids_are_unique_within_one_client() -> void:
	var ids := PreviewSessionProvider.make_debug_session_ids(1, 4)
	assert_eq(ids.size(), 4)
	var unique := {}
	for session_id in ids:
		unique[session_id] = true
	assert_eq(unique.size(), 4)


func test_ids_are_unique_across_clients_with_local_players() -> void:
	var unique := {}
	for instance_number in [1, 2]:
		for session_id in PreviewSessionProvider.make_debug_session_ids(
			instance_number,
			2,
		):
			unique[session_id] = true
	assert_eq(unique.size(), 4)


func test_ids_are_stable_for_the_same_client() -> void:
	# A reconnecting client must send the same ids so the server
	# hands back its old player_id.
	assert_eq(
		PreviewSessionProvider.make_debug_session_ids(2, 2),
		PreviewSessionProvider.make_debug_session_ids(2, 2),
	)


func test_zero_players_yields_no_ids() -> void:
	assert_eq(PreviewSessionProvider.make_debug_session_ids(1, 0).size(), 0)
