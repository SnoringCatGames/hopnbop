extends GutTest
## H113: the game server relays the avatar URL a client
## declares to every other client in the match. Only
## provider CDN URLs are forwarded; anything else is
## dropped, so viewers never fetch from an unlisted host.


func test_hostile_declared_url_is_not_forwarded() -> void:
	var provider := EdgegapServerProvider.new()
	provider._store_profile_image_urls(
		[7], "https://logger.example.invalid/pixel.png")
	provider._store_profile_image_urls(
		[7], "https://127.0.0.1#.googleusercontent.com/x.png")
	provider._store_profile_image_urls(
		[7], "https://4.3.2.1.bc.googleusercontent.com/x.png")
	assert_false(
		provider.get_profile_image_url_map().has(7),
		"an unlisted declared URL is dropped")
	provider.free()


func test_provider_cdn_url_is_forwarded() -> void:
	var provider := EdgegapServerProvider.new()
	var url := "https://lh3.googleusercontent.com/a/avatar.png"
	provider._store_profile_image_urls([7], url)
	assert_eq(
		provider.get_profile_image_url_map().get(7), url,
		"a provider CDN URL is forwarded")
	provider.free()
