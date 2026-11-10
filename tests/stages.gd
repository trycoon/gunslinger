extends SceneTree

const Generator := preload("res://scripts/street_generator.gd")
var game
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func shoot_first_bandit() -> void:
	for actor in game.actors:
		if not actor.civilian:
			game._shoot(game.slots[actor.slot] + Vector2(0, -35))
			return

func _run() -> void:
	var sizes: Dictionary = {}
	var obstacle_kinds: Dictionary = {}
	var signatures: Dictionary = {}
	var all_geometry_valid := true
	var all_slots_match_cover := true
	var all_hitboxes_separate := true
	for seed_value in range(200):
		var layout: Dictionary = Generator.generate(seed_value)
		sizes[layout.buildings.size()] = true
		signatures[JSON.stringify(layout)] = true
		var previous_edge := 0.0
		var names: Dictionary = {}
		var cover_points: Array[Vector2] = []
		for building in layout.buildings:
			var rect: Rect2 = building.rect
			all_geometry_valid = all_geometry_valid and rect.position.x >= previous_edge and rect.end.x <= 620 and rect.size.x >= 100
			previous_edge = rect.end.x
			all_geometry_valid = all_geometry_valid and not names.has(building.title)
			names[building.title] = true
			for point in building.windows: cover_points.append(point)
			cover_points.append(building.door)
		for obstacle in layout.obstacles:
			cover_points.append(obstacle.position)
			obstacle_kinds[obstacle.kind] = true
		all_slots_match_cover = all_slots_match_cover and cover_points == layout.slots and layout.slots.size() >= 7
		for index in range(layout.slots.size()):
			var box := Rect2(layout.slots[index] + Vector2(-11, -41), Vector2(22, 41))
			all_geometry_valid = all_geometry_valid and Rect2(0, 50, 640, 290).encloses(box)
			for other in range(index):
				var other_box := Rect2(layout.slots[other] + Vector2(-11, -41), Vector2(22, 41))
				all_hitboxes_separate = all_hitboxes_separate and not box.intersects(other_box)
	check(all_geometry_valid, "200 generated streets keep buildings and target hitboxes in valid bounds")
	check(all_slots_match_cover, "every target slot belongs to a generated window, doorway or obstacle")
	check(all_hitboxes_separate, "generated targets have distinct, non-overlapping hitboxes")
	check(sizes.size() == 2 and obstacle_kinds.size() == 3, "generation varies building count and all obstacle types")
	check(signatures.size() == 200, "different seeds produce different city blocks")
	check(Generator.generate(412) == Generator.generate(412), "a street seed reproduces its layout")

	DirAccess.make_dir_recursive_absolute("res://.tools/test-state")
	game = load("res://scripts/main.gd").new()
	game.score_path = "res://.tools/test-state/stages-scores.json"
	game.settings_path = "res://.tools/test-state/stages-settings.cfg"
	root.add_child(game)
	game.set_process(false)
	game.input_mode = "Mouse"
	game.mode = "Endless"
	game.difficulty = 0
	game.rng.seed = 193
	var quotas: Dictionary = {}
	var quota_bounds_valid := true
	for index in range(40):
		game._start_game()
		quotas[game.stage_bandits_total] = true
		quota_bounds_valid = quota_bounds_valid and game.stage_bandits_total >= 8 and game.stage_bandits_total <= 12
	check(quota_bounds_valid and quotas.size() == 5, "stage quotas randomly cover every total from 8 through 12")
	var found_civilian := false
	for seed_value in range(128):
		game._start_game()
		game.rng.seed = seed_value
		game._spawn_actor()
		if game.actors[0].civilian:
			found_civilian = true
			break
	check(found_civilian and game.stage_bandits_spawned == 0, "civilians do not consume the stage bandit quota")
	if found_civilian:
		game._shoot(game.slots[game.actors[0].slot] + Vector2(0, -35))
		check(game.stage_bandits_defeated == 0 and game.lives == 2 and game.state == "playing", "shooting a civilian costs a life without advancing stage progress")
	game._start_game()
	var first_seed: int = game.town.seed
	var quota: int = game.stage_bandits_total
	for index in range(quota - 1):
		game._spawn_actor(true)
		shoot_first_bandit()
	check(game.state == "playing" and game.stage_bandits_defeated == quota - 1, "empty screen between waves does not finish the stage early")
	# With only one bandit left, no random seed may schedule a two-bandit encounter.
	var pairs_with_one_remaining := false
	for seed_value in range(40):
		game.rng.seed = seed_value
		game.actors.clear()
		game.stage_bandits_spawned = quota - 1
		game.burst_timer = -1.0
		game._spawn_encounter()
		pairs_with_one_remaining = pairs_with_one_remaining or game.burst_timer >= 0.0
	check(not pairs_with_one_remaining, "one remaining bandit never schedules a pair that exceeds the quota")
	game.actors.clear()
	game.stage_bandits_spawned = quota - 1
	game._spawn_actor(true)
	check(game.stage_bandits_spawned == quota and not game._spawn_actor(true), "spawning stops at the exact stage quota")
	game._check_stage_clear()
	check(game.state == "playing", "last live bandit prevents stage completion")
	game.elapsed = game.actors[0].next_shot
	game._tick_game(0.01)
	check(game.lives == 2, "the last bandit still fires after the spawn quota is reached")
	# A surviving civilian does not need to be shot or waited out to clear a stage.
	var civilian_slot: int = (int(game.actors[0].slot) + 1) % game.slots.size()
	game.actors.append({"slot": civilian_slot, "civilian": true, "born": game.elapsed,
		"expires": game.elapsed + 4.0, "next_shot": 9999.0, "reaction": 5.2, "flash_until": 0.0})
	shoot_first_bandit()
	check(game.state == "transition" and game.stage_bandits_defeated == quota, "defeating the final bandit starts the transition")
	check(game.actors.is_empty() and game.next_town.seed != first_seed, "transition clears civilians and prepares a new street")
	var carried_score: int = game.score
	game.magazine = true
	game.ammo = 2
	var active_time: float = game.elapsed
	game._shoot(Vector2(200, 200))
	game._reload()
	check(game.score == carried_score and game.ammo == 2 and game.reload_left == 0.0, "shots and reloading are disabled while scrolling")
	check(not game._spawn_actor(true), "no targets can spawn during a transition")
	game._process(game.STAGE_CLEAR_HOLD + game.STAGE_SCROLL_DURATION / 2.0)
	check(game.state == "transition" and game.stage == 1 and is_equal_approx(game.elapsed, active_time), "scroll keeps the old stage and freezes the active-play clock")
	var midpoint: float = game.transition_elapsed
	game._pause()
	game._process(3.0)
	check(game.state == "paused" and is_equal_approx(game.transition_elapsed, midpoint), "pause freezes the transition midway")
	game._resume_game()
	check(game.state == "transition", "resume returns to the interrupted scroll")
	var second_seed: int = game.next_town.seed
	game._process(game.STAGE_SCROLL_DURATION)
	check(game.state == "playing" and game.stage == 2 and game.town.seed == second_seed, "scroll arrives in the next procedural street")
	check(game.next_town.is_empty() and game.actors.is_empty() and game.stage_bandits_spawned == 0 and game.stage_bandits_defeated == 0, "arrival resets stage targets and releases the old block")
	check(game.lives == 2 and game.ammo == 2 and game.score == carried_score, "lives, ammunition and score carry across stages")
	check(game.slots == game.town.slots and game.stage_bandits_total >= 8 and game.stage_bandits_total <= 12, "new stage uses its generated slots and its own quota")
	check(game.spawn_timer > 0.0 and game.burst_timer < 0.0, "new stage starts with a fresh random wait")
	# Check the final quota boundary when a pending pair supplies the last two bandits.
	game._start_game()
	game.stage_bandits_spawned = game.stage_bandits_total - 2
	game.stage_bandits_defeated = game.stage_bandits_spawned
	game._spawn_actor(true)
	game.burst_timer = 0.2
	shoot_first_bandit()
	check(game.state == "playing" and game.burst_timer >= 1.5, "a pending final partner prevents premature completion and respects the kill pause")
	game._process(1.51)
	check(game.actors.size() == 1 and game.stage_bandits_spawned == game.stage_bandits_total, "pending partner consumes exactly the final quota slot")
	shoot_first_bandit()
	check(game.state == "transition", "defeating the final partner clears the stage")
	game._show_menu()
	game._process(5.0)
	check(game.state == "menu" and game.next_town.is_empty(), "returning to menu cancels a pending scroll")
	# Timed mode still ends after 90 active seconds, even between stages.
	game.mode = "Timed"
	game._start_game()
	game.elapsed = 89.9
	game.stage_bandits_spawned = game.stage_bandits_total
	game.stage_bandits_defeated = game.stage_bandits_total
	game._check_stage_clear()
	game._process(3.0)
	check(game.state == "playing" and game.stage == 2 and is_equal_approx(game.elapsed, 89.9), "timed mode does not consume play time during a scroll")
	game._process(0.2)
	check(game.state == "gameover", "timed mode ends normally after the next active-play tick")
	game._start_game()
	check(game.stage == 1 and game.stage_bandits_defeated == 0 and game.lives == 3 and game.score == 0, "a new run resets stage progression and run statistics")

	print("Stages and city: %d checks, %d failures" % [checks, failures])
	await process_frame
	game.free()
	await process_frame
	quit(1 if failures else 0)
