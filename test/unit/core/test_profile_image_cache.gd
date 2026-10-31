extends GutTest
## H60 (PI-1): the avatar cache fetched any URL on any host,
## with no size limit or timeout. Only allowlisted provider
## CDN hosts over https are queued now, and the pooled
## requests carry both limits. The H37 probe asserted the old
## behavior; these tests assert the fixed one.


func test_http_and_unknown_hosts_are_never_queued() -> void:
	# Outside the tree there are no download slots, so an
	# accepted URL stays queued where the test can see it.
	var cache := ProfileImageCache.new()
	cache.request_image(2, "http://tracker.invalid/pixel.png")
	cache.request_image(
		3, "https://tracker.invalid/pixel.png")
	assert_eq(
		cache._queue.size(), 0, "no off-list URL is queued")
	cache.free()


func test_reused_id_with_a_new_url_evicts_the_old_image() -> void:
	# H61 (PI-2): player ids are per-server and reused by the
	# next match, so an id-keyed hit must not survive a URL
	# change, or the new player wears the old one's avatar.
	var cache := ProfileImageCache.new()
	var url_a := "https://lh3.googleusercontent.com/a/first.png"
	var url_b := "https://lh3.googleusercontent.com/a/second.png"
	cache.request_image(2, url_a)
	# Pretend the first download landed.
	cache._textures[2] = Texture2D.new()
	cache._queue.clear()

	cache.request_image(2, url_b)

	assert_null(
		cache.get_texture(2),
		"the old player's image is evicted on a URL change",
	)
	assert_eq(
		cache._queue, [[2, url_b]],
		"the new URL is queued in its place",
	)
	cache.free()


func test_allowlisted_https_is_queued() -> void:
	var cache := ProfileImageCache.new()
	cache.request_image(
		2, "https://lh3.googleusercontent.com/a/avatar.png")
	assert_eq(cache._queue.size(), 1, "provider CDN is queued")
	cache.free()


func test_pool_requests_carry_size_and_time_limits() -> void:
	var cache := ProfileImageCache.new()
	add_child_autofree(cache)
	assert_eq(cache._request_pool.size(), 3, "three slots")
	for request in cache._request_pool:
		assert_eq(
			request.body_size_limit,
			ProfileImageCache._AVATAR_MAX_BYTES,
			"size cap set")
		assert_eq(
			request.timeout,
			ProfileImageCache._AVATAR_TIMEOUT_SEC,
			"timeout set")
		assert_eq(
			request.max_redirects, 0,
			"redirects are not followed (H113)")


func test_allowed_url_shapes() -> void:
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://lh3.googleusercontent.com/a.png"))
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://scontent.fbcdn.net/a.png"))
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://scontent-lax3-1.xx.fbcdn.net/a.png"))
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://platform-lookaside.fbsbx.com/a.png"))
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://avatars.steamstatic.com/a.png"))
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://avatars.akamai.steamstatic.com/a.png"))
	assert_false(ProfileImageCache.is_allowed_avatar_url(
		"http://lh3.googleusercontent.com/a.png"))
	assert_false(ProfileImageCache.is_allowed_avatar_url(
		"https://googleusercontent.com.evil.invalid/a.png"))
	assert_false(ProfileImageCache.is_allowed_avatar_url(""))


func test_allowed_url_shapes_attacker_controlled() -> void:
	# Shapes where the string check and the engine's URL
	# handling disagree, and customer-run subdomains of
	# the provider parents (H113).
	var refused: Array[String] = [
		"https://127.0.0.1#.googleusercontent.com/a.png",
		"https://evil.invalid#.googleusercontent.com",
		"https://evil.invalid?x.googleusercontent.com/a.png",
		"https://user@lh3.googleusercontent.com/a.png",
		"https://lh3.googleusercontent.com:8443/a.png",
		"https://lh3%2egoogleusercontent.com/a.png",
		"https://lh3.googleusercontent.com\\a.png",
		"https://4.3.2.1.bc.googleusercontent.com/a.png",
		"https://storage.googleapis.com/a.png",
		"https://storage.googleusercontent.com/a.png",
		"https://lhx.googleusercontent.com/a.png",
		"https://lh-3.googleusercontent.com/a.png",
		"https://lh3.googleusercontent.com./a.png",
		"https://graph.facebook.com/a.png",
		"https://cdn.steamstatic.com/a.png",
		"https://avatars.fastly.steamstatic.com/a.png",
	]
	for url in refused:
		assert_false(
			ProfileImageCache.is_allowed_avatar_url(url),
			"refused: %s" % url)


func test_oversized_declared_dimensions_are_not_decoded(
) -> void:
	var cache := ProfileImageCache.new()
	var data := PackedByteArray()
	data.resize(33)
	# PNG signature and IHDR with 20000x20000 declared.
	var signature: Array[int] = [
		0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
	for i in 8:
		data[i] = signature[i]
	# "IHDR", then width and height big-endian.
	data[12] = 0x49
	data[13] = 0x48
	data[14] = 0x44
	data[15] = 0x52
	data[18] = 0x4E
	data[19] = 0x20
	data[22] = 0x4E
	data[23] = 0x20
	assert_eq(
		cache._load_image_from_buffer(Image.new(), data),
		ERR_INVALID_DATA,
		"a huge flat image is refused before decoding")
	# A small real PNG still decodes.
	var small := Image.create(
		2, 2, false, Image.FORMAT_RGBA8)
	var bytes := small.save_png_to_buffer()
	assert_eq(
		cache._load_image_from_buffer(Image.new(), bytes),
		OK, "a small PNG decodes")
	cache.free()
