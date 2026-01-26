class_name AudioMain
extends Node2D


@export var theme_fade_duration_sec := 0.2

@export var mute_volume := -80.0

@export var main_theme_volume := 0.0
@export var menu_theme_volume := 0.0

@onready var STREAM_PLAYERS_BY_NAME := {
	"menu_theme" = %MenuThemeStreamPlayer,
	"main_theme" = %MainThemeStreamPlayer,
	"click" = %ClickStreamPlayer,
	# TODO: Make a better sound.
	"godot_splash" = %ClickStreamPlayer,
	"scg_splash" = %SnoringCatStreamPlayer,
	"success" = %SuccessCadenceStreamPlayer,
	"failure" = %FailureCadenceStreamPlayer,
	"achievement" = %AchievementStreamPlayer,
}


func _enter_tree() -> void:
	G.audio = self

	if G.network.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return


func _ready() -> void:
	G.log.log_system_ready("AudioMain")

	if not G.network.is_primary_client:
		return


func play_sound(sound_name: StringName) -> void:
	if not G.network.is_primary_client:
		return

	if not G.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if not stream_player.playing:
		stream_player.play()


func fade_to_menu_theme() -> void:
	if not G.network.is_primary_client:
		return

	fade_out(%MainThemeStreamPlayer)
	fade_in(%MenuThemeStreamPlayer, menu_theme_volume)


func fade_to_main_theme() -> void:
	if not G.network.is_primary_client:
		return

	fade_out(%MenuThemeStreamPlayer)
	fade_in(%MainThemeStreamPlayer, main_theme_volume)


func fade_in(stream_player: AudioStreamPlayer, volume: float) -> void:
	if not G.network.is_primary_client:
		return

	if G.settings.mute_music:
		volume = mute_volume

	if not stream_player.playing:
		stream_player.volume_db = mute_volume
		# This is similar to calling play(), except play() resets playback
		# position to zero.
		stream_player.stream_paused = false

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		stream_player,
		"volume_db",
		volume,
		theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with
	# overlapping tweens (the latest tween should end up winning).
	stream_player.stream_paused = false


func fade_out(stream_player: AudioStreamPlayer) -> void:
	if not G.network.is_primary_client:
		return

	if not stream_player.playing:
		return

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		stream_player,
		"volume_db",
		mute_volume,
		theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with
	# overlapping tweens (the latest tween should end up winning).
	stream_player.stream_paused = true
