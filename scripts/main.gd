extends Node2D

const StreetGenerator := preload("res://scripts/street_generator.gd")
const BanditAppearance := preload("res://scripts/bandit_appearance.gd")
const CivilianAppearance := preload("res://scripts/civilian_appearance.gd")
const SIZE := Vector2(640, 360)
const PREVIEW := Rect2(18, 74, 320, 240)
var score_path := "user://highscores.json"
var settings_path := "user://settings.cfg"
const DIFFICULTIES := ["Easy", "Medium", "Hard"]
const BANDIT_RESPAWN_DELAY := 1.5
const LONG_PAUSE_CHANCE := 0.20
const BANDIT_PAIR_CHANCE := 0.18
const BANDIT_PAIR_GAP := Vector2(0.15, 0.35)
const STAGE_CLEAR_HOLD := 0.8
const STAGE_SCROLL_DURATION := 1.8
const RULES := [
	{"max": 2, "reaction": 5.2, "wait": Vector2(2.0, 4.0), "long_wait": Vector2(4.5, 7.5)},
	{"max": 2, "reaction": 3.2, "wait": Vector2(1.5, 3.2), "long_wait": Vector2(3.5, 6.5)},
	{"max": 3, "reaction": 2.3, "wait": Vector2(1.0, 2.5), "long_wait": Vector2(3.0, 5.0)},
]
var slots: Array[Vector2] = []
var town: Dictionary = {}
var next_town: Dictionary = {}
var stage := 1
var stage_bandits_total := 0
var stage_bandits_spawned := 0
var stage_bandits_defeated := 0
var transition_elapsed := 0.0
var paused_state := "playing"
var combat_started_at := 0.0

var state := "menu"
var input_mode := "Mouse"
var mode := "Endless"
var difficulty := 1
var magazine := false
var lives := 3
var ammo := 6
var score := 0
var elapsed := 0.0
var spawn_timer := 0.0
var burst_timer := -1.0
var reload_left := 0.0
var damage_flash := 0.0
var muzzle_flash := 0.0
var message := ""
var message_left := 0.0
var actors: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var highscores: Dictionary = {}
var ui: Control
var buttons: Array[Dictionary] = []
var font: Font
var udp := PacketPeerUDP.new()
var command_udp := PacketPeerUDP.new()
var camera_request := HTTPRequest.new()
var config_request := HTTPRequest.new()
var camera_texture: ImageTexture
var preview_timer := 0.0
var preview_busy := false
var preview_error := "Start the camera bridge to see a preview."
var calibration_points: Array[Vector2] = []
var saved_points: Array[Vector2] = []
var calibration_saved := false
var calibration_post_pending := false
var bridge_status := "Camera bridge offline"
var bridge_last_seen := -100.0
var name_edit: LineEdit
var audio_players: Dictionary = {}
var rng := RandomNumberGenerator.new()
var saved_run := false
var seen_shots: Array[String] = []

func _ready() -> void:
	Engine.max_fps = 60
	font = ThemeDB.fallback_font
	rng.randomize()
	town = StreetGenerator.generate(rng.randi())
	slots.assign(town.slots)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	add_child(camera_request)
	add_child(config_request)
	camera_request.timeout = 1.0
	config_request.timeout = 2.0
	camera_request.request_completed.connect(_camera_received)
	config_request.request_completed.connect(_config_received)
	var result := udp.bind(4242, "127.0.0.1")
	if result != OK:
		bridge_status = "Input port 4242 unavailable"
	command_udp.set_dest_address("127.0.0.1", 4243)
	_load_settings()
	_load_scores()
	if DisplayServer.get_name() != "headless":
		for sound in ["shot", "reload", "enemy", "civilian", "draw", "dont_shoot", "got_me"]:
			var player := AudioStreamPlayer.new()
			var sound_path := "res://assets/audio/%s.wav" % sound
			if not ResourceLoader.exists(sound_path):
				player.free()
				continue
			player.stream = load(sound_path)
			player.volume_db = -10.0
			add_child(player)
			audio_players[sound] = player
	_show_menu()

func _exit_tree() -> void:
	for player in audio_players.values():
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	udp.close()
	command_udp.close()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		input_mode = str(cfg.get_value("game", "input", "Mouse"))
		if input_mode not in ["Mouse", "Lightgun"]:
			input_mode = "Mouse"
		mode = str(cfg.get_value("game", "mode", "Endless"))
		if mode not in ["Endless", "Timed"]:
			mode = "Endless"
		difficulty = clampi(int(cfg.get_value("game", "difficulty", 1)), 0, 2)
		magazine = bool(cfg.get_value("game", "magazine", false)) and input_mode == "Mouse"

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "input", input_mode)
	cfg.set_value("game", "mode", mode)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "magazine", magazine)
	if cfg.save(settings_path) != OK:
		_notice("Could not save settings")

func _load_scores() -> void:
	if not FileAccess.file_exists(score_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(score_path))
	if parsed is Dictionary:
		for key in parsed:
			if not parsed[key] is Array:
				continue
			var valid: Array = []
			for entry in parsed[key]:
				if entry is Dictionary and entry.get("name") is String and entry.get("score") is float:
					valid.append({"name": _clean_name(entry.name), "score": maxi(0, int(entry.score))})
			valid.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
			highscores[str(key)] = valid.slice(0, 10)

func _clean_name(value: String) -> String:
	var cleaned := ""
	for character in value.to_upper():
		if character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
			cleaned += character
		if cleaned.length() == 8:
			break
	return cleaned if not cleaned.is_empty() else "AAA"

func _score_key() -> String:
	return "%s/%s/%s/%s" % [mode, DIFFICULTIES[difficulty], input_mode, "Six" if magazine else "Infinite"]

func _save_score() -> void:
	if saved_run:
		return
	var key := _score_key()
	var rows: Array = highscores.get(key, []).duplicate(true)
	rows.append({"name": _clean_name(name_edit.text), "score": score})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	highscores[key] = rows.slice(0, 10)
	var file := FileAccess.open(score_path + ".tmp", FileAccess.WRITE)
	if file == null:
		_notice("Could not save highscore")
		return
	file.store_string(JSON.stringify(highscores, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(score_path + ".tmp"), ProjectSettings.globalize_path(score_path))
	if err != OK:
		_notice("Could not save highscore")
		return
	saved_run = true
	_show_scores()

func _clear_ui() -> void:
	for child in ui.get_children():
		ui.remove_child(child)
		child.queue_free()
	buttons.clear()

func _button(text_value: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("f7e5c3"))
	button.add_theme_color_override("font_hover_color", Color("fff2d8"))
	button.add_theme_color_override("font_disabled_color", Color("837969"))
	for appearance in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("3b3227")
		if appearance == "hover": style.bg_color = Color("65523a")
		elif appearance == "pressed": style.bg_color = Color("92724c")
		elif appearance == "disabled": style.bg_color = Color("26231f")
		style.border_color = Color("806b46")
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		button.add_theme_stylebox_override(appearance, style)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	ui.add_child(button)
	buttons.append({"node": button, "action": action})
	return button

func _notice(value: String) -> void:
	message = value
	message_left = 2.5

func _show_menu() -> void:
	state = "menu"
	actors.clear()
	next_town = {}
	burst_timer = -1.0
	_clear_ui()
	_button("START GAME", Rect2(222, 119, 196, 31), _start_game)
	_button("INPUT: " + input_mode, Rect2(222, 156, 196, 26), func() -> void:
		input_mode = "Lightgun" if input_mode == "Mouse" else "Mouse"
		if input_mode == "Lightgun": magazine = false
		_save_settings()
		_show_menu())
	_button("MODE: " + mode, Rect2(222, 188, 196, 26), func() -> void:
		mode = "Timed" if mode == "Endless" else "Endless"
		_save_settings()
		_show_menu())
	_button("DIFFICULTY: " + DIFFICULTIES[difficulty], Rect2(222, 220, 196, 26), func() -> void:
		difficulty = (difficulty + 1) % 3
		_save_settings()
		_show_menu())
	var ammo_button := _button("AMMO: " + ("6 SHOTS" if magazine else "INFINITE"), Rect2(222, 252, 196, 26), func() -> void:
		magazine = not magazine
		_save_settings()
		_show_menu())
	ammo_button.disabled = input_mode == "Lightgun"
	_button("CALIBRATION", Rect2(122, 294, 124, 26), _show_calibration)
	_button("HIGHSCORES", Rect2(258, 294, 124, 26), _show_scores)
	_button("QUIT", Rect2(394, 294, 124, 26), func() -> void: get_tree().quit())

func _start_game() -> void:
	_clear_ui()
	state = "playing"
	actors.clear()
	shots.clear()
	lives = 3
	ammo = 6
	score = 0
	elapsed = 0.0
	stage = 1
	reload_left = 0.0
	damage_flash = 0.0
	saved_run = false
	magazine = magazine and input_mode == "Mouse"
	_begin_stage(StreetGenerator.generate(rng.randi()))
	_sound("draw")

func _begin_stage(layout: Dictionary) -> void:
	town = layout
	slots.assign(town.slots)
	next_town = {}
	stage_bandits_total = rng.randi_range(8, 12)
	stage_bandits_spawned = 0
	stage_bandits_defeated = 0
	actors.clear()
	shots.clear()
	spawn_timer = _next_spawn_delay()
	burst_timer = -1.0
	transition_elapsed = 0.0
	combat_started_at = Time.get_unix_time_from_system()
	state = "playing"

func _check_stage_clear() -> void:
	if state != "playing" or stage_bandits_spawned < stage_bandits_total or stage_bandits_defeated < stage_bandits_total: return
	for actor in actors:
		if not actor.civilian: return
	state = "transition"
	actors.clear()
	shots.clear()
	burst_timer = -1.0
	transition_elapsed = 0.0
	message_left = 0.0
	next_town = StreetGenerator.generate(rng.randi())

func _tick_transition(delta: float) -> void:
	transition_elapsed += delta
	if transition_elapsed >= STAGE_CLEAR_HOLD + STAGE_SCROLL_DURATION:
		stage += 1
		_begin_stage(next_town)

func _end_game() -> void:
	if state != "playing": return
	state = "gameover"
	_clear_ui()
	name_edit = LineEdit.new()
	name_edit.position = Vector2(254, 152)
	name_edit.size = Vector2(132, 26)
	name_edit.max_length = 8
	name_edit.text = ""
	name_edit.placeholder_text = "Your initials"
	name_edit.add_theme_font_size_override("font_size", 14)
	ui.add_child(name_edit)
	for index in range(26):
		var letter := String.chr(65 + index)
		_button(letter, Rect2(168 + (index % 13) * 24, 190 + (index / 13) * 25, 22, 23), func() -> void:
			if name_edit.text.length() < 8: name_edit.text += letter)
	_button("DELETE", Rect2(206, 249, 100, 26), func() -> void: name_edit.text = name_edit.text.left(maxi(0, name_edit.text.length() - 1)))
	_button("SAVE SCORE", Rect2(316, 249, 118, 26), _save_score)
	_button("PLAY AGAIN", Rect2(206, 290, 100, 27), _start_game)
	_button("MENU", Rect2(316, 290, 118, 27), _show_menu)

func _show_scores() -> void:
	state = "scores"
	_clear_ui()
	_button("BACK", Rect2(260, 308, 120, 28), _show_menu)

func _pause() -> void:
	if state not in ["playing", "transition"]: return
	paused_state = state
	state = "paused"
	_clear_ui()
	_button("RESUME", Rect2(232, 160, 176, 32), _resume_game)
	_button("MAIN MENU", Rect2(232, 204, 176, 32), _show_menu)

func _resume_game() -> void:
	_clear_ui()
	state = paused_state

func _show_calibration() -> void:
	state = "calibration"
	_clear_ui()
	calibration_points.clear()
	calibration_saved = false
	preview_timer = 0.0
	config_request.request("http://127.0.0.1:4244/calibration")
	_button("RESET POINTS", Rect2(361, 239, 253, 24), func() -> void:
		calibration_points.clear()
		calibration_saved = false)
	_button("SAVE CALIBRATION", Rect2(361, 268, 253, 24), _save_calibration)
	_button("BACK", Rect2(361, 297, 253, 24), _show_menu)

func _save_calibration() -> void:
	if calibration_points.size() != 4:
		_notice("Select all four corners first")
		return
	var points: Array = []
	for point in calibration_points: points.append([point.x, point.y])
	var err := config_request.request("http://127.0.0.1:4244/calibration", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify({"corners": points}))
	calibration_post_pending = err == OK
	if err != OK: _notice("Camera bridge unavailable")

func _config_received(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or not parsed is Dictionary:
		calibration_post_pending = false
		_notice(str(parsed.get("error", "Camera bridge unavailable")) if parsed is Dictionary else "Camera bridge unavailable")
		return
	saved_points.clear()
	var values: Variant = parsed.get("corners", [])
	if values is Array:
		for point in values:
			if point is Array and point.size() == 2:
				saved_points.append(Vector2(float(point[0]), float(point[1])))
	if calibration_post_pending:
		calibration_post_pending = false
		calibration_saved = true
		_notice("Calibration saved")

func _camera_received(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	preview_busy = false
	if code != 200:
		preview_error = "No camera preview. Check the bridge."
		return
	var image := Image.new()
	if image.load_jpg_from_buffer(body) == OK:
		camera_texture = ImageTexture.create_from_image(image)
		preview_error = ""

func _process(delta: float) -> void:
	_poll_input()
	var now := Time.get_ticks_msec() / 1000.0
	if now - bridge_last_seen > 3.0: bridge_status = "Camera bridge offline"
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if state in ["playing", "transition"] else Input.MOUSE_MODE_VISIBLE
	message_left = maxf(0.0, message_left - delta)
	damage_flash = maxf(0.0, damage_flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	for shot in shots: shot.ttl -= delta
	shots = shots.filter(func(shot: Dictionary) -> bool: return shot.ttl > 0.0)
	if state == "calibration":
		preview_timer -= delta
		if preview_timer <= 0.0 and not preview_busy:
			preview_timer = 0.15
			preview_busy = camera_request.request("http://127.0.0.1:4244/frame.jpg") == OK
	if state == "playing":
		elapsed += delta
		if mode == "Timed" and elapsed >= 90.0:
			_end_game()
		else:
			_tick_game(delta)
	elif state == "transition":
		_tick_transition(delta)
	queue_redraw()

func _tick_game(delta: float) -> void:
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		if reload_left == 0.0: ammo = 6
	var reaction := _reaction_time()
	for actor in actors.duplicate():
		if actor.civilian:
			if elapsed >= actor.expires: actors.erase(actor)
		elif elapsed >= actor.next_shot:
			actor.next_shot = elapsed + reaction * 1.3
			actor.flash_until = elapsed + 0.16
			_sound("enemy")
			_damage()
			if state != "playing": return
	if stage_bandits_spawned >= stage_bandits_total:
		burst_timer = -1.0
		return
	spawn_timer -= delta
	if burst_timer >= 0.0:
		burst_timer -= delta
		if burst_timer <= 0.0:
			burst_timer = -1.0
			_spawn_actor(true)
			# Start a fresh wait after the pair, rather than adding a third target immediately.
			spawn_timer = _next_spawn_delay()
	elif spawn_timer <= 0.0:
		_spawn_encounter()

func _next_spawn_delay() -> float:
	var rule: Dictionary = RULES[difficulty]
	if rng.randf() < LONG_PAUSE_CHANCE:
		# Keep occasional long waits even late in a run, so the tension does not disappear.
		var long_wait: Vector2 = rule.long_wait
		return rng.randf_range(long_wait.x, long_wait.y)
	var wait: Vector2 = rule.wait
	return maxf(0.8, rng.randf_range(wait.x, wait.y) / (1.0 + elapsed / 120.0))

func _maximum_targets() -> int:
	return mini(7, int(RULES[difficulty].max) + int(elapsed / 40.0))

func _spawn_encounter() -> void:
	if state != "playing" or stage_bandits_spawned >= stage_bandits_total: return
	var pair := stage_bandits_total - stage_bandits_spawned >= 2 and _maximum_targets() - actors.size() >= 2 and rng.randf() < BANDIT_PAIR_CHANCE
	if _spawn_actor(pair) and pair:
		burst_timer = rng.randf_range(BANDIT_PAIR_GAP.x, BANDIT_PAIR_GAP.y)
		spawn_timer = 0.0
	else:
		spawn_timer = _next_spawn_delay()

func _reaction_time() -> float:
	return maxf(0.8, float(RULES[difficulty].reaction) / (1.0 + elapsed / 180.0))

func _spawn_actor(force_bandit: bool = false) -> bool:
	if state != "playing" or stage_bandits_spawned >= stage_bandits_total or actors.size() >= _maximum_targets(): return false
	var available: Array[int] = []
	for slot in range(slots.size()):
		var occupied := false
		for actor in actors:
			if actor.slot == slot: occupied = true
		if not occupied: available.append(slot)
	if available.is_empty(): return false
	var slot := available[rng.randi_range(0, available.size() - 1)]
	var reaction := _reaction_time()
	var civilian := not force_bandit and rng.randf() < 0.23
	if not civilian: stage_bandits_spawned += 1
	var appearance: Dictionary = {}
	if civilian:
		appearance = CivilianAppearance.generate(hash("%s:%s:%s:%s" % [town.seed, stage, slot, elapsed]))
	else:
		appearance = BanditAppearance.generate(hash("%s:%s:%s" % [town.seed, stage, stage_bandits_spawned]))
	actors.append({"slot": slot, "civilian": civilian, "born": elapsed,
		"next_shot": elapsed + reaction, "reaction": reaction, "expires": elapsed + 4.0,
		"flash_until": 0.0, "appearance": appearance})
	return true

func _damage() -> void:
	lives = maxi(0, lives - 1)
	damage_flash = 0.2
	if lives == 0: _end_game()

func _reload() -> void:
	if state == "playing" and magazine and ammo < 6 and reload_left == 0.0:
		reload_left = 0.85
		_sound("reload")

func _sound(key: String) -> void:
	if audio_players.has(key): audio_players[key].play()

func _shoot(point: Vector2, found: bool = true) -> void:
	if state == "transition": return
	if state != "playing":
		if found: _activate_button(point)
		return
	if reload_left > 0.0: return
	if magazine and ammo == 0:
		_notice("Empty! Right click to reload")
		return
	if magazine: ammo -= 1
	_sound("shot")
	muzzle_flash = 0.07
	if not found:
		_notice("Miss: laser point not detected")
		return
	shots.append({"point": point, "ttl": 0.18})
	for index in range(actors.size() - 1, -1, -1):
		var actor: Dictionary = actors[index]
		var position: Vector2 = slots[actor.slot]
		var head := Rect2(position + Vector2(-8, -41), Vector2(16, 17))
		var body := Rect2(position + Vector2(-11, -24), Vector2(22, 24))
		if head.has_point(point) or body.has_point(point):
			actors.remove_at(index)
			if actor.civilian:
				_sound("civilian")
				_sound("dont_shoot")
				_notice("Civilian hit! One life lost")
				_damage()
			else:
				stage_bandits_defeated += 1
				# Give the player a breather even when the normal spawn timer is nearly due.
				spawn_timer = maxf(spawn_timer, BANDIT_RESPAWN_DELAY)
				if burst_timer >= 0.0:
					burst_timer = maxf(burst_timer, BANDIT_RESPAWN_DELAY)
				var bonus := roundi(100.0 * maxf(0.0, 1.0 - (elapsed - float(actor.born)) / float(actor.reaction)))
				var earned := 100 + bonus + (75 if head.has_point(point) else 0)
				score += earned
				if rng.randf() < 0.3: _sound("got_me")
				_notice(("HEADSHOT " if head.has_point(point) else "HIT ") + "+%d" % earned)
				_check_stage_clear()
			return

func _activate_button(point: Vector2) -> void:
	for item in buttons.duplicate():
		var button: Button = item.node
		if is_instance_valid(button) and not button.disabled and button.get_global_rect().has_point(point):
			item.action.call()
			return

func _poll_input() -> void:
	while udp.get_available_packet_count() > 0:
		var data: Variant = JSON.parse_string(udp.get_packet().get_string_from_utf8())
		if not data is Dictionary: continue
		if data.get("type") == "status":
			bridge_last_seen = Time.get_ticks_msec() / 1000.0
			bridge_status = str(data.get("message", "Camera bridge connected"))
		elif data.get("type") == "shot" and input_mode == "Lightgun" and state != "calibration":
			var identifier := str(data.get("id", ""))
			var age := Time.get_unix_time_from_system() - float(data.get("fired_at", 0.0))
			if identifier.is_empty() or identifier in seen_shots or age > 0.8 or age < -1.0: continue
			seen_shots.append(identifier)
			if seen_shots.size() > 128: seen_shots.pop_front()
			if state == "playing" and float(data.get("fired_at", 0.0)) < combat_started_at: continue
			var x := float(data.get("x", -1.0))
			var y := float(data.get("y", -1.0))
			var valid := bool(data.get("found", false)) and x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0
			_shoot(Vector2(x, y) * SIZE, valid)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if state in ["playing", "transition"]: _pause()
			elif state == "paused":
				_resume_game()
			else: _show_menu()
		elif event.keycode == KEY_F11:
			var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_F8:
			var position := get_global_mouse_position() / SIZE
			command_udp.put_packet(JSON.stringify({"type": "simulate", "x": position.x, "y": position.y}).to_utf8_buffer())
	if event is InputEventMouseButton and event.pressed:
		if state == "calibration" and event.button_index == MOUSE_BUTTON_LEFT and PREVIEW.has_point(event.position):
			if calibration_points.size() < 4:
				calibration_points.append((event.position - PREVIEW.position) / PREVIEW.size)
			return
		if input_mode == "Mouse" and event.button_index == MOUSE_BUTTON_LEFT and state == "playing": _shoot(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT: _reload()

func _text(value: String, position: Vector2, size: int = 12, color: Color = Color("f6e6bf")) -> void:
	draw_string(font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center(value: String, y: float, size: int = 18, color: Color = Color("f6e6bf")) -> void:
	_text(value, Vector2((640 - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x) / 2.0, y), size, color)

func _draw() -> void:
	_draw_backdrop()
	var scrolling := state == "transition" or (state == "paused" and paused_state == "transition")
	if scrolling:
		var progress := clampf((transition_elapsed - STAGE_CLEAR_HOLD) / STAGE_SCROLL_DURATION, 0.0, 1.0)
		var distance := SIZE.x * smoothstep(0.0, 1.0, progress)
		_draw_town(town, -distance)
		_draw_town(next_town, SIZE.x - distance)
	else:
		_draw_town(town)
		if state in ["playing", "paused", "gameover"]:
			for actor in actors: _draw_actor(actor)
			_draw_foreground(town)
	if state in ["playing", "transition", "paused", "gameover"]:
		_draw_hud()
	if state == "playing":
		for shot in shots:
			var point: Vector2 = shot.point
			draw_line(point - Vector2(4, 4), point + Vector2(4, 4), Color("ffe8a0"), 2)
			draw_line(point + Vector2(-4, 4), point + Vector2(4, -4), Color("ffe8a0"), 2)
		if input_mode == "Mouse": _draw_crosshair(get_global_mouse_position())
		if muzzle_flash > 0.0: draw_rect(Rect2(0, 340, 640, 20), Color(1.0, 0.85, 0.5, 0.3))
	elif state == "transition":
		draw_rect(Rect2(145, 137, 350, 68), Color(0.07, 0.06, 0.05, 0.90))
		_center("STAGE %d CLEAR" % stage, 165, 25, Color("f2cc7a"))
		_center("MOVING TO STAGE %d" % (stage + 1), 189, 13)
	elif state == "calibration":
		_draw_calibration()
	else:
		draw_rect(Rect2(100, 38, 440, 302), Color(0.06, 0.055, 0.05, 0.93))
		match state:
			"menu":
				_center("GUNSLINGER", 81, 34, Color("f2cc7a"))
				_center("A WESTERN SHOOTOUT", 101, 11)
				_center(bridge_status, 344, 10, Color("cfb78f"))
			"paused":
				_center("PAUSED", 121, 26)
			"gameover":
				_center("TIME'S UP" if lives > 0 else "GAME OVER", 94, 27)
				_center("SCORE  %d" % score, 124, 22, Color("f2cc7a"))
			"scores":
				_center("HIGHSCORES", 78, 25)
				_center(_score_key().replace("/", "  /  "), 101, 10)
				var rows: Array = highscores.get(_score_key(), [])
				if rows.is_empty(): _center("No scores yet. Make your mark!", 183, 14)
				for index in range(rows.size()):
					_text("%2d.  %-8s" % [index + 1, rows[index].name], Vector2(190, 125 + index * 17), 12)
					_text(str(rows[index].score), Vector2(405, 125 + index * 17), 12, Color("f2cc7a"))
	if damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(1.0, 0.6, 0.2, 0.25))
	if message_left > 0.0:
		draw_rect(Rect2(100, 5, 440, 23), Color(0.04, 0.04, 0.04, 0.92))
		_center(message, 21, 12, Color("ffe6a0"))

func _draw_crosshair(point: Vector2) -> void:
	draw_circle(point, 8, Color("fff3ce"), false, 1.0)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(point + direction * 4, point + direction * 12, Color("fff3ce"), 1.0)
	draw_rect(Rect2(point - Vector2.ONE, Vector2(2, 2)), Color("fff3ce"))

func _draw_hud() -> void:
	draw_rect(Rect2(0, 0, 640, 50), Color("241e1b"))
	_text("SCORE  %06d" % score, Vector2(12, 20), 14)
	_text("LIVES  " + "* ".repeat(lives), Vector2(200, 20), 14, Color("f2cc7a"))
	_text("RELOADING..." if reload_left > 0.0 else ("AMMO  %d/6" % ammo if magazine else "AMMO  INF"), Vector2(330, 20), 13)
	_text("%02d:%02d" % [int(maxf(0, 90 - elapsed)) / 60, int(maxf(0, 90 - elapsed)) % 60] if mode == "Timed" else "ENDLESS", Vector2(534, 20), 13)
	_text("STAGE %d    BANDITS %d / %d" % [stage, stage_bandits_defeated, stage_bandits_total], Vector2(12, 43), 11, Color("f2cc7a"))
	_text(str(town.get("name", "")), Vector2(390, 43), 11, Color("cfb78f"))
	_text("ESC pause   F11 fullscreen" + ("   Right click reload" if magazine else ""), Vector2(10, 352), 10, Color("dbc098"))

func _draw_backdrop() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("ddab72"))
	for index in range(12): draw_rect(Rect2(0, index * 10, 640, 10), Color("efc78d").lerp(Color("cb945f"), index / 12.0))
	draw_circle(Vector2(360, 55), 25, Color("f9df9e"))

func _draw_town(layout: Dictionary, offset_x: float = 0.0) -> void:
	if layout.is_empty(): return
	draw_set_transform(Vector2(roundf(offset_x), 0))
	draw_colored_polygon(layout.mountains, Color("9c7859"))
	for building in layout.buildings: _draw_building(building)
	draw_rect(Rect2(0, 254, 640, 106), Color("b28a5d"))
	for mark in layout.dirt: draw_rect(mark, Color("a17b52"))
	draw_rect(Rect2(16, 186, 5, 83), Color("64543c"))
	draw_rect(Rect2(9, 199, 19, 4), Color("64543c"))
	draw_rect(Rect2(606, 151, 5, 109), Color("64543c"))
	draw_rect(Rect2(597, 173, 20, 5), Color("64543c"))
	_draw_foreground(layout)
	draw_set_transform(Vector2.ZERO)

func _draw_building(building: Dictionary) -> void:
	var rect: Rect2 = building.rect
	var title: String = building.title
	var color: Color = building.color
	var door: Vector2 = building.door
	draw_rect(Rect2(rect.position + Vector2(7, 5), rect.size), Color("73583f"))
	draw_rect(rect, color)
	if building.vertical_planks:
		for x in range(int(rect.position.x) + 5, int(rect.end.x), 9):
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), color.darkened(0.12), 1)
	else:
		for y in range(int(rect.position.y) + 4, int(rect.end.y), 8):
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), color.darkened(0.12), 1)
	if building.roof == 1:
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.2, -12), Vector2(rect.size.x * 0.6, 12)), color)
	elif building.roof == 2:
		draw_colored_polygon(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x / 2, -12), rect.position + Vector2(rect.size.x, 0)]), color.lightened(0.12))
	draw_rect(Rect2(rect.position + Vector2(-4, -5), Vector2(rect.size.x + 8, 9)), Color("5e4936"))
	draw_rect(Rect2(rect.position + Vector2(8, 5), Vector2(rect.size.x - 16, 20)), Color("e3c590"))
	var sign_size := 14
	while sign_size > 8 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, sign_size).x > rect.size.x - 22:
		sign_size -= 1
	var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, sign_size).x
	_text(title, Vector2(rect.position.x + (rect.size.x - text_width) / 2, rect.position.y + 20), sign_size, Color("42382b"))
	for position in building.windows:
		draw_rect(Rect2(position + Vector2(-21, -48), Vector2(42, 52)), Color("cfb17e"))
		draw_rect(Rect2(position + Vector2(-17, -44), Vector2(34, 44)), Color("292b28"))
		draw_rect(Rect2(position + Vector2(-25, 1), Vector2(50, 4)), Color("675038"))
	draw_rect(Rect2(door + Vector2(-21, -48), Vector2(42, 78)), Color("524332"))
	draw_rect(Rect2(door + Vector2(-16, -43), Vector2(32, 65)), Color("292b28"))
	if building.awning:
		draw_rect(Rect2(rect.position.x + 3, 179, rect.size.x - 6, 7), color.darkened(0.25))
		draw_rect(Rect2(rect.position.x + 8, 186, 4, 56), Color("675038"))
		draw_rect(Rect2(rect.end.x - 12, 186, 4, 56), Color("675038"))
	draw_rect(Rect2(rect.position.x - 9, rect.end.y - 13, rect.size.x + 18, 12), Color("756043"))

func _draw_foreground(layout: Dictionary) -> void:
	for obstacle in layout.obstacles:
		var position: Vector2 = obstacle.position
		match int(obstacle.kind):
			0:
				draw_rect(Rect2(position + Vector2(-25, 0), Vector2(50, 23)), Color("77583b"))
				draw_rect(Rect2(position + Vector2(-23, 2), Vector2(46, 4)), Color("bd9969"))
				draw_rect(Rect2(position + Vector2(-23, 14), Vector2(46, 3)), Color("bd9969"))
				draw_line(position + Vector2(-18, 21), position + Vector2(18, 4), Color("ab8658"), 3)
			1:
				draw_colored_polygon(PackedVector2Array([position + Vector2(-14, 0), position + Vector2(14, 0), position + Vector2(19, 5), position + Vector2(19, 24), position + Vector2(14, 29), position + Vector2(-14, 29), position + Vector2(-19, 24), position + Vector2(-19, 5)]), Color("927047"))
				for x in [-10, -2, 6]: draw_rect(Rect2(position + Vector2(x, 1), Vector2(2, 27)), Color("735538"))
				for y in [6, 21]: draw_rect(Rect2(position + Vector2(-19, y), Vector2(38, 3)), Color("49483e"))
				draw_rect(Rect2(position + Vector2(-14, 0), Vector2(28, 3)), Color("c0a16d"))
			2:
				draw_rect(Rect2(position + Vector2(-40, 0), Vector2(80, 20)), Color("785d40"))
				for y in [1, 8, 15]: draw_rect(Rect2(position + Vector2(-38, y), Vector2(76, 3)), Color("b09262"))
				for x in [-26, 26]:
					draw_circle(position + Vector2(x, 26), 9, Color("453e31"))
					draw_circle(position + Vector2(x, 26), 4, Color("b09262"))
				draw_line(position + Vector2(40, 12), position + Vector2(53, 4), Color("785d40"), 3)

func _draw_actor(actor: Dictionary) -> void:
	var point: Vector2 = slots[actor.slot]
	var civilian: bool = actor.civilian
	if civilian:
		if not actor.has("appearance") or actor.appearance.is_empty():
			actor.appearance = CivilianAppearance.generate(hash("%s:%s:%s" % [town.seed, actor.slot, actor.born]))
		CivilianAppearance.draw(self, point, actor.appearance)
		_text("SAFE", point + Vector2(-12, -46), 8, Color("a9e6d1"))
	else:
		if not actor.has("appearance") or actor.appearance.is_empty():
			# Cache a stable appearance for legacy/debug actors as well.
			actor.appearance = BanditAppearance.generate(hash("%s:%s:%s" % [town.seed, actor.slot, actor.born]))
		BanditAppearance.draw(self, point, actor.appearance)
		var remaining := clampf((float(actor.next_shot) - elapsed) / float(actor.reaction), 0, 1)
		draw_rect(Rect2(point + Vector2(-13, -47), Vector2(26, 3)), Color("342e2b"))
		draw_rect(Rect2(point + Vector2(-13, -47), Vector2(26 * remaining, 3)), Color("f2cc7a"))
		if elapsed < float(actor.flash_until):
			draw_colored_polygon(PackedVector2Array([point + Vector2(23, -15), point + Vector2(34, -11), point + Vector2(23, -7)]), Color("fff4b9"))

func _draw_calibration() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("19232c"))
	for point in [Vector2(3, 3), Vector2(625, 3), Vector2(625, 345), Vector2(3, 345)]:
		draw_rect(Rect2(point, Vector2(12, 12)), Color("f7f0d0"))
	_center("CAMERA CALIBRATION", 37, 21)
	_text("Camera view", Vector2(18, 65), 12)
	draw_rect(PREVIEW, Color("101419"))
	if camera_texture:
		draw_texture_rect(camera_texture, PREVIEW, false)
	else:
		_text("Waiting for camera...", Vector2(73, 190), 12)
	var points := calibration_points if not calibration_points.is_empty() else saved_points
	for index in range(points.size()):
		var position: Vector2 = PREVIEW.position + points[index] * PREVIEW.size
		draw_circle(position, 4, Color("75ead4"))
		_text(str(index + 1), position + Vector2(6, -5), 12, Color("75ead4"))
		if index > 0: draw_line(PREVIEW.position + points[index - 1] * PREVIEW.size, position, Color("75ead4"), 1)
	if points.size() == 4:
		draw_line(PREVIEW.position + points[3] * PREVIEW.size, PREVIEW.position + points[0] * PREVIEW.size, Color("75ead4"), 1)
	_text("Click the projected image corners", Vector2(361, 82), 12)
	_text("inside the camera view:", Vector2(361, 100), 12)
	var instructions := ["1  TOP LEFT", "2  TOP RIGHT", "3  BOTTOM RIGHT", "4  BOTTOM LEFT"]
	for index in range(4):
		_text(instructions[index], Vector2(371, 129 + index * 22), 13, Color("75ead4") if index < calibration_points.size() else Color("f6e6bf"))
	_text("Saved" if calibration_saved else "Then save calibration.", Vector2(361, 223), 11)
	_text(preview_error if not preview_error.is_empty() else bridge_status, Vector2(18, 336), 10)
