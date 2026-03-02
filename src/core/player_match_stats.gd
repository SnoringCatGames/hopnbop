class_name PlayerMatchStats
extends RefCounted
## Server-side per-player stat accumulator for dynamic
## adjective assignment. Tracks gameplay metrics during
## a match and provides serialization for RPC delivery.


var crown_time_sec := 0.0
var regicide_count := 0
var bump_count := 0
var kill_count := 0
var death_count := 0
var jump_count := 0
var water_time_sec := 0.0
var water_jump_count := 0
var ice_time_sec := 0.0
var spring_launch_count := 0
var direction_change_count := 0
var snail_crush_count := 0
var cricket_disturb_count := 0
var fish_disturb_count := 0
var butterfly_disturb_count := 0
var fly_proximity_time_sec := 0.0
var poop_count := 0

var _height_accumulator := 0.0
var _height_frame_count := 0
var _previous_facing_sign := 0


var average_height: float:
	get:
		if _height_frame_count == 0:
			return 0.0
		return (
			_height_accumulator
			/ _height_frame_count
		)


## Accumulates per-frame stats from the character's
## current state. Called once per server forward-sim
## frame (not during resimulation or death).
func accumulate_frame(
	character: Character,
	delta_sec: float,
	has_crown: bool,
) -> void:
	# Height tracking (negate Y so higher altitude
	# = higher value).
	_height_accumulator += -character.global_position.y
	_height_frame_count += 1

	# Crown time.
	if has_crown:
		crown_time_sec += delta_sec

	# Water time.
	if character.surfaces.is_in_water:
		water_time_sec += delta_sec

	# Ice time (on floor with ice friction).
	if (
		character.surfaces.is_attaching_to_floor
		and character.surfaces.surface_properties
			.friction_multiplier < 1.0
	):
		ice_time_sec += delta_sec

	# Direction changes.
	var facing := (
		character.surfaces.horizontal_facing_sign
	)
	if (
		_previous_facing_sign != 0
		and facing != 0
		and facing != _previous_facing_sign
	):
		direction_change_count += 1
	if facing != 0:
		_previous_facing_sign = facing


func record_jump(is_in_water: bool) -> void:
	jump_count += 1
	if is_in_water:
		water_jump_count += 1


func record_spring_launch() -> void:
	spring_launch_count += 1


func record_kill() -> void:
	kill_count += 1


func record_death() -> void:
	death_count += 1


func record_bump() -> void:
	bump_count += 1


func record_regicide() -> void:
	regicide_count += 1


func record_snail_crush() -> void:
	snail_crush_count += 1


func record_cricket_disturb() -> void:
	cricket_disturb_count += 1


func record_fish_disturb() -> void:
	fish_disturb_count += 1


func record_butterfly_disturb() -> void:
	butterfly_disturb_count += 1


func accumulate_fly_proximity(
	delta_weighted: float,
) -> void:
	fly_proximity_time_sec += delta_weighted


func record_poop() -> void:
	poop_count += 1


## Packs stats into an Array for RPC transmission.
func to_packed_array() -> Array:
	return [
		crown_time_sec,
		regicide_count,
		bump_count,
		kill_count,
		death_count,
		jump_count,
		water_time_sec,
		water_jump_count,
		ice_time_sec,
		spring_launch_count,
		direction_change_count,
		average_height,
		snail_crush_count,
		cricket_disturb_count,
		fish_disturb_count,
		butterfly_disturb_count,
		fly_proximity_time_sec,
		poop_count,
	]


## Populates this instance from a packed array
## (inverse of to_packed_array).
func populate_from_packed_array(
	data: Array,
) -> void:
	crown_time_sec = data[0]
	regicide_count = int(data[1])
	bump_count = int(data[2])
	kill_count = int(data[3])
	death_count = int(data[4])
	jump_count = int(data[5])
	water_time_sec = data[6]
	water_jump_count = int(data[7])
	ice_time_sec = data[8]
	spring_launch_count = int(data[9])
	direction_change_count = int(data[10])
	# average_height is computed from backing fields.
	# Set accumulator to the value with frame_count=1
	# so the getter returns the correct value.
	_height_accumulator = data[11]
	_height_frame_count = 1
	snail_crush_count = int(data[12])
	cricket_disturb_count = int(data[13])
	fish_disturb_count = int(data[14])
	butterfly_disturb_count = int(data[15])
	fly_proximity_time_sec = data[16]
	poop_count = int(data[17])
