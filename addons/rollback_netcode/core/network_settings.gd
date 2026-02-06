class_name NetworkSettings
extends Resource
## Configuration for rollback netcode plugin.
##
## This allows users to edit network settings via Godot's Inspector panel. Users
## can create a .tres file or subclass this Resource to customize network
## behavior.
##
## Usage:
## 1. Create a .tres file: Right-click in FileSystem > New Resource >
##    NetworkSettings
## 2. Edit properties in Inspector panel
## 3. Load in code: var config := load("res://network_settings.tres")
##
## Or subclass for custom logic:
## ```gdscript
## class_name MyGameConfig
## extends NetworkSettings
##
## @export var custom_setting := true
## ```


## Network settings.
## Port number for server to listen on / client to connect to.
@export var server_port := 4433

## Maximum number of simultaneous client connections.
@export var max_client_count := 4

## Target network tick rate in frames per second.
## This determines the simulation frequency for networked game state.
## Common values: 30 (lower bandwidth), 60 (standard), 120 (high precision).
@export var target_network_fps := 60.0

## Duration of rollback buffer in seconds.
@export var rollback_buffer_duration_sec := 1.5


## Pause settings.
## Whether server-initiated pause is enabled.
@export var is_server_pause_enabled := false

## Maximum number of pause requests per client (if pause is enabled).
@export var max_pauses_per_client := 1

## Cooldown between pause requests in seconds.
@export var pause_request_cooldown_sec := 30.0

## Maximum pause duration before auto-unpause (seconds).
@export var max_pause_duration_sec := 60.0


## Preview mode (local multi-instance testing).
## Whether running in local preview mode (multiple instances in editor).
var is_preview_mode := false

## Whether to run multiple client instances in preview mode.
@export var preview_run_multiple_clients := false

## Expected number of clients in preview mode.
var preview_client_count: int:
	get:
		return 2 if preview_run_multiple_clients else 1

## Whether to connect to remote server in preview mode (false = local only).
@export var preview_connect_to_remote_server := false

## Local server IP for preview mode.
@export var local_preview_server_ip_address := &"127.0.0.1"


## Player settings.
## Maximum number of local players per client (split-screen/couch co-op).
@export var max_local_player_count := 4


## Debug/performance tracking.
## Whether to enable perf logging.
@export var tracking_perf := true

## Whether to include verbose/debug logs in output.
## When disabled, verbose() calls are skipped (no string manipulation overhead).
@export var includes_verbose_logs := false
