extends "res://scripts/main.gd"

var examples: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	set_process(false)
	_clear_ui()
	slots.assign([Vector2.ZERO])
	for index in range(12):
		var look := BanditAppearance.generate(174 + index * 53)
		# Show the available silhouettes and faces rather than relying on chance
		# to include every style in a small visual review sheet.
		look.hat = index % 6
		look.outfit = index % 4
		look.face = index % 5
		examples.append({"slot": 0, "civilian": false, "appearance": look,
			"born": 0.0, "next_shot": 5.2, "reaction": 5.2, "flash_until": 0.0})

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("241e1b"))
	_center("GUNSLINGER: THE OUTLAWS", 32, 23, Color("f2cc7a"))
	_center("A few combinations from the new bandit wardrobe", 50, 11)
	var outfits := ["DUSTER", "WAISTCOAT", "PONCHO", "SUSPENDERS"]
	for index in range(examples.size()):
		var column := index % 6
		var row := index / 6
		var x := 55 + column * 106
		var y := 150 + row * 138
		draw_rect(Rect2(x - 48, y - 87, 96, 114), Color("41352a"))
		draw_set_transform(Vector2(x, y), 0.0, Vector2(1.8, 1.8))
		_draw_actor(examples[index])
		draw_set_transform(Vector2.ZERO)
		var label: String = outfits[index % 4]
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_text(label, Vector2(x - width / 2, y + 20), 10)
	_center("Civilian colors and SAFE labels remain distinct. All bandits carry revolvers.", 343, 10, Color("cfb78f"))
