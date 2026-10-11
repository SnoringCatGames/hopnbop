extends GutHookScript
## GUT post-run hook that fails the run if this test process sent
## any HTTP request through the Nakama SDK.
##
## CI passes it with -gpost_run_script. Every GUT process boots the
## game's autoloads, and G points Platform at production Nakama
## (nakama.snoringcat.games). No test here should reach a Nakama
## server. The platform's RPC paths are covered by the
## snoringcat-platform compliance suite, which runs against its own
## ephemeral stack (compliance-matrix.yml). So any request from a
## GUT run means a test, or the boot path, is talking to production.
##
## The count is NakamaHTTPAdapter.get_last_token(), the request id
## that every send_async increments before it awaits. The SDK's
## realtime socket is not counted, but it cannot connect without a
## session from an HTTP auth call first. Raw HTTPRequest calls that
## bypass the SDK (version_check, profile images) are not counted.


func run() -> void:
	var request_count: int = Nakama.get_client_adapter().get_last_token()
	if request_count == 0:
		return
	gut.logger.error(
		(
			"NAKAMA TRAFFIC: this test process sent %d HTTP request(s)"
			+ " through the Nakama SDK. Tests must not talk to a"
			+ " Nakama server; Platform points at production."
		)
		% request_count
	)
	set_exit_code(1)
