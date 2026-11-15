extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func verify(value: bool, label: String) -> void:
	if not value:
		failed = true
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func _run() -> void:
	var game = load("res://scripts/main.gd").new()
	game.score_path = "res://.tools/test-state/bridge-disconnect-scores.json"
	game.settings_path = "res://.tools/test-state/bridge-disconnect-settings.cfg"
	root.add_child(game)
	game.set_process(false)
	game._check_bridge_connection(100.0)
	verify(not game.bridge_disconnect_dialog.visible, "no loss dialog before first heartbeat")
	game._bridge_status_received("BLE searching", 100.0)
	game._check_bridge_connection(103.0)
	verify(game.bridge_connected and not game.bridge_disconnect_dialog.visible, "heartbeat remains valid at timeout")
	game._check_bridge_connection(103.01)
	verify(not game.bridge_connected and game.bridge_disconnect_dialog.visible, "lost heartbeat opens dialog")
	verify(game.bridge_status == "Camera bridge offline", "lost heartbeat updates status")
	game.bridge_disconnect_dialog.hide()
	game._check_bridge_connection(104.0)
	verify(not game.bridge_disconnect_dialog.visible, "dismissed dialog does not repeat during outage")
	game._bridge_status_received("BLE connected", 105.0)
	verify(game.bridge_connected and game.bridge_status == "BLE connected", "heartbeat restores connection")
	game._check_bridge_connection(108.01)
	verify(game.bridge_disconnect_dialog.visible, "new outage opens dialog again")
	game._bridge_status_received("BLE connected", 109.0)
	verify(not game.bridge_disconnect_dialog.visible, "reconnection closes dialog")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", 4242)
	var error := sender.put_packet(JSON.stringify({"type": "status", "message": "UDP heartbeat"}).to_utf8_buffer())
	verify(error == OK, "status packet sent")
	await create_timer(0.05).timeout
	game._poll_input()
	verify(game.bridge_connected and game.bridge_status == "UDP heartbeat", "UDP status updates connection")
	sender.close()
	game.free()
	quit(1 if failed else 0)
