# class_name G
extends Node
## Add global state here for easy access.


# Note: This is shown at the top to assist with local debugging.
var preview_instance_label := ""

var args: Dictionary

var time := ScaffolderTime.new()
@warning_ignore("shadowed_global_identifier")
var log := ScaffolderLog.new()
var utils := Utils.new()
var geometry := Geometry.new()
var network := NetworkingMain.new()

var main: Main
var settings: Settings
var audio: AudioMain
var hud: Hud
var screens: ScreensMain

var main_menu_screen: MainMenuScreen
var loading_screen: LoadingScreen
var game_over_screen: GameOverScreen
var win_screen: WinScreen
var pause_screen: PauseScreen

var game_panel: GamePanel
var match_state: MatchState
var local_session: LocalSession
var level: Level


func _enter_tree() -> void:
    args = Utils.parse_command_line_args()

    time.name = "Time"
    add_child(time)

    log.name = "Log"
    add_child(log)

    utils.name = "Utils"
    add_child(utils)

    geometry.name = "Geometry"
    add_child(geometry)

    network.name = "Network"
    add_child(network)


func _ready() -> void:
    G.log.log_system_ready("Global")

    if G.network.is_preview:
        if G.network.is_client:
            preview_instance_label = "Client %s" % G.network.preview_client_number
        else:
            preview_instance_label = "Server"
    else:
        preview_instance_label = ""


func get_player_match_state(multiplayer_id: int) -> PlayerMatchState:
    if not match_state.players_by_id.has(multiplayer_id):
        return null
    return match_state.players_by_id[multiplayer_id]


func get_player(multiplayer_id: int) -> Player:
    if (not is_instance_valid(level) or
            not level.players_by_id.has(multiplayer_id)):
        return null
    return level.players_by_id[multiplayer_id]


# --- Include some convenient access to logging/error utilities ---------------

func print(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
    log.print(message, category)


func warning(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
    log.warning(message, category)


func error(message = "", category := ScaffolderLog.CATEGORY_DEFAULT) -> void:
    log.error(message, category)


func ensure(condition: bool, message = "") -> bool:
    return log.ensure(condition, message)


func check(condition: bool, message = "") -> bool:
    return log.check(condition, message)


func check_is_server(method_name: String) -> bool:
    return log.check(G.network.is_server, "%s: is_client" % method_name)


func check_is_client(method_name: String) -> bool:
    return log.check(G.network.is_client, "%s: is_server" % method_name)

# -----------------------------------------------------------------------------
