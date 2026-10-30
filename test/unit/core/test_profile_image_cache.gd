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


func test_allowed_url_shapes() -> void:
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://lh3.googleusercontent.com/a.png"))
	assert_true(ProfileImageCache.is_allowed_avatar_url(
		"https://scontent.fbcdn.net/a.png"))
	assert_false(ProfileImageCache.is_allowed_avatar_url(
		"http://lh3.googleusercontent.com/a.png"))
	assert_false(ProfileImageCache.is_allowed_avatar_url(
		"https://googleusercontent.com.evil.invalid/a.png"))
	assert_false(ProfileImageCache.is_allowed_avatar_url(""))
