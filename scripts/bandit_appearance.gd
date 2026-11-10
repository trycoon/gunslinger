extends RefCounted

const SKIN_COLOR := Color("e0b780")
const CLOTH_COLORS := [Color("67518b"), Color("8f503c"), Color("4f6174"),
	Color("6a7650"), Color("8b7655"), Color("70564c"), Color("604658")]
const HAT_COLORS := [Color("353630"), Color("583d2c"), Color("333d4c"),
	Color("594e41"), Color("484b35")]
const HAIR_COLORS := [Color("292321"), Color("60412c"), Color("a58a62"), Color("c3b49a")]
const ACCENT_COLORS := [Color("a36f47"), Color("747e4e"), Color("92789c"),
	Color("648290"), Color("b49b6b")]

static func generate(seed_value: int) -> Dictionary:
	# A separate seeded generator keeps cosmetic choices out of gameplay's RNG.
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	return {"skin": SKIN_COLOR,
		"cloth": CLOTH_COLORS[random.randi_range(0, CLOTH_COLORS.size() - 1)],
		"hat_color": HAT_COLORS[random.randi_range(0, HAT_COLORS.size() - 1)],
		"hair": HAIR_COLORS[random.randi_range(0, HAIR_COLORS.size() - 1)],
		"accent": ACCENT_COLORS[random.randi_range(0, ACCENT_COLORS.size() - 1)],
		"hat": random.randi_range(0, 5), "outfit": random.randi_range(0, 3),
		"face": random.randi_range(0, 4), "accessory": random.randi_range(0, 4)}

static func draw(canvas: CanvasItem, point: Vector2, look: Dictionary) -> void:
	var cloth: Color = look.cloth
	var accent: Color = look.accent
	var skin := SKIN_COLOR
	var hair: Color = look.hair
	var hat: Color = look.hat_color
	var dark := Color("302b28")
	# All outfits retain the original target's body/head dimensions and gun pose.
	canvas.draw_rect(Rect2(point + Vector2(-10, -24), Vector2(20, 24)), cloth)
	canvas.draw_rect(Rect2(point + Vector2(-14, -23), Vector2(4, 19)), cloth.darkened(0.12))
	canvas.draw_rect(Rect2(point + Vector2(10, -23), Vector2(4, 19)), cloth.darkened(0.12))
	match int(look.outfit):
		0: # Open duster with contrasting lapels and shirt.
			canvas.draw_rect(Rect2(point + Vector2(-3, -24), Vector2(6, 24)), accent)
			canvas.draw_line(point + Vector2(-7, -23), point + Vector2(-3, -11), cloth.lightened(0.25), 2)
			canvas.draw_line(point + Vector2(7, -23), point + Vector2(3, -11), cloth.lightened(0.25), 2)
			canvas.draw_rect(Rect2(point + Vector2(-1, -17), Vector2(2, 2)), dark)
			canvas.draw_rect(Rect2(point + Vector2(-1, -10), Vector2(2, 2)), dark)
		1: # Waistcoat and lighter sleeves.
			canvas.draw_rect(Rect2(point + Vector2(-14, -23), Vector2(4, 15)), accent)
			canvas.draw_rect(Rect2(point + Vector2(10, -23), Vector2(4, 15)), accent)
			canvas.draw_rect(Rect2(point + Vector2(-2, -24), Vector2(4, 18)), accent.lightened(0.2))
			for y in [-18, -12, -6]:
				canvas.draw_rect(Rect2(point + Vector2(2, y), Vector2(2, 2)), Color("c2a673"))
		2: # Striped poncho with a stepped hem.
			canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(-8, -25), point + Vector2(8, -25), point + Vector2(14, -17), point + Vector2(12, -3), point + Vector2(0, 0), point + Vector2(-12, -3), point + Vector2(-14, -17)]), cloth)
			for y in [-18, -10]:
				canvas.draw_rect(Rect2(point + Vector2(-12, y), Vector2(24, 3)), accent)
			canvas.draw_rect(Rect2(point + Vector2(-10, -4), Vector2(20, 2)), cloth.lightened(0.25))
		3: # Work shirt and leather suspenders.
			for x in [-6, 4]:
				canvas.draw_rect(Rect2(point + Vector2(x, -24), Vector2(3, 22)), dark)
				canvas.draw_rect(Rect2(point + Vector2(x, -10), Vector2(3, 2)), Color("b6a378"))
	canvas.draw_rect(Rect2(point + Vector2(-10, -4), Vector2(20, 3)), dark)
	canvas.draw_rect(Rect2(point + Vector2(-2, -4), Vector2(4, 3)), Color("c2a673"))
	match int(look.accessory):
		0: # Bandolier.
			canvas.draw_line(point + Vector2(-8, -24), point + Vector2(8, -3), Color("493a2b"), 4)
			for index in range(4):
				canvas.draw_rect(Rect2(point + Vector2(-7 + index * 4, -22 + index * 5), Vector2(3, 3)), Color("bca26b"))
		1: # Neck scarf.
			canvas.draw_rect(Rect2(point + Vector2(-5, -24), Vector2(10, 4)), accent)
			canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(-2, -21), point + Vector2(4, -21), point + Vector2(1, -12)]), accent)
		2: # Pocket and kerchief.
			canvas.draw_rect(Rect2(point + Vector2(-8, -15), Vector2(5, 5)), cloth.darkened(0.25))
			canvas.draw_rect(Rect2(point + Vector2(-7, -17), Vector2(3, 3)), Color("c8bca1"))
		3: # Rolled sleeves and visible wrists.
			for x in [-14, 10]:
				canvas.draw_rect(Rect2(point + Vector2(x, -11), Vector2(4, 3)), accent)
				canvas.draw_rect(Rect2(point + Vector2(x, -8), Vector2(4, 4)), skin)
		4: # Cartridge belt.
			for x in [-8, -4, 4, 8]:
				canvas.draw_rect(Rect2(point + Vector2(x, -6), Vector2(2, 4)), Color("bca26b"))
	canvas.draw_rect(Rect2(point + Vector2(-6, -35), Vector2(12, 13)), skin)
	canvas.draw_rect(Rect2(point + Vector2(-6, -34), Vector2(1, 8)), skin.lightened(0.25))
	canvas.draw_rect(Rect2(point + Vector2(5, -33), Vector2(1, 9)), skin.darkened(0.2))
	canvas.draw_rect(Rect2(point + Vector2(-6, -35), Vector2(2, 7)), hair)
	canvas.draw_rect(Rect2(point + Vector2(4, -35), Vector2(2, 7)), hair)
	for x in [-4, 3]:
		canvas.draw_rect(Rect2(point + Vector2(x, -31), Vector2(2, 2)), Color("e9dfc8"))
		canvas.draw_rect(Rect2(point + Vector2(x + 1, -31), Vector2(1, 2)), dark)
	canvas.draw_rect(Rect2(point + Vector2(0, -29), Vector2(2, 3)), skin.darkened(0.22))
	match int(look.face):
		0: # Bandana mask.
			canvas.draw_rect(Rect2(point + Vector2(-6, -28), Vector2(12, 5)), accent.darkened(0.25))
			canvas.draw_rect(Rect2(point + Vector2(-3, -23), Vector2(6, 2)), accent.darkened(0.25))
		1: # Moustache.
			canvas.draw_rect(Rect2(point + Vector2(-4, -26), Vector2(8, 2)), hair)
			canvas.draw_rect(Rect2(point + Vector2(-5, -25), Vector2(2, 2)), hair)
			canvas.draw_rect(Rect2(point + Vector2(3, -25), Vector2(2, 2)), hair)
		2: # Full beard.
			canvas.draw_rect(Rect2(point + Vector2(-6, -27), Vector2(12, 5)), hair)
			canvas.draw_rect(Rect2(point + Vector2(-3, -22), Vector2(6, 2)), hair)
			canvas.draw_rect(Rect2(point + Vector2(-2, -27), Vector2(4, 2)), skin)
		3: # Eye patch and stubble.
			canvas.draw_line(point + Vector2(-6, -33), point + Vector2(-1, -29), dark, 1)
			canvas.draw_rect(Rect2(point + Vector2(-5, -32), Vector2(4, 4)), dark)
			for x in [-4, 0, 4]: canvas.draw_rect(Rect2(point + Vector2(x, -24), Vector2(1, 1)), hair)
		4: # Clean-shaven with heavy brows.
			for x in [-5, 2]: canvas.draw_rect(Rect2(point + Vector2(x, -33), Vector2(4, 1)), hair)
			canvas.draw_rect(Rect2(point + Vector2(-2, -24), Vector2(4, 1)), skin.darkened(0.4))
	match int(look.hat):
		0:
			canvas.draw_rect(Rect2(point + Vector2(-7, -40), Vector2(14, 7)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-12, -35), Vector2(24, 3)), hat)
		1: # Tall crown.
			canvas.draw_rect(Rect2(point + Vector2(-6, -41), Vector2(12, 8)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-6, -36), Vector2(12, 2)), accent)
			canvas.draw_rect(Rect2(point + Vector2(-10, -34), Vector2(20, 2)), hat)
		2: # Bowler.
			canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(-5, -40), point + Vector2(5, -40), point + Vector2(7, -38), point + Vector2(7, -33), point + Vector2(-7, -33), point + Vector2(-7, -38)]), hat)
			canvas.draw_rect(Rect2(point + Vector2(-10, -34), Vector2(20, 2)), hat)
		3: # Battered, angled brim.
			canvas.draw_rect(Rect2(point + Vector2(-7, -39), Vector2(14, 6)), hat)
			canvas.draw_rect(Rect2(point + Vector2(3, -40), Vector2(3, 2)), hat)
			canvas.draw_line(point + Vector2(-12, -33), point + Vector2(12, -35), hat, 3)
		4: # Tied headband instead of a hat.
			canvas.draw_rect(Rect2(point + Vector2(-6, -38), Vector2(12, 4)), hair)
			canvas.draw_rect(Rect2(point + Vector2(-6, -35), Vector2(12, 3)), accent)
			canvas.draw_rect(Rect2(point + Vector2(-10, -34), Vector2(4, 3)), accent)
		5: # Broad flat hat.
			canvas.draw_rect(Rect2(point + Vector2(-8, -39), Vector2(16, 6)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-8, -36), Vector2(16, 2)), accent)
			canvas.draw_rect(Rect2(point + Vector2(-14, -34), Vector2(28, 2)), hat)
	# The revolver remains the shared visual signal that this is a hostile target.
	canvas.draw_rect(Rect2(point + Vector2(9, -13), Vector2(14, 4)), Color("282a2b"))
	canvas.draw_rect(Rect2(point + Vector2(10, -10), Vector2(4, 6)), Color("282a2b"))
	canvas.draw_rect(Rect2(point + Vector2(12, -13), Vector2(10, 1)), Color("8c9189"))
