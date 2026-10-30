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

## Avatar downloads are capped and timed out (H60): one slow
## or endless response must not hold a download slot for good,
## and a huge body must not decode unbounded in memory.
const _AVATAR_MAX_BYTES := 2 * 1024 * 1024
const _AVATAR_TIMEOUT_SEC := 10.0

## Only provider CDN hosts are fetched (H60). Any other URL
## would leak the viewer's IP to whoever set it and is never
## queued. Suffixes match the host or any subdomain.
const _ALLOWED_AVATAR_HOST_SUFFIXES: Array[String] = [
	"googleusercontent.com",
	"fbcdn.net",
	"fbsbx.com",
	"steamstatic.com",
]

## Anonymous fallback icon loaded once on ready.
var _anonymous_texture: Texture2D

## Cached textures by player_id.
## Dictionary<int, ImageTexture>
var _textures: Dictionary = {}

## Set of player_ids currently downloading.
## Dictionary<int, bool>
var _downloading: Dictionary = {}

## URL each player_id's cache entry belongs to (H61).
## Dictionary<int, String>
var _requested_urls: Dictionary = {}

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
		request.body_size_limit = _AVATAR_MAX_BYTES
		request.timeout = _AVATAR_TIMEOUT_SEC
		add_child(request)
		_request_pool.append(request)


## Request an image download for a player. If already
## cached or downloading, this is a no-op.
func request_image(
	player_id: int, url: String,
) -> void:
	if url.is_empty():
		return
	if not is_allowed_avatar_url(url):
		return
	# Player ids are per-server and reused across matches
	# (H61): a cached image only counts for the URL it was
	# fetched from. A new URL for the same id evicts the old
	# binding instead of showing the previous player.
	if _requested_urls.get(player_id, "") == url:
		if (
			_textures.has(player_id)
			or _downloading.has(player_id)
		):
			return
		for entry in _queue:
			if entry[0] == player_id:
				return
	else:
		_requested_urls[player_id] = url
		_textures.erase(player_id)
		_queue = _queue.filter(
			func(entry: Array) -> bool:
				return entry[0] != player_id)
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
	_requested_urls.clear()
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
			request, player_id, url),
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
	url: String = "",
) -> void:
	_downloading.erase(player_id)

	# A newer URL for this id superseded this download
	# (H61); drop its result on the floor.
	if (
		not url.is_empty()
		and _requested_urls.get(player_id, "") != url
	):
		_process_queue()
		return

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

## Whether an avatar URL may be fetched: https on an
## allowlisted provider CDN host (or a subdomain of one).
static func is_allowed_avatar_url(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var rest := url.trim_prefix("https://")
	var host := rest.split("/")[0].split(":")[0].to_lower()
	if host.is_empty():
		return false
	for suffix in _ALLOWED_AVATAR_HOST_SUFFIXES:
		if host == suffix or host.ends_with("." + suffix):
			return true
	return false
