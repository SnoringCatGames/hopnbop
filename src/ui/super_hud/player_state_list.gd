class_name PlayerStateList
extends PanelContainer

@export var player_state_panel_scene: PackedScene


func _enter_tree() -> void:
    if G.network.is_server:
        visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
        return


func _ready() -> void:
    if G.network.is_server:
        return

    visibility_changed.connect(_on_visibility_changed)

    if visible:
        _initialize()


func _on_visibility_changed() -> void:
    if visible and %States.get_child_count() == 0:
        _initialize()


func _initialize() -> void:
    _on_players_updated()
    if not G.game_panel.match_state_synchronizer.players_updated.is_connected(_on_players_updated):
        G.game_panel.match_state_synchronizer.players_updated.connect(_on_players_updated)


func _on_players_updated() -> void:
    for child in %States.get_children():
        child.queue_free()

    if G.match_state.players.is_empty():
        # No player state to show.
        return

    if not G.ensure(
        G.match_state.players.has(G.network.local_id),
        "No match_state for the local player",
    ):
        return

    # Add the local player state first.
    _add_player_state(G.network.local_id)

    for multiplayer_id in G.match_state.players:
        if multiplayer_id == G.network.local_id:
            # We already added the local player state.
            continue
        _add_player_state(multiplayer_id)


func _add_player_state(multiplayer_id: int) -> void:
    var player_state_panel: PlayerStatePanel = player_state_panel_scene.instantiate()
    player_state_panel.multiplayer_id = multiplayer_id
    %States.add_child(player_state_panel)
