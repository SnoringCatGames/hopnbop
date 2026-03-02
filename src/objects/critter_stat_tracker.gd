class_name CritterStatTracker
extends Node
## Client-side tracker that accumulates critter
## disturbance counts and fly proximity time for
## local players.


## Per-player recording cooldown for fish and
## butterfly disturbances (seconds).
const RECORD_COOLDOWN_SEC := 2.0

## Radius for counting nearby flies (matches
## FlySwarm.PLAYER_INTERACTION_RADIUS).
const _FLY_PROXIMITY_RADIUS := 40.0

# Accumulated counts per player_id. Public so
# ClientStatReporter can read them for deltas.
var cricket_counts := {}
var fish_counts := {}
var butterfly_counts := {}
var fly_proximity_times := {}

# Per-player recording cooldowns for
# rate-limited critter types. Maps
# player_id -> { "fish": float,
#   "butterfly": float }.
var _cooldowns := {}

# References set by the level after spawning.
var _fly_swarms: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _physics_process(delta: float) -> void:
	_update_fly_proximity(delta)
	_tick_cooldowns(delta)


## Connects disturbance signals from a cricket.
func register_cricket(cricket: Cricket) -> void:
	cricket.disturbed.connect(
		_on_cricket_disturbed)


## Connects disturbance signals from a fish.
func register_fish(fish: Fish) -> void:
	fish.disturbed.connect(
		_on_fish_disturbed)


## Connects disturbance signals from a butterfly.
func register_butterfly(
	butterfly: Butterfly,
) -> void:
	butterfly.disturbed.connect(
		_on_butterfly_disturbed)


## Registers a fly swarm for proximity tracking.
func register_fly_swarm(
	swarm: FlySwarm,
) -> void:
	_fly_swarms.append(swarm)


# --- Signal handlers ---


func _on_cricket_disturbed(
	player_id: int,
) -> void:
	# No recording cooldown for crickets.
	cricket_counts[player_id] = (
		cricket_counts.get(player_id, 0) + 1)


func _on_fish_disturbed(
	player_id: int,
) -> void:
	var cd: Dictionary = _cooldowns.get(
		player_id, {})
	if cd.get("fish", 0.0) > 0.0:
		return
	fish_counts[player_id] = (
		fish_counts.get(player_id, 0) + 1)
	cd["fish"] = RECORD_COOLDOWN_SEC
	_cooldowns[player_id] = cd


func _on_butterfly_disturbed(
	player_id: int,
) -> void:
	var cd: Dictionary = _cooldowns.get(
		player_id, {})
	if cd.get("butterfly", 0.0) > 0.0:
		return
	butterfly_counts[player_id] = (
		butterfly_counts.get(player_id, 0) + 1)
	cd["butterfly"] = RECORD_COOLDOWN_SEC
	_cooldowns[player_id] = cd


# --- Per-frame updates ---


func _tick_cooldowns(delta: float) -> void:
	for player_id in _cooldowns:
		var cd: Dictionary = _cooldowns[player_id]
		for key in cd:
			cd[key] = maxf(
				cd[key] - delta, 0.0)


func _update_fly_proximity(
	delta: float,
) -> void:
	var level: Level = G.level
	if not is_instance_valid(level):
		return

	for player_id in \
			G.client_session.local_player_ids:
		var player: Player = \
			level.players_by_id.get(player_id)
		if not is_instance_valid(player):
			continue
		var player_pos := \
			player.global_position

		var nearby_count := 0
		for swarm in _fly_swarms:
			if not is_instance_valid(swarm):
				continue
			for fly in swarm._flies:
				if not is_instance_valid(fly):
					continue
				var dist: float = (
					fly.global_position
						.distance_to(
							player_pos))
				if dist < _FLY_PROXIMITY_RADIUS:
					nearby_count += 1

		if nearby_count > 0:
			fly_proximity_times[player_id] = (
				fly_proximity_times
					.get(player_id, 0.0)
				+ delta * nearby_count)
