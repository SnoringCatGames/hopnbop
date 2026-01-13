class_name LoadingScreen
extends Screen


func _enter_tree() -> void:
    super._enter_tree()
    G.loading_screen = self


func on_open() -> void:
    super.on_open()
    G.check(G.local_session.is_game_loading,
        "LoadingScreen.on_open: Game is not loading")
