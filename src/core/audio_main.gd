class_name AudioMain
extends Node2D


@export var theme_fade_duration_sec := 0.2

@export var mute_volume := -80.0

@export var main_theme_volume := 0.0
@export var menu_theme_volume := 0.0


func _enter_tree() -> void:
	G.audio = self


func play_click_sound() -> void:
	if not %ClickStreamPlayer.playing:
		%ClickStreamPlayer.play()


func fade_to_menu_theme() -> void:
	fade_out(%MainThemeStreamPlayer)
	fade_in(%MenuThemeStreamPlayer, menu_theme_volume)


func fade_to_main_theme() -> void:
	fade_out(%MenuThemeStreamPlayer)
	fade_in(%MainThemeStreamPlayer, main_theme_volume)


func fade_in(stream_player: AudioStreamPlayer, volume: float) -> void:
	if G.settings.mute_music:
		volume = mute_volume
	
	if not stream_player.playing:
		stream_player.volume_db = mute_volume
		# This is similar to calling play(), except play() resets playback position to zero.
		stream_player.stream_paused = false
	
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(stream_player, "volume_db", volume, theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with overlapping tweens
	# (the latest tween should end up winning).
	stream_player.stream_paused = false


func fade_out(stream_player: AudioStreamPlayer) -> void:
	if not stream_player.playing:
		return
	
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(stream_player, "volume_db", mute_volume, theme_fade_duration_sec)

	await tween.step_finished
	# Ensure the stream is still playing, just in case we somehow end up with overlapping tweens
	# (the latest tween should end up winning).
	stream_player.stream_paused = true
