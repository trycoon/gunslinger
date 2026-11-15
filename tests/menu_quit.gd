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
	game.score_path = "res://.tools/test-state/menu-quit-scores.json"
	game.settings_path = "res://.tools/test-state/menu-quit-settings.cfg"
	root.add_child(game)
	game.set_process(false)
	var quit_button: Button
	for item in game.buttons:
		var button: Button = item.node
		if button.text == "QUIT":
			quit_button = button
			break
	verify(quit_button != null, "main menu includes quit button")
	quit_button.pressed.emit()
	verify(game.quit_dialog.visible, "quit button opens confirmation dialog")
	verify(game.quit_dialog.ok_button_text == "QUIT", "confirmation requires explicit quit")
	game.quit_dialog.hide()
	verify(not game.quit_dialog.visible, "canceling confirmation keeps game open")
	game.free()
	quit(1 if failed else 0)
