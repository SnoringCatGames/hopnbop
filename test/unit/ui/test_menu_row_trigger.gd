extends GutTest
## MenuRow.trigger() is the shared activation dispatch (H95):
## one activation fires `triggered` and the subclass's
## on_trigger() exactly once each, so the click sound hooked
## into trigger() covers keyboard, gamepad, and mouse alike.


class ProbeRow:
	extends MenuRow
	var trigger_calls := 0

	func on_trigger() -> void:
		trigger_calls += 1


func test_trigger_dispatches_signal_and_action_once() -> void:
	var row := ProbeRow.new()
	add_child_autofree(row)
	watch_signals(row)

	row.trigger()

	assert_signal_emitted(row, "triggered")
	assert_eq(row.trigger_calls, 1)


func test_trigger_is_the_only_dispatch_the_panel_needs() -> void:
	var row := ProbeRow.new()
	add_child_autofree(row)

	row.trigger()
	row.trigger()

	assert_eq(row.trigger_calls, 2, "every activation lands")
