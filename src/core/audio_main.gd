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
	"kill" = %KillStreamPlayer,
	"hole" = %HoleStreamPlayer,
	"crown_cadence" = %CrownCadenceStreamPlayer,
}


func _enter_tree() -> void:
	G.audio = self


func _ready() -> void:
	G.log.log_system_ready("AudioMain")

	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	if not Netcode.is_primary_client:
		return

	# Apply persisted audio settings.
	apply_music_mute()
	apply_sfx_mute()


func play_sound(sound_name: StringName) -> void:
	if not Netcode.is_primary_client:
		return

	if not Netcode.ensure(STREAM_PLAYERS_BY_NAME.has(sound_name)):
		return

	var stream_player: AudioStreamPlayer = STREAM_PLAYERS_BY_NAME[sound_name]
	if not stream_player.playing:
		stream_player.play()


func fade_to_menu_theme() -> void:
	if not Netcode.is_primary_client:
		return

	fade_out(%MainThemeStreamPlayer)
	fade_in(%MenuThemeStreamPlayer, menu_theme_volume)


func fade_to_main_theme() -> void:
	if not Netcode.is_primary_client:
		return

	fade_out(%MenuThemeStreamPlayer)
	fade_in(%MainThemeStreamPlayer, main_theme_volume)


func fade_out_menu_theme() -> void:
	if not Netcode.is_primary_client:
		return

	fade_out(%MenuThemeStreamPlayer)


func fade_in_main_theme() -> void:
	if not Netcode.is_primary_client:
		return

	fade_in(%MainThemeStreamPlayer, main_theme_volume)


func fade_out_main_theme() -> void:
	if not Netcode.is_primary_client:
		return

	fade_out(%MainThemeStreamPlayer)


func fade_in(stream_player: AudioStreamPlayer, volume: float) -> void:
	if not Netcode.is_primary_client:
		return

	if G.settings.mute_music:
		volume = mute_volume

	if not stream_player.playing:
		stream_player.volume_db = mute_volume
		stream_player.play.call()

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
	if not Netcode.is_primary_client:
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


func apply_music_mute() -> void:
	if not Netcode.is_primary_client:
		return

	# Apply mute setting to currently playing music streams.
	var menu_player := %MenuThemeStreamPlayer
	var main_player := %MainThemeStreamPlayer

	if menu_player.playing and not menu_player.stream_paused:
		menu_player.volume_db = mute_volume if (
			G.settings.mute_music
		) else menu_theme_volume

	if main_player.playing and not main_player.stream_paused:
		main_player.volume_db = mute_volume if (
			G.settings.mute_music
		) else main_theme_volume


func apply_sfx_mute() -> void:
	if not Netcode.is_primary_client:
		return

	# Bus index 2 is "SFX" per
	# default_bus_layout.tres.
	AudioServer.set_bus_mute(
		2, G.settings.mute_sfx)
