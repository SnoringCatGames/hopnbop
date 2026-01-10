# class_name G
extends Node
## Add global state here for easy access.


var time := ScaffolderTime.new()
@warning_ignore("shadowed_global_identifier")
var log := ScaffolderLog.new()
var utils := Utils.new()
var geometry := Geometry.new()
var server_time_tracker := ServerTimeTracker.new()

var main: Main
var settings: Settings
var audio: AudioMain
var hud: Hud
var screens: ScreensMain

var main_menu_screen: MainMenuScreen
var game_over_screen: GameOverScreen
var win_screen: WinScreen
var pause_screen: PauseScreen

var game_panel: GamePanel
var session: Session
var level: Level


func _enter_tree() -> void:
    time.name = "Time"
    add_child(time)
    
    log.name = "Log"
    add_child(log)
    
    utils.name = "Utils"
    add_child(utils)
    
    geometry.name = "Geometry"
    add_child(geometry)
    
    server_time_tracker.name = "ServerTimeTracker"
    add_child(server_time_tracker)
