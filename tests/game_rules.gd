extends SceneTree

var failures := 0
var checks := 0
var game

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func actor(civilian: bool = false) -> Dictionary:
	return {"slot": 0, "civilian": civilian, "born": 0.0, "next_shot": 2.3,
		"reaction": 2.3, "expires": 4.0, "flash_until": 0.0}

func target_point(head: bool = true, slot: int = 0) -> Vector2:
	return game.slots[slot] + Vector2(0, -35 if head else -12)

func fresh() -> void:
	game._start_game()
	game.spawn_timer = 1000.0

func start_pair() -> bool:
	for seed_value in range(128):
		fresh()
		game.rng.seed = seed_value
		game._spawn_encounter()
		if game.burst_timer > 0.0: return true
	return false

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.tools/test-state")
	game = load("res://scripts/main.gd").new()
	game.score_path = "res://.tools/test-state/highscores.json"
	game.settings_path = "res://.tools/test-state/settings.cfg"
	root.add_child(game)
	game.set_process(false)
	game.highscores.clear()
	game.input_mode = "Mouse"
	game.mode = "Endless"
	game.difficulty = 1
	game.magazine = false
	game.rng.seed = 104729

	check(game.DIFFICULTIES == ["Easy", "Medium", "Hard"], "difficulty labels match the rebalanced levels")
	var initial_reaction_times := [5.2, 3.2, 2.3]
	var initial_target_limits := [2, 2, 3]
	for level in range(3):
		game.difficulty = level
		fresh()
		game._spawn_actor()
		var bandit: Dictionary = game.actors[0]
		bandit.civilian = false
		var deadline: float = initial_reaction_times[level]
		check(is_equal_approx(bandit.next_shot, deadline), "level %d uses the new firing delay" % level)
		game.elapsed = deadline - 0.01
		game._tick_game(0.001)
		check(game.lives == 3, "level %d does not fire before its deadline" % level)
		game.elapsed = deadline
		game._tick_game(0.001)
		check(game.lives == 2, "level %d fires when its deadline arrives" % level)
		fresh()
		for index in range(12): game._spawn_actor()
		check(game.actors.size() == initial_target_limits[level], "level %d uses the rebalanced target limit" % level)
	game.difficulty = 1

	fresh()
	game.spawn_timer = 0.01
	game.actors.append(actor())
	var remaining_bandit := actor()
	remaining_bandit.slot = 1
	remaining_bandit.next_shot = 1.0
	game.actors.append(remaining_bandit)
	game._shoot(target_point())
	check(game.spawn_timer >= 1.5, "defeating a bandit postpones an imminent spawn")
	game._process(1.0)
	check(game.actors.size() == 1 and game.lives == 2, "existing bandits still fire during the spawn pause")
	game._process(0.49)
	check(game.actors.size() == 1, "no replacement appears before the 1.5-second pause ends")
	game._process(0.02)
	check(game.actors.size() == 2, "spawning resumes after the pause")

	fresh()
	game.elapsed = 3600.0
	game.spawn_timer = 0.01
	game.actors.append(actor())
	game._shoot(target_point())
	game._process(1.49)
	check(game.actors.is_empty(), "late-game scaling does not shorten the post-hit spawn pause")
	game._process(0.02)
	check(game.actors.size() == 1, "late-game spawns resume after the pause")
	game._start_game()
	check(game.spawn_timer >= 1.5 and game.spawn_timer <= 6.5 and game.burst_timer < 0.0, "a new run starts with a random wait and clears pending pairs")

	game.spawn_timer = 0.03
	game._shoot(Vector2.ZERO)
	check(is_equal_approx(game.spawn_timer, 0.03), "a miss does not delay spawns")
	game.actors.append(actor(true))
	game._shoot(target_point(false))
	check(is_equal_approx(game.spawn_timer, 0.03), "shooting a civilian does not delay spawns")

	var normal_ranges := [Vector2(2.0, 4.0), Vector2(1.5, 3.2), Vector2(1.0, 2.5)]
	var long_ranges := [Vector2(4.5, 7.5), Vector2(3.5, 6.5), Vector2(3.0, 5.0)]
	for level in range(3):
		game.difficulty = level
		fresh()
		game.rng.seed = 724
		var long_count := 0
		var delays: Dictionary = {}
		var valid_ranges := true
		for index in range(256):
			var delay: float = game._next_spawn_delay()
			delays[delay] = true
			if delay >= long_ranges[level].x and delay <= long_ranges[level].y:
				long_count += 1
			elif delay < normal_ranges[level].x or delay > normal_ranges[level].y:
				valid_ranges = false
		check(valid_ranges, "level %d waits stay inside the normal or long range" % level)
		check(delays.size() > 32, "level %d waits vary rather than repeating a fixed interval" % level)
		check(long_count >= 20 and long_count <= 90, "level %d has occasional long pauses, not constant silence" % level)
		game.elapsed = 3600.0
		var saw_long_pause := false
		var valid_late_ranges := true
		for index in range(128):
			var delay: float = game._next_spawn_delay()
			if delay >= long_ranges[level].x and delay <= long_ranges[level].y:
				saw_long_pause = true
			elif not is_equal_approx(delay, 0.8):
				valid_late_ranges = false
		check(saw_long_pause and valid_late_ranges, "level %d keeps long pauses and the normal minimum late in a run" % level)
	game.difficulty = 0

	var found_pair := start_pair()
	check(found_pair, "random encounter selection can produce a pair")
	if found_pair:
		check(game.actors.size() == 1 and not game.actors[0].civilian, "a pair starts with a bandit")
		check(game.burst_timer >= 0.15 and game.burst_timer <= 0.35, "second bandit is scheduled close to the first")
		game._process(0.14)
		check(game.actors.size() == 1, "second bandit does not appear before the pair gap")
		game._process(0.22)
		check(game.actors.size() == 2 and not game.actors[1].civilian, "second member of a pair is also a bandit")
		check(game.actors[0].slot != game.actors[1].slot, "paired bandits occupy different positions")
		check(game.burst_timer < 0.0 and game.spawn_timer >= 2.0, "a new random wait follows the pair")
		# Even if a large frame consumes the wait, a pair cannot overflow the target cap.
		game.spawn_timer = 0.0
		game._process(0.01)
		check(game.actors.size() == 2 and game.burst_timer < 0.0 and game.spawn_timer > 0.0, "full screen skips the encounter and schedules another wait")

	fresh()
	game.actors.append(actor())
	game._spawn_encounter()
	check(game.actors.size() == 2 and game.burst_timer < 0.0, "only one free slot prevents scheduling a pair")

	found_pair = start_pair()
	if found_pair:
		var point: Vector2 = game.slots[game.actors[0].slot] + Vector2(0, -35)
		game._shoot(point)
		check(game.burst_timer >= 1.5, "killing the first bandit postpones its pending partner")
		game._process(1.49)
		check(game.actors.is_empty(), "a pending partner respects the 1.5-second post-kill pause")
		game._process(0.02)
		check(game.actors.size() == 1 and not game.actors[0].civilian, "the postponed partner eventually appears")

	found_pair = start_pair()
	if found_pair:
		var pending_gap: float = game.burst_timer
		game._pause()
		game._process(1.0)
		check(is_equal_approx(game.burst_timer, pending_gap) and game.actors.size() == 1, "pausing freezes a pending pair")
		game._start_game()
		check(game.actors.is_empty() and game.burst_timer < 0.0, "restarting clears a pending pair")
	game.difficulty = 1

	fresh()
	game.actors.append(actor())
	game._shoot(target_point())
	check(game.score == 275 and game.actors.is_empty(), "headshot + immediate speed bonus")

	fresh()
	game.elapsed = 1.15
	game.actors.append(actor())
	game._shoot(target_point(false))
	check(game.score == 150, "body hit + decayed speed bonus")

	fresh()
	game.actors.append(actor(true))
	game._shoot(target_point(false))
	check(game.lives == 2 and game.score == 0, "civilian costs life, no points")

	fresh()
	game.actors.append(actor())
	game.elapsed = 2.4
	game._tick_game(0.01)
	check(game.lives == 2 and game.actors.size() == 1, "enemy fires and remains")
	game.elapsed = game.actors[0].next_shot + 0.01
	game._tick_game(0.01)
	check(game.lives == 1 and game.actors.size() == 1, "same enemy fires again")
	game.elapsed = game.actors[0].next_shot + 0.01
	game._tick_game(0.01)
	check(game.lives == 0 and game.state == "gameover", "third hit ends run")

	game.magazine = true
	fresh()
	for index in range(6): game._shoot(Vector2.ZERO)
	check(game.ammo == 0, "six shots empty magazine")
	game.actors.append(actor())
	game._shoot(target_point())
	check(game.score == 0 and game.actors.size() == 1, "empty magazine cannot hit")
	game._reload()
	game._shoot(target_point())
	check(game.score == 0, "cannot shoot during reload")
	game._tick_game(1.0)
	check(game.ammo == 6 and game.reload_left == 0.0, "reload refills magazine")
	game._shoot(Vector2.ZERO, false)
	check(game.ammo == 5 and game.score == 0, "undetected shot consumes ammunition")

	game.input_mode = "Lightgun"
	game.magazine = true
	fresh()
	check(not game.magazine, "lightgun forces infinite ammunition")
	for index in range(12): game._shoot(Vector2.ZERO)
	check(game.ammo == 6, "infinite ammunition stays available")

	game.mode = "Timed"
	fresh()
	game.elapsed = 89.9
	game._process(0.2)
	check(game.state == "gameover" and game.lives == 3, "timed run ends after 90 seconds")

	game.input_mode = "Mouse"
	game.mode = "Endless"
	game.magazine = false
	fresh()
	game.score = 1234
	game._end_game()
	game.name_edit.text = "test!"
	game._save_score()
	game.highscores.clear()
	game._load_scores()
	var rows: Array = game.highscores.get(game._score_key(), [])
	check(rows.size() == 1 and rows[0].name == "TEST" and rows[0].score == 1234, "highscore survives reload")
	game._save_settings()
	game.difficulty = 2
	game._load_settings()
	check(game.difficulty == 1, "settings survive reload")

	game.mode = "Endless"
	fresh()
	game._pause()
	game._process(1.0)
	check(game.elapsed == 0.0 and game.state == "paused", "pause freezes game time")

	print("Game rules: %d checks, %d failures" % [checks, failures])
	await process_frame
	game.free()
	await process_frame
	quit(1 if failures else 0)
