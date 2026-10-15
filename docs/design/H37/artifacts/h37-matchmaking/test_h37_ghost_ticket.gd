extends GutTest
## H37 probe (h37-matchmaking, F4 D): a Cancel that lands while
## PlatformMatchmakingClient.start_matchmaking is suspended in
## add_matchmaker_async leaves a live ticket behind. The socket is a
## fake: nothing connects, nothing binds a port.


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
			p_query : String = "*",
			p_min_count : int = 2,
			p_max_count : int = 8,
			p_string_props : Dictionary = {},
			p_numeric_props : Dictionary = {},
			p_count_multiple : int = 0,
	) -> NakamaRTAPI.MatchmakerTicket:
		add_calls += 1
		await release
		var t := NakamaRTAPI.MatchmakerTicket.new()
		t.ticket = "probe-ticket"
		return t

	func remove_matchmaker_async(p_ticket : String) -> NakamaAsyncResult:
		remove_calls += 1
		return NakamaAsyncResult.new()

	func rpc_async(p_func_id : String, p_payload = null) -> NakamaAPI.ApiRpc:
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


# Control: Cancel after the ticket exists withdraws it.
func test_cancel_after_ticket_withdraws_it() -> void:
	var client := _make_client()
	client.start_matchmaking("*", 2, 4, {}, {})
	client.fake.release.emit()
	await wait_process_frames(2)
	assert_true(client.is_searching(), "control: searching once queued")
	client.cancel_matchmaking()
	assert_false(client.is_searching())
	assert_eq(client.fake.remove_calls, 1, "control: ticket withdrawn")
	assert_eq(client.fake.rpc_calls.size(), 1, "control: cancel RPC sent")


# Probe: Cancel inside the add_matchmaker_async await.
func test_cancel_during_start_leaves_live_ticket() -> void:
	var client := _make_client()
	client.start_matchmaking("*", 2, 4, {}, {})
	assert_eq(client.fake.add_calls, 1, "suspended in add_matchmaker_async")
	assert_false(client.is_searching(), "window: not yet searching")
	client.cancel_matchmaking()
	client.fake.release.emit()
	await wait_process_frames(2)
	assert_true(client.is_searching(), "ghost: searching after Cancel")
	assert_eq(client._ticket, "probe-ticket", "ghost: ticket kept")
	assert_eq(client.fake.remove_calls, 0, "ghost: ticket never withdrawn")
	assert_eq(client.fake.rpc_calls.size(), 0, "ghost: no cancel RPC")
	assert_false(client._elapsed_timer.is_stopped(), "ghost: timer runs")
	client.start_matchmaking("*", 2, 4, {}, {})
	assert_eq(client.fake.add_calls, 1, "next Play files no new ticket")


# Probe (F3): the 120 s timer runs from ticket creation and nothing stops it
# while the runtime allocates (the client hears nothing until the hook
# returns). Its expiry sends the shared-allocation cancel RPC.
func test_timeout_sends_allocation_cancel() -> void:
	var client := _make_client()
	watch_signals(client)
	client.start_matchmaking("*", 2, 4, {}, {})
	client.fake.release.emit()
	await wait_process_frames(2)
	for i in 121:
		client._on_elapsed_tick()
	assert_false(client.is_searching(), "timed out")
	assert_eq(client.fake.remove_calls, 1, "ticket removal sent")
	assert_true(
		client.fake.rpc_calls.has("cancel_matchmaking_allocation"),
		"timeout sends the shared-allocation cancel RPC",
	)
	assert_signal_emitted(client, "matchmaking_failed")


# Probe (F4 G): a clean socket close while searching only prints.
func test_socket_close_while_searching_keeps_searching() -> void:
	var client := _make_client()
	watch_signals(client)
	client.start_matchmaking("*", 2, 4, {}, {})
	client.fake.release.emit()
	await wait_process_frames(2)
	client._on_socket_closed()
	assert_true(client.is_searching(), "still searching on a closed socket")
	assert_false(client._elapsed_timer.is_stopped(), "timer still runs")
	assert_signal_not_emitted(client, "matchmaking_failed")
