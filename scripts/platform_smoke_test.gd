extends SceneTree
## End-to-end smoke test against the live snoringcat-platform
## backend.
##
## Run from the repo root:
##   godot --headless --path . -s scripts/platform_smoke_test.gd
##
## NOTE: -s script mode bypasses the project's autoloads, so
## this test instantiates the platform classes directly instead
## of going through the Platform autoload. Once we have a
## proper Main scene that uses Platform.initialize(), the
## smoke test can switch to running through that flow.


const _API_URL := (
	"https://r20b7wqop6.execute-api.us-west-2.amazonaws.com/prod"
)
const _ApiClientScript := preload(
	"res://addons/snoringcat_platform_client/core/api_client.gd"
)


func _init() -> void:
	print("[smoke] Instantiating PlatformApiClient...")
	var api = _ApiClientScript.new()
	api.base_url = _API_URL
	# Add to the SceneTree so its inner HTTPRequest enters the
	# tree and can issue requests.
	root.add_child(api)

	api.response_received.connect(_on_response)
	api.request_failed.connect(_on_failed)
	print("[smoke] GET %s/v1/version" % _API_URL)
	api.do_get("/v1/version")


func _on_response(
	ok: bool,
	status_code: int,
	body: Dictionary,
	path: String,
) -> void:
	print(
		"[smoke] response: ok=%s status=%d path=%s body=%s"
		% [str(ok), status_code, path, str(body)])
	if ok:
		print("[smoke] PASS")
		quit(0)
	else:
		print("[smoke] FAIL: non-2xx status")
		quit(1)


func _on_failed(error: String, path: String) -> void:
	print(
		"[smoke] FAIL: transport error %s on %s"
		% [error, path])
	quit(2)
