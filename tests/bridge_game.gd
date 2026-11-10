extends SceneTree

var game
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func verify(value: bool, label: String) -> void:
	if not value:
		failed = true
		push_error("FAIL: " + label)
	else: print("PASS: " + label)

func wait_for(predicate: Callable, seconds: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await process_frame
	return false

func _run() -> void:
	game = load("res://scripts/main.gd").new()
	game.score_path = "res://.tools/test-state/bridge-scores.json"
	game.settings_path = "res://.tools/test-state/bridge-settings.cfg"
	root.add_child(game)
	game._show_calibration()
	verify(await wait_for(func() -> bool: return game.camera_texture != null), "camera preview reaches calibration menu")
	# Simulate clicking the preview at known mock projector corners.
	for point in [Vector2(.08,.12), Vector2(.91,.08), Vector2(.94,.88), Vector2(.06,.93)]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = game.PREVIEW.position + point * game.PREVIEW.size
		game._unhandled_input(click)
	verify(game.calibration_points.size() == 4, "four camera preview clicks recorded")
	game._save_calibration()
	verify(await wait_for(func() -> bool: return game.calibration_saved), "HTTP calibration save acknowledged")
	game.input_mode = "Lightgun"
	game._show_menu()
	# F8-equivalent trigger aimed at the Start Game button, through camera detector.
	game.command_udp.put_packet(JSON.stringify({"type":"simulate", "x":.5, "y":.375}).to_utf8_buffer())
	verify(await wait_for(func() -> bool: return game.state == "playing"), "laser operates Start Game menu button")
	game.spawn_timer = 1000.0
	game.actors.clear()
	game.actors.append({"slot":0,"civilian":false,"born":game.elapsed,
		"next_shot":game.elapsed+2.3,"reaction":2.3,"expires":game.elapsed+4,"flash_until":0.0})
	game.stage_bandits_spawned = 1
	var point: Vector2 = game.slots[0] + Vector2(0, -35)
	await create_timer(.55).timeout # Let previous laser extinguish and refill baseline.
	game.command_udp.put_packet(JSON.stringify({"type":"simulate", "x":point.x/640.0, "y":point.y/360.0}).to_utf8_buffer())
	verify(await wait_for(func() -> bool: return game.score > 0), "mock laser -> OpenCV -> UDP -> Godot target hit")
	verify(game.score >= 175 and game.actors.is_empty(), "headshot awarded and bandit removed")
	var before: int = game.score
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1",4242)
	var duplicate := {"type":"shot","found":true,"x":point.x/640.0,"y":point.y/360.0,
		"id":game.seen_shots[-1],"fired_at":Time.get_unix_time_from_system()}
	game.actors.append({"slot":0,"civilian":false,"born":game.elapsed,
		"next_shot":game.elapsed+2.3,"reaction":2.3,"expires":game.elapsed+4,"flash_until":0.0})
	sender.put_packet(JSON.stringify(duplicate).to_utf8_buffer())
	await create_timer(.05).timeout
	verify(game.score == before and game.actors.size() == 1, "duplicate trigger rejected by game")
	duplicate.id = "stale"
	duplicate.fired_at = Time.get_unix_time_from_system() - 2
	sender.put_packet(JSON.stringify(duplicate).to_utf8_buffer())
	await create_timer(.05).timeout
	verify(game.score == before, "expired trigger rejected by game")
	# Complete stage one using a real mock-camera shot, then aim at a generated
	# position in stage two. The bridge's normalized coordinate contract stays fixed.
	game.actors.clear()
	game.stage_bandits_spawned = game.stage_bandits_total - 1
	game.stage_bandits_defeated = game.stage_bandits_total - 1
	game._spawn_actor(true)
	point = game.slots[game.actors[0].slot] + Vector2(0, -35)
	await create_timer(.55).timeout
	game.command_udp.put_packet(JSON.stringify({"type":"simulate", "x":point.x/640.0, "y":point.y/360.0}).to_utf8_buffer())
	verify(await wait_for(func() -> bool: return game.state == "transition"), "lightgun defeat of final bandit clears the stage")
	var old_seed: int = game.town.seed
	game._process(game.STAGE_CLEAR_HOLD + game.STAGE_SCROLL_DURATION)
	verify(game.state == "playing" and game.stage == 2 and game.town.seed != old_seed, "lightgun game arrives in a different generated block")
	game.spawn_timer = 1000.0
	game._spawn_actor(true)
	point = game.slots[game.actors[0].slot] + Vector2(0, -35)
	before = game.score
	var boundary_shot := {"type":"shot", "id":"before-current-stage", "found":true,
		"x":point.x/640.0, "y":point.y/360.0, "fired_at":game.combat_started_at - .01}
	sender.put_packet(JSON.stringify(boundary_shot).to_utf8_buffer())
	await create_timer(.05).timeout
	verify(game.score == before and game.actors.size() == 1, "late packet from before stage arrival cannot hit the new block")
	await create_timer(.55).timeout
	game.command_udp.put_packet(JSON.stringify({"type":"simulate", "x":point.x/640.0, "y":point.y/360.0}).to_utf8_buffer())
	verify(await wait_for(func() -> bool: return game.score > before), "lightgun hits a target at its new procedural position")
	verify(game.stage_bandits_defeated == 1 and game.actors.is_empty(), "new stage tracks the camera hit against its own quota")
	sender.close()
	await process_frame
	game.free()
	await process_frame
	quit(1 if failed else 0)
