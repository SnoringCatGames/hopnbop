class_name TestSettings
extends Settings

# Minimal settings configuration for CI testing

func _init():
    # Override any settings that might cause issues in CI
    preview_connect_to_remote_server = false
    preview_run_multiple_clients = false
