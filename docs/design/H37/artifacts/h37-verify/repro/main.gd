# H37 verify: minimal engine repro of the hopnbop client crash. The client
# handles the server's peer_disconnected the way rollback_netcode does
# (network_connector.gd:363 emits inside the engine callback) and then:
#   replace:  assigns a new ENet client peer at once (reconnect_handler.gd:193
#             -> network_connector.gd:293);
#   null:     closes and nulls the peer at once (game_panel.gd:1250-1284);
#   deferred: does the replace via call_deferred (the proposed fix).
extends Node

var role := ""
var variant := ""
var port := 0


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	role = args.get("role", "")
	variant = args.get("variant", "")
	port = int(args.get("port", "0"))
	print("build: editor=%s debug=%s template_release=%s" % [
		OS.has_feature("editor"), OS.is_debug_build(),
		OS.has_feature("template_release")])
	var peer := ENetMultiplayerPeer.new()
	if role == "server":
		print("server: create_server err=%d" % peer.create_server(port, 4))
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_server_on_connected)
		get_tree().create_timer(15.0).timeout.connect(get_tree().quit.bind(3))
	else:
		print("client: create_client err=%d variant=%s" % [
			peer.create_client("127.0.0.1", port), variant])
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(
			func() -> void: print("client: connected"))
		multiplayer.peer_disconnected.connect(_client_on_disconnected)
		multiplayer.server_disconnected.connect(
			func() -> void: print("client: server_disconnected"))
		get_tree().create_timer(6.0).timeout.connect(_client_survived)


func _server_on_connected(id: int) -> void:
	if OS.get_cmdline_user_args().has("--spawn"):
		var p: Node = load("res://player.tscn").instantiate()
		p.name = "Player_%d" % id
		$Level.add_child(p, true)
		print("server: spawned %s" % p.name)
	print("server: peer %d connected; quitting in 1.0 s" % id)
	await get_tree().create_timer(1.0).timeout
	print("server: quit")
	get_tree().quit(0)


func _client_on_disconnected(id: int) -> void:
	print("client: peer_disconnected %d, variant=%s, level children=%d" % [id, variant, $Level.get_child_count()])
	match variant:
		"replace":
			var p := ENetMultiplayerPeer.new()
			p.create_client("127.0.0.1", port)
			multiplayer.multiplayer_peer = p
		"null":
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
		"deferred":
			_replace.call_deferred()
	print("client: handler returned")


func _replace() -> void:
	var p := ENetMultiplayerPeer.new()
	p.create_client("127.0.0.1", port)
	multiplayer.multiplayer_peer = p
	print("client: deferred replace done")


func _client_survived() -> void:
	print("client: survived 6 s, exit 0")
	get_tree().quit(0)

