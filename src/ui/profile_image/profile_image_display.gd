class_name ProfileImageDisplay
extends Control
## Circular profile image with colored border ring.
##
## Shows a player's profile image fetched from their
## OAuth provider, or a tinted anonymous icon as
## fallback. The image is clipped to a circle via
## shader. A colored ring border surrounds it.
## Uses _draw() for all rendering to avoid child
## node layout issues.


const _BORDER_WIDTH := 3


@export var image_size: int = 48

var _player_id: int = 0
var _fallback_color := Color.BLACK
var _is_image_set := false
var _current_texture: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(
		image_size, image_size)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = (
		G.settings.circle_mask_shader)
	material = shader_material
	_current_texture = (
		G.profile_image_cache
			.get_anonymous_texture())
	G.profile_image_cache.image_loaded.connect(
		_on_image_loaded)


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	# Border background (always black).
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color.BLACK)
	# Image inset by border width.
	if _current_texture != null:
		var inset := Vector2(
			_BORDER_WIDTH, _BORDER_WIDTH)
		# Tint anonymous icon with per-client
		# color. Real profile images are untinted.
		var tint := (
			Color.WHITE if _is_image_set
			else _fallback_color)
		draw_texture_rect(
			_current_texture,
			Rect2(inset, size - inset * 2),
			false,
			tint,
		)


## Set the player whose image to display.
func set_player(
	player_id: int,
	fallback_color: Color,
) -> void:
	_player_id = player_id
	_fallback_color = fallback_color
	_is_image_set = false
	_current_texture = (
		G.profile_image_cache
			.get_anonymous_texture())
	_try_load_cached()
	queue_redraw()


## Set from a URL directly (for leaderboard entries
## that are not in-match players).
func set_from_url(
	cache_key: int,
	url: String,
	fallback_color: Color,
) -> void:
	_player_id = cache_key
	_fallback_color = fallback_color
	_is_image_set = false
	_current_texture = (
		G.profile_image_cache
			.get_anonymous_texture())

	var cached := (
		G.profile_image_cache.get_texture(
			cache_key))
	if cached != null:
		_current_texture = cached
		_is_image_set = true
	elif not url.is_empty():
		G.profile_image_cache.request_image(
			cache_key, url)
	queue_redraw()


func _try_load_cached() -> void:
	if _player_id == 0:
		return

	var cached := (
		G.profile_image_cache.get_texture(
			_player_id))
	if cached != null:
		_current_texture = cached
		_is_image_set = true
		queue_redraw()
		return

	var url: String = (
		G.client_session.profile_image_urls
			.get(_player_id, ""))
	# Fall back to local auth store for local
	# players (e.g., in the lobby before server
	# distributes URLs). In the lobby all players
	# are local by definition.
	if (url.is_empty()
			and (G.is_lobby_active
				or _player_id in
					G.client_session
						.local_player_ids)
			and not Platform.token_store
				.profile_image_url.is_empty()):
		url = Platform.token_store.profile_image_url
	if not url.is_empty():
		G.profile_image_cache.request_image(
			_player_id, url)


func _on_image_loaded(player_id: int) -> void:
	if player_id != _player_id:
		return
	if _is_image_set:
		return
	var texture := (
		G.profile_image_cache.get_texture(
			player_id))
	if texture != null:
		_current_texture = texture
		_is_image_set = true
		queue_redraw()
