extends RefCounted

# Generate geometry once per block. Rendering never consumes random numbers.
const BUILDING_NAMES := ["SALOON", "SHERIFF", "BANK", "HOTEL", "GENERAL STORE",
	"BLACKSMITH", "STABLES", "TRADING POST", "POST OFFICE", "BARBER", "DOCTOR", "DRY GOODS"]
const STREET_NAMES := ["DUSTY TRAIL", "COPPER STREET", "CANYON ROAD", "FRONTIER ROW",
	"SILVER AVENUE", "SUNDOWN STREET", "TUMBLEWEED LANE", "PROSPECTOR ROW"]
const WALL_COLORS := [Color("9c7652"), Color("c3a174"), Color("957358"),
	Color("818b7a"), Color("a48a70"), Color("ad976c"), Color("7d9290")]

static func generate(seed_value: int) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var buildings: Array[Dictionary] = []
	var obstacles: Array[Dictionary] = []
	var slots: Array[Vector2] = []
	var names: Array = BUILDING_NAMES.duplicate()
	var count := random.randi_range(3, 4)
	var gap := random.randi_range(12, 20)
	var available_width := 600 - gap * (count - 1)
	var weights: Array[float] = []
	var weight_sum := 0.0
	for index in range(count):
		var weight := random.randf_range(0.95, 1.15)
		weights.append(weight)
		weight_sum += weight
	var x := 20
	for index in range(count):
		var width := int(available_width * weights[index] / weight_sum)
		if index == count - 1: width = 620 - x
		var top := random.randi_range(64, 94)
		var rect := Rect2(x, top, width, 254 - top)
		var windows: Array[Vector2] = []
		var columns := 2 if width >= 125 else 1
		for column in range(columns):
			var point := Vector2(roundf(x + width * (column + 1.0) / (columns + 1.0)), top + 80)
			windows.append(point)
			slots.append(point)
		var door := Vector2(roundf(rect.get_center().x + random.randi_range(-7, 7)), 232)
		slots.append(door)
		buildings.append({"rect": rect, "title": names.pop_at(random.randi_range(0, names.size() - 1)),
			"color": WALL_COLORS[random.randi_range(0, WALL_COLORS.size() - 1)],
			"windows": windows, "door": door, "roof": random.randi_range(0, 2),
			"vertical_planks": random.randf() < 0.3, "awning": random.randf() < 0.5})
		x += width + gap
	var obstacle_count := random.randi_range(2, 4)
	for index in range(obstacle_count):
		var point := Vector2(roundf(640.0 * (index + 1) / (obstacle_count + 1)) + random.randi_range(-18, 18), random.randi_range(292, 304))
		obstacles.append({"position": point, "kind": random.randi_range(0, 2)})
		slots.append(point)
	var mountains := PackedVector2Array([Vector2(0, 142)])
	for index in range(1, 12):
		mountains.append(Vector2(index * 640.0 / 12, random.randi_range(104, 155)))
	mountains.append_array(PackedVector2Array([Vector2(640, 142), Vector2(640, 254), Vector2(0, 254)]))
	var dirt: Array[Rect2] = []
	for index in range(32):
		dirt.append(Rect2(random.randi_range(3, 612), random.randi_range(263, 335), random.randi_range(5, 23), 2))
	return {"seed": seed_value, "name": STREET_NAMES[random.randi_range(0, STREET_NAMES.size() - 1)],
		"buildings": buildings, "obstacles": obstacles, "slots": slots, "mountains": mountains, "dirt": dirt}
