# class_name G
extends Node

# Add global state here for easy access.

var time := ScaffolderTime.new()
var utils := Utils.new()
var geometry := Geometry.new()

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

func _enter_tree() -> void:
    add_child(time)
    add_child(utils)
    add_child(geometry)
