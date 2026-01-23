@tool
class_name TestEnvironmentMock
extends RefCounted
## Helper class for mocking the game environment in tests.
##
## Provides utilities to mock G.level and other dependencies that tests
## need without modifying production code.


## Mock Level class that implements the minimal interface tests need.
## Extends Level to satisfy G.level type constraint.
class MockLevel extends Level:
    # Override initialization to prevent full Level setup in tests
    func _enter_tree() -> void:
        # Skip Level's _enter_tree which requires G.game_panel
        pass

    func _ready() -> void:
        # Skip Level's _ready which requires player_spawner and G.settings
        pass

    func _exit_tree() -> void:
        # Skip Level's _exit_tree which requires G.game_panel
        pass

    # Override on_player_added to work in test context
    func on_player_added(player: Player) -> void:
        # Check if state_from_server is set up (it might not be during test
        # setup)
        if player.state_from_server == null:
            return
        if player.multiplayer_id > 0:
            players_by_id[player.multiplayer_id] = player

    # Override on_player_removed to work in test context
    func on_player_removed(player: Player) -> void:
        players_by_id.erase(player.multiplayer_id)


## Set up mock level in G singleton.
## Also initializes network time to allow rollback buffer setup.
static func setup_mock_level(parent_node: Node) -> MockLevel:
    var mock_level = MockLevel.new()
    mock_level.name = "MockLevel"
    parent_node.add_child(mock_level)
    G.level = mock_level

    # Initialize network time to allow rollback buffer setup.
    # This prevents "backfill_to_with_last_state on Nil" errors.
    if not G.network.time.is_time_initialized:
        # Set start time offset to initialize time synchronization
        G.network.time._start_time_offset_usec = 0

    return mock_level


## Initialize replication config for networked nodes.
static func init_replication_config(node: MultiplayerSynchronizer) -> void:
    if node.replication_config == null:
        node.replication_config = SceneReplicationConfig.new()


## Setup a player with minimal required dependencies (no networking nodes).
## For tests that need networking, use setup_player_with_networking() instead.
## Note: Does NOT add player to tree - caller must do that after adding
## networking nodes.
static func setup_test_player_minimal() -> Player:
    var player = Player.new()
    player.name = "TestPlayer"

    # Initialize required Character exports.
    player.movement_settings = MovementSettings.new()
    player.collision_shape = CollisionShape2D.new()

    # Initialize animator with required AnimatedSprite2D
    player.animator = CharacterAnimator.new()
    player.animator.animated_sprite = AnimatedSprite2D.new()
    player.animator.name = "Animator"
    player.add_child(player.animator)

    # Note: No networked nodes added here. Player._enter_tree() requires
    # state_from_server, so this function should only be used when the caller
    # will immediately add networking nodes before adding to tree.
    return player


## Setup a player with full 3-node configuration.
## Creates the player with all required networked nodes and adds to tree.
static func setup_test_player(parent_node: Node) -> Player:
    # Ensure network time is initialized BEFORE creating player nodes.
    if not G.network.time.is_time_initialized:
        G.network.time._start_time_offset_usec = 0

    # Also ensure frame tracking is initialized
    if not G.network.frame_driver._is_frame_tracking_initialized:
        G.network.frame_driver._initialize_frame_tracking()

    # Create the player but don't add to tree yet
    var player = Player.new()
    player.name = "TestPlayer"

    # Initialize required Character exports.
    player.movement_settings = MovementSettings.new()
    player.collision_shape = CollisionShape2D.new()

    # Initialize animator with required AnimatedSprite2D
    player.animator = CharacterAnimator.new()
    player.animator.animated_sprite = AnimatedSprite2D.new()
    player.animator.name = "Animator"
    player.add_child(player.animator)

    # Initialize all 3 networked nodes to satisfy 3-node validation.
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

    # Set exports on player
    player.state_from_server = state_from_server
    player.input_from_client = input_from_client
    player.forwarded_input_from_server = forwarded_input

    parent_node.add_child(player)
    return player


## Setup 3-node player configuration with all networked components.
## Returns dict with all created nodes for test access.
static func setup_player_with_networking(
    parent_node: Node,
    player_name: String = "Player"
) -> Dictionary:
    # Ensure network time is initialized BEFORE creating player nodes.
    # This must happen before any networked nodes are created, as their _ready()
    # methods will attempt to set up rollback buffers which require initialized
    # time.
    if not G.network.time.is_time_initialized:
        G.network.time._start_time_offset_usec = 0

    # Also ensure frame tracking is initialized
    if not G.network.frame_driver._is_frame_tracking_initialized:
        G.network.frame_driver._initialize_frame_tracking()

    # Use minimal setup to avoid double-creating networked nodes
    var player = setup_test_player_minimal()
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

    # Add player to tree AFTER all nodes are configured
    parent_node.add_child(player)

    return {
        "player": player,
        "state_from_server": state_from_server,
        "input_from_client": input_from_client,
        "forwarded_input": forwarded_input,
    }


## Cleanup mock level from G singleton.
static func cleanup_mock_level() -> void:
    G.level = null
