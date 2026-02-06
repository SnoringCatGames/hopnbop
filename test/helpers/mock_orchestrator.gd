extends Node
## Mock NetworkOrchestrator for testing.

var is_server := true
var is_preview := false
var config: NetworkSettings
var logger: NetworkLogger
var connector: MockConnector
var frame_driver: Node

var is_connected_to_server: bool:
	get:
		return connector.is_connected_to_server

var server_frame_index: int:
	get:
		if frame_driver == null:
			return 0
		return frame_driver.server_frame_index


func _init() -> void:
	connector = MockConnector.new()


## Mock connector for testing.
class MockConnector extends RefCounted:
	var is_connected_to_server := false
