extends GutTest
## SP28: a Cancel landing while start_matchmaking is suspended
## in add_matchmaker_async used to leave a live ghost ticket.
## The search generation counter withdraws it. Flipped from
## the H37 probe (h37-matchmaking F4), plus the socket-close
## case (F4 G).


class FakeSocket extends NakamaSocket:
	signal release
	var add_calls := 0
	var remove_calls := 0
	var rpc_calls: Array = []

	func _init(adapter: NakamaSocketAdapter) -> void:
		super(adapter, "127.0.0.1", 7350, "ws")

	func is_connected_to_host():
		return true

	func add_matchmaker_async(
			p_query: String = "*",
			p_min_count: int = 2,
			p_max_count: int = 8,
			p_string_props: Dictionary = {},
			p_numeric_props: Dictionary = {},
			p_count_multiple: int = 0,
	) -> NakamaRTAPI.MatchmakerTicket:
		add_calls += 1
		await release
		var t := NakamaRTAPI.MatchmakerTicket.new()
		t.ticket = "probe-ticket"
		return t

	func remove_matchmaker_async(
		p_ticket: String,
	) -> NakamaAsyncResult:
		remove_calls += 1
		return NakamaAsyncResult.new()

	func rpc_async(p_func_id: String, p_payload = null) -> NakamaAPI.ApiRpc:
		rpc_calls.append(p_func_id)
		return null


class ProbeClient extends PlatformMatchmakingClient:
	var fake: FakeSocket

	func ensure_socket() -> bool:
		_socket = fake
		return true

	func _record_client_ip() -> void:
		pass


func _make_client() -> ProbeClient:
	var adapter := NakamaSocketAdapter.new()
	add_child_autofree(adapter)
	var client := ProbeClient.new()
	client.fake = FakeSocket.new(adapter)
	add_child_autofree(client)
	return client


func test_cancel_after_ticket_withdraws_it() -> void:
	var client := _make_client()
	client.start_matchmaking("*", 2, 4, {}, {})
	client.fake.release.emit()
	await wait_process_frames(2)
	assert_true(client.is_searching(), "searching once queued")
	client.cancel_matchmaking()
	assert_false(client.is_searching())
	assert_eq(client.fake.remove_calls, 1, "ticket withdrawn")
	assert_eq(client.fake.rpc_calls.size(), 1, "cancel RPC sent")


func test_cancel_during_start_withdraws_the_ticket() -> void:
	var client := _make_client()
	client.start_matchmaking("*", 2, 4, {}, {})
	assert_eq(client.fake.add_calls, 1, "suspended in the add")
	assert_false(client.is_searching(), "not yet searching")
	client.cancel_matchmaking()
	client.fake.release.emit()
	await wait_process_frames(2)
	assert_false(client.is_searching(), "no ghost search")
	assert_eq(client._ticket, "", "no ticket kept")
	assert_eq(
		client.fake.remove_calls, 1, "ghost ticket withdrawn")
	assert_true(
		client._elapsed_timer.is_stopped(), "timer never ran")
	client.start_matchmaking("*", 2, 4, {}, {})
	assert_eq(client.fake.add_calls, 2, "next Play files anew")
	client.fake.release.emit()
	await wait_process_frames(2)
	assert_true(client.is_searching(), "searching again")


func test_socket_close_ends_the_search() -> void:
	var client := _make_client()
	watch_signals(client)
	client.start_matchmaking("*", 2, 4, {}, {})
	client.fake.release.emit()
	await wait_process_frames(2)
	client._on_socket_closed()
	assert_false(client.is_searching(), "search ended")
	assert_true(
		client._elapsed_timer.is_stopped(), "timer stopped")
	assert_signal_emitted(client, "matchmaking_failed")
