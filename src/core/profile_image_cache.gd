class_name ProfileImageCache
extends Node
## Async profile image downloader and texture cache.
##
## Downloads profile images from provider CDN URLs
## and caches them as ImageTexture resources. Uses a
## pool of HTTPRequest nodes to limit concurrent
## downloads. Falls back to a tinted anonymous icon
## when download fails.


signal image_loaded(player_id: int)


const _MAX_CONCURRENT_DOWNLOADS := 3

## Anonymous fallback icon loaded once on ready.
var _anonymous_texture: Texture2D

## Cached textures by player_id.
## Dictionary<int, ImageTexture>
var _textures: Dictionary = {}

## Set of player_ids currently downloading.
## Dictionary<int, bool>
var _downloading: Dictionary = {}

## Queued downloads waiting for a free slot.
## Array of [player_id, url].
var _queue: Array = []

## Pool of reusable HTTPRequest nodes.
var _request_pool: Array[HTTPRequest] = []


func _ready() -> void:
	_anonymous_texture = G.settings.anonymous_texture
	for i in range(_MAX_CONCURRENT_DOWNLOADS):
		var request := HTTPRequest.new()
		request.name = (
			"ImageRequest%d" % i)
		request.use_threads = true
		add_child(request)
		_request_pool.append(request)


## Request an image download for a player. If already
## cached or downloading, this is a no-op.
func request_image(
	player_id: int, url: String,
) -> void:
	if _textures.has(player_id):
		return
	if _downloading.has(player_id):
		return
	if url.is_empty():
		return
	_queue.append([player_id, url])
	_process_queue()


## Returns the cached texture for a player, or null
## if not yet downloaded.
func get_texture(player_id: int) -> ImageTexture:
	return _textures.get(player_id)


## Returns the anonymous fallback texture.
func get_anonymous_texture() -> Texture2D:
	return _anonymous_texture


## Clear all cached textures and pending downloads.
func clear() -> void:
	_textures.clear()
	_downloading.clear()
	_queue.clear()


func _process_queue() -> void:
	while not _queue.is_empty():
		# Find a free HTTPRequest node.
		var request := _get_free_request()
		if request == null:
			return
		var entry: Array = _queue.pop_front()
		var player_id: int = entry[0]
		var url: String = entry[1]
		_start_download(
			request, player_id, url)


func _get_free_request() -> HTTPRequest:
	for request in _request_pool:
		if (not request.request_completed
				.is_connected(
					_on_request_completed)):
			return request
	return null


func _start_download(
	request: HTTPRequest,
	player_id: int,
	url: String,
) -> void:
	_downloading[player_id] = true
	request.request_completed.connect(
		_on_request_completed.bind(
			request, player_id),
		CONNECT_ONE_SHOT,
	)
	var error := request.request(url)
	if error != OK:
		_downloading.erase(player_id)
		request.request_completed.disconnect(
			_on_request_completed)
		_process_queue()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	request: HTTPRequest,
	player_id: int,
) -> void:
	_downloading.erase(player_id)

	if (result != HTTPRequest.RESULT_SUCCESS
			or response_code != 200
			or body.is_empty()):
		_process_queue()
		return

	var image := Image.new()
	var error := _load_image_from_buffer(
		image, body)
	if error != OK:
		_process_queue()
		return

	var texture := ImageTexture.create_from_image(
		image)
	_textures[player_id] = texture
	image_loaded.emit(player_id)
	_process_queue()


## Try loading image data as PNG, then JPEG, then
## WebP.
func _load_image_from_buffer(
	image: Image, data: PackedByteArray,
) -> Error:
	var error := image.load_png_from_buffer(data)
	if error == OK:
		return OK
	error = image.load_jpg_from_buffer(data)
	if error == OK:
		return OK
	error = image.load_webp_from_buffer(data)
	return error
