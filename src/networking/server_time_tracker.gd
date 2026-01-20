class_name ServerTimeTracker
extends Node
## Tracks and estimates current server time using NTP-like clock synchronization.
##
## ServerTimeTracker provides clients with an accurate estimate of the server's
## current time (Time.get_ticks_usec()) by calculating and maintaining a clock
## offset that accounts for network latency.
##
## **NTP algorithm (Network Time Protocol):**
## Reference: https://en.wikipedia.org/wiki/Network_Time_Protocol
##
## The synchronization process uses four timestamps:
## - T1: Client sends request (client local time)
## - T2: Server receives request (server time)
## - T3: Server sends response (server time)
## - T4: Client receives response (client local time)
##
## From these, we calculate:
## - Round-trip time (RTT): (T4 - T1) - (T3 - T2)
## - Clock offset: ((T2 - T1) + (T3 - T4)) / 2
##
## The offset tells us how much to add to local time to estimate server time:
##   estimated_server_time = local_time + clock_offset
##
## **Smoothing and stability:**
## - Maintains a sliding window of recent samples (default 5)
## - Uses average offset across samples for stability
## - Initial burst mode: syncs every 0.2s until enough samples collected
## - Normal mode: syncs every 5.0s to handle clock drift
##
## **Key methods:**
## - get_server_time_usec(): Returns estimated server time in microseconds
## - client_request_time_sync(): Manually trigger a sync request
## - force_clock_offset(delta): Adjust offset when authoritative state indicates
##   drift
##
## **Automatic synchronization:**
## - Starts automatically when client connects to server
## - Runs continuously in _process() if auto_sync_interval > 0
## - Emits sync_completed signal after each successful sync
##
## **Server behavior:**
## - On server, get_server_time_usec() simply returns local time (no offset
##   needed)
## - Server responds to client sync requests via RPC
##
## Accessed via G.network.time singleton.
##
## This accurate time estimate is critical for frame-based networking, allowing
## clients to correctly map network timestamps to local frame indices for
## rollback reconciliation.

## Emitted when a time sync completes successfully.
signal sync_completed(offset_usec: int, rtt_usec: int)

## How often to automatically sync time (in seconds). Set to 0 to disable
## auto-sync.
@export var auto_sync_interval: float = 5.0

## How often to sync during initial burst (in seconds) until we have
## sample_count samples.
@export var initial_sync_interval: float = 0.2

## Number of sync samples to average for a more stable offset estimate.
@export var sample_count: int = 5

## Whether this instance is running on the server.
var is_server: bool:
    get:
        return (
            multiplayer.is_server() if is_instance_valid(multiplayer) and
            multiplayer.has_multiplayer_peer() else true
        )

## The estimated clock offset from local time to server time (in microseconds).
## server_time ≈ local_time + clock_offset_usec
var clock_offset_usec: int = 0

## The most recent measured round-trip time (in microseconds).
var rtt_usec: int = 0

## Whether we have completed at least one successful sync.
var is_synced: bool = false

var _time_since_last_sync: float = 0.0
var _client_pending_sync_t1: int = 0
var _client_offset_samples: Array[int] = []
var _client_rtt_samples: Array[int] = []


func _ready() -> void:
    G.log.log_system_ready("ServerTimeTracker")

    # Connect to multiplayer signals to know when we're connected.
    if G.network.is_client:
        multiplayer.connected_to_server.connect(_client_on_connected_to_server)
    if G.network.is_server:
        multiplayer.peer_connected.connect(_server_on_peer_connected)


func _process(delta: float) -> void:
    if auto_sync_interval <= 0.0:
        return
    if is_server:
        return
    if not multiplayer.has_multiplayer_peer():
        return

    _time_since_last_sync += delta

    # Use faster sync interval until we have enough samples for a stable
    # estimate.
    var current_interval := (
        initial_sync_interval
        if _client_offset_samples.size() < sample_count
        else auto_sync_interval
    )
    if _time_since_last_sync >= current_interval:
        _time_since_last_sync = 0.0
        client_request_time_sync()


## Returns the estimated server time in microseconds.
##
## This is an estimate of what `Time.get_ticks_usec()` would currently return on
## the remote server machine.
func get_server_time_usec() -> int:
    if is_server:
        # We ARE the server, just return local time.
        return Time.get_ticks_usec()

    # Return local time adjusted by the calculated offset.
    return Time.get_ticks_usec() + clock_offset_usec


## Manually request a time synchronization with the server.
##
## On the server, this does nothing.
func client_request_time_sync() -> void:
    if is_server:
        return
    if not multiplayer.has_multiplayer_peer():
        return

    # T1: Client sends request with its local timestamp.
    _client_pending_sync_t1 = Time.get_ticks_usec()
    _server_rpc_request_time.rpc_id(1, _client_pending_sync_t1)


## Manually adjusts the clock offset by the given delta.
##
## This is useful when authoritative network state indicates that our time
## estimate has drifted. The adjustment is applied to all existing samples
## to prevent the NTP averaging from reverting the correction.
func force_clock_offset(delta_usec: int) -> void:
    if is_server:
        return

    clock_offset_usec += delta_usec

    # Also adjust all samples so the running average doesn't fight this
    # correction.
    for i in range(_client_offset_samples.size()):
        _client_offset_samples[i] += delta_usec

    G.log.log(
        "Manually adjusted clock offset by %d usec (new offset: %d usec)"
        % [delta_usec, clock_offset_usec],
        ScaffolderLog.CATEGORY_NETWORK_SYNC,
    )


## Clears all sync data and resets to unsynced state.
func clear() -> void:
    clock_offset_usec = 0
    rtt_usec = 0
    is_synced = false
    _time_since_last_sync = 0.0
    _client_pending_sync_t1 = 0
    _client_offset_samples.clear()
    _client_rtt_samples.clear()


func _client_on_connected_to_server() -> void:
    # When we connect to a server, immediately request time sync.
    clear()
    client_request_time_sync()


func _server_on_peer_connected(_peer_id: int) -> void:
    # Server doesn't need to do anything special when peers connect.
    pass


## RPC called by client to request time from server.
##
## t1_usec: The client's local time when the request was sent.
@rpc("any_peer", "call_remote", "unreliable")
func _server_rpc_request_time(t1_usec: int) -> void:
    if not is_server:
        return

    # T2: Server receives the request.
    var t2_usec := Time.get_ticks_usec()

    # T3: Server sends response (we send T2 and T3 together; T3 is "now").
    var t3_usec := Time.get_ticks_usec()

    var sender_id := multiplayer.get_remote_sender_id()
    _client_rpc_respond_time.rpc_id(sender_id, t1_usec, t2_usec, t3_usec)


## RPC called by server to respond with time information.
##
## t1_usec: Original client send time (echoed back).
## t2_usec: Server receive time.
## t3_usec: Server send time.
@rpc("authority", "call_remote", "unreliable")
func _client_rpc_respond_time(t1_usec: int, t2_usec: int, t3_usec: int) -> void:
    if is_server:
        return

    # T4: Client receives the response.
    var t4_usec := Time.get_ticks_usec()

    # Verify this response matches our pending request.
    if t1_usec != _client_pending_sync_t1:
        # Stale response, ignore.
        return

    # Calculate round-trip time: RTT = (T4 - T1) - (T3 - T2).
    # This is the total network delay (excluding server processing time).
    var rtt := (t4_usec - t1_usec) - (t3_usec - t2_usec)

    # Calculate clock offset using NTP formula:
    # offset = ((T2 - T1) + (T3 - T4)) / 2
    # This gives us how much to add to local time to get server time.
    @warning_ignore("integer_division")
    var offset := ((t2_usec - t1_usec) + (t3_usec - t4_usec)) / 2

    # Add to samples.
    _client_offset_samples.append(offset)
    _client_rtt_samples.append(rtt)

    # Keep only the most recent samples.
    while _client_offset_samples.size() > sample_count:
        _client_offset_samples.pop_front()
    while _client_rtt_samples.size() > sample_count:
        _client_rtt_samples.pop_front()

    # Calculate average offset (could also use median for more robustness).
    var total_offset: int = 0
    for sample in _client_offset_samples:
        total_offset += sample
    @warning_ignore("integer_division")
    clock_offset_usec = total_offset / _client_offset_samples.size()

    # Store the latest RTT.
    rtt_usec = rtt

    is_synced = true
    sync_completed.emit(clock_offset_usec, rtt_usec)
