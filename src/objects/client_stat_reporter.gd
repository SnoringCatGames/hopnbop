class_name ClientStatReporter
extends Node
## Periodically sends client-authoritative stats
## (critter disturbances, fly proximity, poop) to
## the server via RPC. Reads critter counts from a
## CritterStatTracker and tracks poop locally.


## How often to send accumulated stats to the
## server (physics frames). 120 = ~2 sec at
## 60 FPS.
const _SEND_INTERVAL_FRAMES := 120

## Reference to the critter tracker whose counts
## we read for delta computation.
var critter_tracker: CritterStatTracker

# Accumulated poop counts per player_id.
var _poop_counts := {}

var _send_counter := 0

# Tracks the last cumulative values sent to the
# server so we can send only deltas.
var _last_sent_cricket := {}
var _last_sent_fish := {}
var _last_sent_butterfly := {}
var _last_sent_fly_time := {}
var _last_sent_poop := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(_delta: float) -> void:
	_send_counter += 1
	if _send_counter >= _SEND_INTERVAL_FRAMES:
		_send_counter = 0
		_send_stats_to_server()


## Records a poop event for the given player.
func record_poop(player_id: int) -> void:
	_poop_counts[player_id] = (
		_poop_counts.get(player_id, 0) + 1)


# --- RPC sending ---


func _send_stats_to_server() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not (multiplayer.multiplayer_peer
			.get_connection_status()
			== MultiplayerPeer
				.CONNECTION_CONNECTED):
		return
	if not is_instance_valid(critter_tracker):
		return

	var packed := []
	for player_id in (
			G.client_session.local_player_ids):
		var cricket_delta: int = (
			critter_tracker.cricket_counts
				.get(player_id, 0)
			- _last_sent_cricket
				.get(player_id, 0))
		var fish_delta: int = (
			critter_tracker.fish_counts
				.get(player_id, 0)
			- _last_sent_fish
				.get(player_id, 0))
		var butterfly_delta: int = (
			critter_tracker.butterfly_counts
				.get(player_id, 0)
			- _last_sent_butterfly
				.get(player_id, 0))
		var fly_time_delta: float = (
			critter_tracker.fly_proximity_times
				.get(player_id, 0.0)
			- _last_sent_fly_time
				.get(player_id, 0.0))
		var poop_delta: int = (
			_poop_counts.get(player_id, 0)
			- _last_sent_poop
				.get(player_id, 0))

		if (
			cricket_delta == 0
			and fish_delta == 0
			and butterfly_delta == 0
			and fly_time_delta == 0.0
			and poop_delta == 0
		):
			continue

		packed.append(player_id)
		packed.append(cricket_delta)
		packed.append(fish_delta)
		packed.append(butterfly_delta)
		packed.append(fly_time_delta)
		packed.append(poop_delta)

		# Update last-sent watermarks.
		_last_sent_cricket[player_id] = (
			critter_tracker.cricket_counts
				.get(player_id, 0))
		_last_sent_fish[player_id] = (
			critter_tracker.fish_counts
				.get(player_id, 0))
		_last_sent_butterfly[player_id] = (
			critter_tracker.butterfly_counts
				.get(player_id, 0))
		_last_sent_fly_time[player_id] = (
			critter_tracker.fly_proximity_times
				.get(player_id, 0.0))
		_last_sent_poop[player_id] = (
			_poop_counts
				.get(player_id, 0))

	if packed.is_empty():
		return

	var synchronizer: MatchStateSynchronizer = (
		G.game_panel.match_state_synchronizer)
	if is_instance_valid(synchronizer):
		(synchronizer
			._rpc_server_update_critter_stats
			.rpc_id(
				NetworkConnector.SERVER_ID,
				packed,
			))
