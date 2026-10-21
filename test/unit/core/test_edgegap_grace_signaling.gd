extends GutTest
## H48: the 10s connection grace restarts when a peer's
## signaling completes, so WebRTC setup time is not consumed
## by the window that waits for late validations. The probe
## provider counts grace (re)starts instead of running timers.


class ProbeProvider extends EdgegapServerProvider:
	var grace_starts := 0

	func _start_grace_timer() -> void:
		_grace_active = true
		grace_starts += 1

	func _stop_grace_timer() -> void:
		_grace_active = false


var _provider: ProbeProvider


func before_each() -> void:
	ArrayPool.clear_all_pools()
	_provider = ProbeProvider.new()


func after_each() -> void:
	_provider.free()
	ArrayPool.clear_all_pools()


func test_signaling_before_validation_does_not_start_grace() -> void:
	_provider._on_peer_connected(7)
	assert_eq(_provider.grace_starts, 0, "no grace before anyone validates")
	assert_true(
		_provider._peer_signaling_msec.has(7),
		"signaling completion is stamped for the run log",
	)


func test_signaling_after_first_validation_restarts_grace() -> void:
	_provider._validated_player_count = 1
	_provider._start_grace_timer()
	assert_eq(_provider.grace_starts, 1, "grace running from first validation")
	_provider._on_peer_connected(8)
	assert_eq(
		_provider.grace_starts, 2,
		"grace restarts after the late peer's signaling",
	)
	_provider._on_peer_connected(9)
	assert_eq(_provider.grace_starts, 3, "each late signaling restarts it")


func test_no_restart_once_grace_stopped() -> void:
	_provider._validated_player_count = 1
	_provider._start_grace_timer()
	_provider._stop_grace_timer()
	_provider._on_peer_connected(8)
	assert_eq(_provider.grace_starts, 1, "stopped grace stays stopped")
