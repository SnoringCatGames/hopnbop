class_name CharacterActionState
extends RefCounted


const BIT_JUMP := 0
const BIT_UP := 1
const BIT_DOWN := 2
const BIT_LEFT := 3
const BIT_RIGHT := 4
const BIT_ATTACH := 5
const BIT_FACE_LEFT := 6
const BIT_FACE_RIGHT := 7

var bitmask: int = 0
var previous_bitmask: int = 0

var current_actions_bitmask: int:
    get: return bitmask
    set(value): bitmask = value

var pressed_jump: bool:
    set(value): _set_bit(BIT_JUMP, value)
    get: return _get_bit(bitmask, BIT_JUMP)
var just_pressed_jump: bool:
    get: return _get_bit(bitmask, BIT_JUMP) and not _get_bit(previous_bitmask, BIT_JUMP)
var just_released_jump: bool:
    get: return not _get_bit(bitmask, BIT_JUMP) and _get_bit(previous_bitmask, BIT_JUMP)

var pressed_up: bool:
    set(value): _set_bit(BIT_UP, value)
    get: return _get_bit(bitmask, BIT_UP)
var just_pressed_up: bool:
    get: return _get_bit(bitmask, BIT_UP) and not _get_bit(previous_bitmask, BIT_UP)
var just_released_up: bool:
    get: return not _get_bit(bitmask, BIT_UP) and _get_bit(previous_bitmask, BIT_UP)

var pressed_down: bool:
    set(value): _set_bit(BIT_DOWN, value)
    get: return _get_bit(bitmask, BIT_DOWN)
var just_pressed_down: bool:
    get: return _get_bit(bitmask, BIT_DOWN) and not _get_bit(previous_bitmask, BIT_DOWN)
var just_released_down: bool:
    get: return not _get_bit(bitmask, BIT_DOWN) and _get_bit(previous_bitmask, BIT_DOWN)

var pressed_left: bool:
    set(value): _set_bit(BIT_LEFT, value)
    get: return _get_bit(bitmask, BIT_LEFT)
var just_pressed_left: bool:
    get: return _get_bit(bitmask, BIT_LEFT) and not _get_bit(previous_bitmask, BIT_LEFT)
var just_released_left: bool:
    get: return not _get_bit(bitmask, BIT_LEFT) and _get_bit(previous_bitmask, BIT_LEFT)

var pressed_right: bool:
    set(value): _set_bit(BIT_RIGHT, value)
    get: return _get_bit(bitmask, BIT_RIGHT)
var just_pressed_right: bool:
    get: return _get_bit(bitmask, BIT_RIGHT) and not _get_bit(previous_bitmask, BIT_RIGHT)
var just_released_right: bool:
    get: return not _get_bit(bitmask, BIT_RIGHT) and _get_bit(previous_bitmask, BIT_RIGHT)

var pressed_attach: bool:
    set(value): _set_bit(BIT_ATTACH, value)
    get: return _get_bit(bitmask, BIT_ATTACH)
var just_pressed_attach: bool:
    get: return _get_bit(bitmask, BIT_ATTACH) and not _get_bit(previous_bitmask, BIT_ATTACH)
var just_released_attach: bool:
    get: return not _get_bit(bitmask, BIT_ATTACH) and _get_bit(previous_bitmask, BIT_ATTACH)

var pressed_face_left: bool:
    set(value): _set_bit(BIT_FACE_LEFT, value)
    get: return _get_bit(bitmask, BIT_FACE_LEFT)
var just_pressed_face_left: bool:
    get: return _get_bit(bitmask, BIT_FACE_LEFT) and not _get_bit(previous_bitmask, BIT_FACE_LEFT)
var just_released_face_left: bool:
    get: return not _get_bit(bitmask, BIT_FACE_LEFT) and _get_bit(previous_bitmask, BIT_FACE_LEFT)

var pressed_face_right: bool:
    set(value): _set_bit(BIT_FACE_RIGHT, value)
    get: return _get_bit(bitmask, BIT_FACE_RIGHT)
var just_pressed_face_right: bool:
    get: return _get_bit(bitmask, BIT_FACE_RIGHT) and not _get_bit(previous_bitmask, BIT_FACE_RIGHT)
var just_released_face_right: bool:
    get: return not _get_bit(bitmask, BIT_FACE_RIGHT) and _get_bit(previous_bitmask, BIT_FACE_RIGHT)


## Helper function to check if a bit is set in a bitmask.
static func _get_bit(mask: int, bit: int) -> bool:
    return (mask >> bit) & 1 == 1


## Helper function to set or clear a bit in the bitmask.
func _set_bit(bit: int, value: bool) -> void:
    if value:
        bitmask |= 1 << bit
    else:
        bitmask &= ~(1 << bit)


func clear() -> void:
    bitmask = 0
    previous_bitmask = 0


func copy(other: CharacterActionState) -> void:
    bitmask = other.bitmask
    previous_bitmask = other.previous_bitmask


func log_new_presses_and_releases(character) -> void:
    _log_new_press_or_release(
            character,
            "jump",
            just_pressed_jump,
            just_released_jump)
    _log_new_press_or_release(
            character,
            "up",
            just_pressed_up,
            just_released_up)
    _log_new_press_or_release(
            character,
            "down",
            just_pressed_down,
            just_released_down)
    _log_new_press_or_release(
            character,
            "left",
            just_pressed_left,
            just_released_left)
    _log_new_press_or_release(
            character,
            "right",
            just_pressed_right,
            just_released_right)
    _log_new_press_or_release(
            character,
            "attach",
            just_pressed_attach,
            just_released_attach)
    _log_new_press_or_release(
            character,
            "faceL",
            just_pressed_face_left,
            just_released_face_left)
    _log_new_press_or_release(
            character,
            "faceR",
            just_pressed_face_right,
            just_released_face_right)


func _log_new_press_or_release(
        character,
        action_name: String,
        just_pressed: bool,
        just_released: bool) -> void:
    var current_presses_strs := []
    if pressed_jump:
        current_presses_strs.push_back("J")
    if pressed_up:
        current_presses_strs.push_back("U")
    if pressed_down:
        current_presses_strs.push_back("D")
    if pressed_left:
        current_presses_strs.push_back("L")
    if pressed_right:
        current_presses_strs.push_back("R")
    if pressed_attach:
        current_presses_strs.push_back("G")
    if pressed_face_left:
        current_presses_strs.push_back("FL")
    if pressed_face_right:
        current_presses_strs.push_back("FR")
    var current_presses_str: String = Utils.join(current_presses_strs)

    var velocity_string: String = \
            "%17s" % Utils.get_vector_string(character.velocity, 1)

    var details := "v=%s; [%s]" % [
        velocity_string,
        current_presses_str,
    ]

    if just_pressed:
        G.print("START %5s: %s" % [action_name, details],
            ScaffolderLog.CATEGORY_PLAYER_MOVEMENT,
            ScaffolderLog.Verbosity.VERBOSE)
    if just_released:
        G.print("STOP  %5s: %s" % [action_name, details],
            ScaffolderLog.CATEGORY_PLAYER_MOVEMENT,
            ScaffolderLog.Verbosity.VERBOSE)


const _ACTION_FLAG_DEBUG_LABEL_PAIRS := [
    [BIT_JUMP, "J"],
    [BIT_UP, "U"],
    [BIT_DOWN, "D"],
    [BIT_LEFT, "L"],
    [BIT_RIGHT, "R"],
    [BIT_ATTACH, "G"],
]


static func get_debug_label_from_actions_bitmask(actions_bitmask: int) -> String:
    var action_strs := []
    for pair in _ACTION_FLAG_DEBUG_LABEL_PAIRS:
        var bit: int = pair[0]
        var text: String = pair[1]
        if actions_bitmask & (1 << bit):
            action_strs.push_back(text)
        else:
            action_strs.push_back("-")
    return Utils.join(action_strs)
