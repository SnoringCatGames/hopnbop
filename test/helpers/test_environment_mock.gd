@tool
class_name TestEnvironmentMock
extends RefCounted
## Helper class for mocking the game environment in tests.
##
## Provides utilities to mock G.level and other dependencies that tests
## need without modifying production code.


## Mock Level class that implements the minimal interface tests need.
class MockLevel extends Node:
    var players_by_id := {}


    func on_player_added(player: Node) -> void:
        if "multiplayer_id" in player and player.multiplayer_id > 0:
            players_by_id[player.multiplayer_id] = player


    func on_player_removed(player: Node) -> void:
        if "multiplayer_id" in player:
            players_by_id.erase(player.multiplayer_id)


## Set up mock level in G singleton.
static func setup_mock_level(parent_node: Node) -> MockLevel:
    var mock_level = MockLevel.new()
    mock_level.name = "MockLevel"
    parent_node.add_child(mock_level)
    G.level = mock_level
    return mock_level


## Initialize replication config for networked nodes.
static func init_replication_config(node: MultiplayerSynchronizer) -> void:
    if node.replication_config == null:
        node.replication_config = SceneReplicationConfig.new()


## Setup a player with minimal required dependencies.
static func setup_test_player(parent_node: Node) -> Player:
    var player = Player.new()
    player.name = "TestPlayer"

    # Initialize required Character exports.
    player.movement_settings = MovementSettings.new()
    player.collision_shape = CollisionShape2D.new()
    player.animator = CharacterAnimator.new()

    parent_node.add_child(player)
    return player


## Setup 3-node player configuration with all networked components.
static func setup_player_with_networking(
    parent_node: Node,
    player_name: String = "Player"
) -> Dictionary:
    var player = setup_test_player(parent_node)
    player.name = player_name

    var state_from_server = CharacterStateFromServer.new()
    state_from_server.name = "StateFromServer"
    state_from_server.root_path = NodePath(".")
    init_replication_config(state_from_server)
    state_from_server.character = player
    player.add_child(state_from_server)

    var input_from_client = PlayerInputFromClient.new()
    input_from_client.name = "InputFromClient"
    input_from_client.root_path = NodePath(".")
    init_replication_config(input_from_client)
    input_from_client.player = player
    player.add_child(input_from_client)

    var forwarded_input = ForwardedPlayerInputFromServer.new()
    forwarded_input.name = "ForwardedInput"
    forwarded_input.root_path = NodePath(".")
    init_replication_config(forwarded_input)
    forwarded_input.player = player
    player.add_child(forwarded_input)

    # Set exports.
    player.state_from_server = state_from_server
    player.input_from_client = input_from_client
    player.forwarded_input_from_server = forwarded_input

    return {
        "player": player,
        "state_from_server": state_from_server,
        "input_from_client": input_from_client,
        "forwarded_input": forwarded_input,
    }


## Cleanup mock level from G singleton.
static func cleanup_mock_level() -> void:
    G.level = null
