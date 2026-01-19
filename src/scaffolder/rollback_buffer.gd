class_name RollbackBuffer
extends CircularBuffer
## A circular buffer specialized for rollback networking.
##
## This buffer is pre-filled with default frame states and allows access to
## "virtual" previous frames that haven't been explicitly set yet, as long as
## they don't wrap around to overwrite actually-set frames.

## The default state used to fill new/unset frames.
var _default_frame_state: Array = []


func _init(p_capacity: int, p_current_frame_index: int, p_default_frame_state: Array) -> void:
    super._init(p_capacity)

    _default_frame_state = p_default_frame_state

    _reinitialize_data(p_default_frame_state, p_current_frame_index)


## Reinitialize the entire _data array with duplicates of fill_state,
## and set buffer indices to point to target_index + 1.
## Uses array pool to reduce allocations.
func _reinitialize_data(fill_state: Array, target_index: int) -> void:
    for i in range(_capacity):
        # Release old array and acquire new one from pool.
        if _data[i] is Array:
            ArrayPool.release(_data[i])

        var new_arr := ArrayPool.acquire(fill_state.size())
        for j in range(fill_state.size()):
            new_arr[j] = fill_state[j]
        _data[i] = new_arr

    _next_index = (target_index + 1) % _capacity
    _total_pushed = target_index + 1


## Override to allow access to previous frames that haven't been explicitly set,
## as long as they wouldn't wrap around to currently-set frames.
##
## This supports access to -1 and -2:
## - Index -1 is used for the "previous" (default) state for frame 0.
## - Index -2 is used in _pre_network_process when accessing frame N-2 as
##   "previous" state for frame N (where N=0, so N-2=-2).
func has_at(index: int) -> bool:
    if index >= _total_pushed:
        return false

    # Calculate the oldest theoretically accessible index.
    # This is limited by the buffer capacity.
    var oldest_accessible_index := maxi(-2, _total_pushed - _capacity)
    return index >= oldest_accessible_index


## Override to allow access to the same indices as has_at, including index -1.
func get_at(index: int) -> Variant:
    if not has_at(index):
        return null
    # Handle index -1 by wrapping to the end of the internal array.
    var internal_index := index % _capacity
    if internal_index < 0:
        internal_index += _capacity
    return _data[internal_index]


## Back-fill missing frames using the last recorded state.
func backfill_to_with_last_state(target_index: int) -> void:
    if get_latest_index() >= target_index:
        return

    var latest_state: Array = get_at(get_latest_index())

    # Use array pool for temporary fill_state to avoid allocation.
    var fill_state := ArrayPool.acquire(latest_state.size())
    for i in range(latest_state.size()):
        fill_state[i] = latest_state[i]

    # Backfilled state is not authoritative.
    fill_state[fill_state.size() - 1] = ReconcilableNetworkedState.FrameAuthority.PREDICTED

    # If the gap is larger than capacity, just reinitialize the entire array.
    if target_index - get_latest_index() > _capacity:
        _reinitialize_data(fill_state, target_index)
    else:
        _backfill_to(target_index, fill_state)

    # Return temporary array to pool.
    ArrayPool.release(fill_state)


## Back-fill any missing frames in the buffer up to (but not including)
## target_index.
func _backfill_to(target_index: int, fill_state: Variant) -> void:
    while get_latest_index() < target_index:
        var next_index := get_latest_index() + 1
        # No need to duplicate, set_at() will reuse existing array slots.
        set_at(next_index, fill_state)
