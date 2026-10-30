extends GutTest
## SDK failure strings are English diagnostics; a toast shows the
## mapped translation, never the raw string (H18).


func test_not_authenticated_maps_to_the_sign_out_line() -> void:
	assert_eq(
		ToastOverlay.player_error_text("Not authenticated"),
		tr("TOAST.SIGNED_OUT"),
	)


func test_described_errors_map_to_the_generic_line() -> void:
	assert_eq(
		ToastOverlay.player_error_text(
			"Party join failed: group not found (status=3)"),
		tr("TOAST.OPERATION_FAILED"),
	)


func test_raw_text_never_passes_through() -> void:
	var raw := "rpc party_invite: context deadline exceeded"
	assert_ne(ToastOverlay.player_error_text(raw), raw)
