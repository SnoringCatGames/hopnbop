class_name NetworkConditionSimulatorPanel
extends PanelContainer
## Debug UI panel for controlling network condition simulation at runtime.
##
## Provides sliders for latency, jitter, packet loss, frame delay, and
## bandwidth throttling, plus preset buttons for common scenarios. Only
## active in debug builds; disables itself on servers.


func _ready() -> void:
	if Netcode.is_server:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	_connect_controls()
	_sync_ui_from_settings()


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_stats_label()


# --- Control wiring ---


func _connect_controls() -> void:
	%EnabledCheck.toggled.connect(_on_enabled_toggled)

	%LatencySlider.value_changed.connect(_on_latency_changed)
	%JitterSlider.value_changed.connect(_on_jitter_changed)
	%PacketLossSlider.value_changed.connect(_on_packet_loss_changed)
	%FrameDelaySlider.value_changed.connect(_on_frame_delay_changed)
	%BandwidthSlider.value_changed.connect(_on_bandwidth_changed)

	%SpikeIntervalSlider.value_changed.connect(
		_on_spike_interval_changed
	)
	%SpikeDurationSlider.value_changed.connect(
		_on_spike_duration_changed
	)
	%SpikeLatencySlider.value_changed.connect(
		_on_spike_latency_changed
	)

	%PresetNone.pressed.connect(
		_on_preset.bind(NetworkConditionSimulator.Preset.NONE)
	)
	%PresetGood.pressed.connect(
		_on_preset.bind(NetworkConditionSimulator.Preset.GOOD)
	)
	%PresetBadWifi.pressed.connect(
		_on_preset.bind(NetworkConditionSimulator.Preset.BAD_WIFI)
	)
	%Preset3G.pressed.connect(
		_on_preset.bind(NetworkConditionSimulator.Preset.MOBILE_3G)
	)
	%PresetChaos.pressed.connect(
		_on_preset.bind(NetworkConditionSimulator.Preset.CHAOS)
	)


# --- Callbacks ---


func _on_enabled_toggled(pressed: bool) -> void:
	Netcode.settings.network_sim_enabled = pressed
	_update_enabled_label()


func _on_latency_changed(value: float) -> void:
	Netcode.settings.network_sim_latency_ms = int(value)
	%LatencyValue.text = "%d ms" % int(value)


func _on_jitter_changed(value: float) -> void:
	Netcode.settings.network_sim_jitter_ms = int(value)
	%JitterValue.text = "%d ms" % int(value)


func _on_packet_loss_changed(value: float) -> void:
	Netcode.settings.network_sim_packet_loss_pct = value
	%PacketLossValue.text = "%.1f%%" % value


func _on_frame_delay_changed(value: float) -> void:
	Netcode.settings.network_sim_frame_delay_ms = int(value)
	%FrameDelayValue.text = "%d ms" % int(value)


func _on_bandwidth_changed(value: float) -> void:
	Netcode.settings.network_sim_bandwidth_limit = int(value)
	if int(value) == 0:
		%BandwidthValue.text = "Off"
	else:
		%BandwidthValue.text = "%d/sec" % int(value)


func _on_spike_interval_changed(value: float) -> void:
	Netcode.settings.network_sim_spike_interval_sec = value
	if value == 0.0:
		%SpikeIntervalValue.text = "Off"
	else:
		%SpikeIntervalValue.text = "%.1fs" % value


func _on_spike_duration_changed(value: float) -> void:
	Netcode.settings.network_sim_spike_duration_ms = int(value)
	%SpikeDurationValue.text = "%d ms" % int(value)


func _on_spike_latency_changed(value: float) -> void:
	Netcode.settings.network_sim_spike_latency_ms = int(value)
	%SpikeLatencyValue.text = "%d ms" % int(value)


func _on_preset(preset: NetworkConditionSimulator.Preset) -> void:
	if Netcode.condition_simulator == null:
		return
	Netcode.condition_simulator.apply_preset(preset)
	_sync_ui_from_settings()


# --- Sync UI from settings ---


func _sync_ui_from_settings() -> void:
	var s := Netcode.settings
	if s == null:
		return

	%EnabledCheck.button_pressed = s.network_sim_enabled
	_update_enabled_label()

	%LatencySlider.value = s.network_sim_latency_ms
	%LatencyValue.text = "%d ms" % s.network_sim_latency_ms

	%JitterSlider.value = s.network_sim_jitter_ms
	%JitterValue.text = "%d ms" % s.network_sim_jitter_ms

	%PacketLossSlider.value = s.network_sim_packet_loss_pct
	%PacketLossValue.text = "%.1f%%" % s.network_sim_packet_loss_pct

	%FrameDelaySlider.value = s.network_sim_frame_delay_ms
	%FrameDelayValue.text = "%d ms" % s.network_sim_frame_delay_ms

	%BandwidthSlider.value = s.network_sim_bandwidth_limit
	if s.network_sim_bandwidth_limit == 0:
		%BandwidthValue.text = "Off"
	else:
		%BandwidthValue.text = "%d/sec" % s.network_sim_bandwidth_limit

	%SpikeIntervalSlider.value = s.network_sim_spike_interval_sec
	if s.network_sim_spike_interval_sec == 0.0:
		%SpikeIntervalValue.text = "Off"
	else:
		%SpikeIntervalValue.text = (
			"%.1fs" % s.network_sim_spike_interval_sec
		)

	%SpikeDurationSlider.value = s.network_sim_spike_duration_ms
	%SpikeDurationValue.text = (
		"%d ms" % s.network_sim_spike_duration_ms
	)

	%SpikeLatencySlider.value = s.network_sim_spike_latency_ms
	%SpikeLatencyValue.text = (
		"%d ms" % s.network_sim_spike_latency_ms
	)


func _update_enabled_label() -> void:
	var on: bool = Netcode.settings.network_sim_enabled
	%EnabledCheck.text = "Enabled" if on else "Disabled"


func _update_stats_label() -> void:
	var sim := Netcode.condition_simulator
	if sim == null:
		%StatsLabel.text = "Simulator not available"
		return

	if not sim.is_enabled:
		%StatsLabel.text = "Simulation disabled"
		return

	%StatsLabel.text = (
		"Queued:%d  Delivered:%d  Dropped:%d  Pending:%d"
		% [
			sim.stats_queued,
			sim.stats_delivered,
			sim.stats_dropped,
			sim.stats_pending,
		]
	)
