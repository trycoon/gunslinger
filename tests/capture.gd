extends SceneTree

var game

func _initialize() -> void:
	call_deferred("_capture")

func snapshot(filename: String) -> void:
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tools/" + filename)

func _capture() -> void:
	game = load("res://scripts/main.gd").new()
	game.score_path = "res://.tools/test-state/visual-scores.json"
	game.settings_path = "res://.tools/test-state/visual-settings.cfg"
	root.add_child(game)
	game.set_process(false)
	game.bridge_status = "Mouse mode - ready to play"
	await snapshot("menu.png")
	game.input_mode = "Mouse"
	game.mode = "Timed"
	game.rng.seed = 2026
	game._start_game()
	game.stage_bandits_total = 10
	game.stage_bandits_defeated = 2
	game.stage_bandits_spawned = 6
	game.score = 450
	game.elapsed = 1.0
	for index in [0, 2, 4, 6, game.slots.size() - 1]:
		game.actors.append({"slot": index, "civilian": index == 2, "born": 0.0,
			"next_shot": 2.3, "reaction": 2.3, "expires": 4.0, "flash_until": 0.0})
	await snapshot("game.png")
	game._end_game()
	await snapshot("gameover.png")
	game._start_game()
	game.stage_bandits_spawned = game.stage_bandits_total
	game.stage_bandits_defeated = game.stage_bandits_total
	game._check_stage_clear()
	await snapshot("stage-clear.png")
	game._process(game.STAGE_CLEAR_HOLD + game.STAGE_SCROLL_DURATION / 2.0)
	await snapshot("stage-scroll.png")
	game._process(game.STAGE_SCROLL_DURATION)
	await snapshot("stage-2.png")
	game.stage_bandits_spawned = game.stage_bandits_total
	game.stage_bandits_defeated = game.stage_bandits_total
	game._check_stage_clear()
	game._process(game.STAGE_CLEAR_HOLD + game.STAGE_SCROLL_DURATION)
	await snapshot("stage-3.png")
	game.visible = false
	var gallery = load("res://tests/bandit_gallery.gd").new()
	gallery.score_path = "res://.tools/test-state/gallery-scores.json"
	gallery.settings_path = "res://.tools/test-state/gallery-settings.cfg"
	root.add_child(gallery)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tools/bandit-lineup.png")
	gallery.free()
	var civilian_gallery = load("res://tests/civilian_gallery.gd").new()
	civilian_gallery.score_path = "res://.tools/test-state/civilian-gallery-scores.json"
	civilian_gallery.settings_path = "res://.tools/test-state/civilian-gallery-settings.cfg"
	root.add_child(civilian_gallery)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tools/civilian-lineup.png")
	civilian_gallery.free()
	await process_frame
	game.free()
	await process_frame
	quit()
