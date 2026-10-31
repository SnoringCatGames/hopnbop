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

## A small body can still declare huge dimensions; anything
## over this is not decoded at all.
const _AVATAR_MAX_DIMENSION := 1024

## Only provider CDN hosts are fetched (H60). Any other URL
## would leak the viewer's IP to whoever set it and is never
## queued. Hosts match exactly (H113): a suffix match would
## also admit customer-run subdomains of the same parents.
## Mirrors the runtime's list (SP88 keeps the two in step).

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
		# Provider avatar URLs are direct; a redirect would
		# send the viewer to an unlisted host (H113).
		request.max_redirects = 0
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
## WebP. Declared dimensions over the cap are refused
## before decoding (H113): a small flat PNG can declare
## tens of thousands of pixels per side.
func _load_image_from_buffer(
	image: Image, data: PackedByteArray,
) -> Error:
	var dimensions := _declared_dimensions(data)
	if (dimensions.x > _AVATAR_MAX_DIMENSION
			or dimensions.y > _AVATAR_MAX_DIMENSION):
		return ERR_INVALID_DATA
	var error := image.load_png_from_buffer(data)
	if error == OK:
		return OK
	error = image.load_jpg_from_buffer(data)
	if error == OK:
		return OK
	error = image.load_webp_from_buffer(data)
	return error

## Whether an avatar URL may be fetched: https on an
## exact provider CDN host, parsed strictly (H113).
## Anything the fetch would read differently than this
## check ? a fragment, a query or userinfo in the
## authority, a port, an encoded host ? is refused.
static func is_allowed_avatar_url(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	if url.contains("#") or url.contains("\\"):
		return false
	var rest := url.trim_prefix("https://")
	var slash := rest.find("/")
	var authority := (
		rest if slash == -1 else rest.left(slash))
	if authority.is_empty():
		return false
	for bad_char in ["@", "?", "%", ":", " ", "\t"]:
		if authority.contains(bad_char):
			return false
	return _is_allowed_avatar_host(authority.to_lower())


## The provider hosts avatar URLs are fetched from:
## Google's `lh<n>` image servers, Facebook's lookaside
## and `scontent` CDNs, Steam's avatar CDNs. Nothing
## else under those parents is fetched (H113).
static func _is_allowed_avatar_host(host: String) -> bool:
	if (host == "platform-lookaside.fbsbx.com"
			or host == "avatars.steamstatic.com"
			or host == "avatars.akamai.steamstatic.com"):
		return true
	if host.ends_with(".googleusercontent.com"):
		var label := host.trim_suffix(
			".googleusercontent.com")
		if not label.begins_with("lh"):
			return false
		var digits := label.substr(2)
		if digits.is_empty():
			return false
		return digits.lstrip("0123456789").is_empty()
	if host.ends_with(".fbcdn.net"):
		var head := host.trim_suffix(".fbcdn.net")
		return (head == "scontent"
			or head.begins_with("scontent.")
			or head.begins_with("scontent-"))
	return false


## Width and height an encoded image declares, or
## (-1, -1) when the header is not PNG, JPEG or WebP.
static func _declared_dimensions(
	data: PackedByteArray,
) -> Vector2i:
	if (data.size() >= 24
			and data[0] == 0x89 and data[1] == 0x50
			and data[2] == 0x4E and data[3] == 0x47):
		return Vector2i(
			_read_be32(data, 16), _read_be32(data, 20))
	if (data.size() >= 4
			and data[0] == 0xFF and data[1] == 0xD8):
		return _jpeg_dimensions(data)
	if (data.size() >= 30
			and data.slice(0, 4).get_string_from_ascii() == "RIFF"
			and data.slice(8, 4).get_string_from_ascii() == "WEBP"):
		return _webp_dimensions(data)
	return Vector2i(-1, -1)


static func _jpeg_dimensions(
	data: PackedByteArray,
) -> Vector2i:
	var pos := 2
	while pos + 9 < data.size():
		if data[pos] != 0xFF:
			break
		var marker := data[pos + 1]
		if (marker >= 0xC0 and marker <= 0xCF
				and marker != 0xC4 and marker != 0xC8
				and marker != 0xCC):
			return Vector2i(
				_read_be16(data, pos + 7),
				_read_be16(data, pos + 5))
		if (marker == 0xD8 or marker == 0xD9
				or marker == 0x01
				or (marker >= 0xD0 and marker <= 0xD7)):
			pos += 2
		else:
			pos += 2 + _read_be16(data, pos + 2)
	return Vector2i(-1, -1)


static func _webp_dimensions(
	data: PackedByteArray,
) -> Vector2i:
	var chunk := data.slice(12, 4).get_string_from_ascii()
	if chunk == "VP8X" and data.size() >= 30:
		return Vector2i(
			_read_le24(data, 24) + 1,
			_read_le24(data, 27) + 1)
	if chunk == "VP8L" and data.size() >= 25:
		var b1 := data[22]
		var b2 := data[23]
		var b3 := data[24]
		return Vector2i(
			1 + (((b1 & 0x3F) << 8) | data[21]),
			1 + (((b3 & 0x0F) << 10) | (b2 << 2)
				| ((b1 & 0xC0) >> 6)))
	if chunk == "VP8 " and data.size() >= 30:
		return Vector2i(
			_read_le16(data, 26) & 0x3FFF,
			_read_le16(data, 28) & 0x3FFF)
	return Vector2i(-1, -1)


static func _read_be32(
	data: PackedByteArray, offset: int,
) -> int:
	return ((data[offset] << 24) | (data[offset + 1] << 16)
		| (data[offset + 2] << 8) | data[offset + 3])


static func _read_be16(
	data: PackedByteArray, offset: int,
) -> int:
	return (data[offset] << 8) | data[offset + 1]


static func _read_le16(
	data: PackedByteArray, offset: int,
) -> int:
	return data[offset] | (data[offset + 1] << 8)


static func _read_le24(
	data: PackedByteArray, offset: int,
) -> int:
	return (data[offset] | (data[offset + 1] << 8)
		| (data[offset + 2] << 16))

