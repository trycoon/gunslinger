extends RefCounted

const SKIN_COLOR := Color("e0b780")
const SHIRTS := [Color("75b7ba"), Color("8daebc"), Color("80b6a2"), Color("7aa8bc")]
const HAIR := [Color("60412c"), Color("aaa69a"), Color("60412c"), Color("a18458")]

static func generate(seed_value: int) -> Dictionary:
	return {"variant": posmod(seed_value, 4)}

static func draw(canvas: CanvasItem, point: Vector2, look: Dictionary) -> void:
	var variant := clampi(int(look.get("variant", 0)), 0, 3)
	var cloth: Color = SHIRTS[variant]
	var hair: Color = HAIR[variant]
	var cream := Color("e7dbb7")
	var hat := Color("efd5a2")
	var dark := Color("394647")
	# Two men (rancher, merchant) and two women (bonnet/apron, hat/braid).
	# The silhouette stays within the existing civilian body and head footprint.
	canvas.draw_rect(Rect2(point + Vector2(-10, -24), Vector2(20, 24)), cloth)
	canvas.draw_rect(Rect2(point + Vector2(-14, -23), Vector2(4, 19)), cloth.darkened(0.1))
	canvas.draw_rect(Rect2(point + Vector2(10, -23), Vector2(4, 19)), cloth.darkened(0.1))
	if variant >= 2:
		canvas.draw_colored_polygon(PackedVector2Array([point + Vector2(-7, -24), point + Vector2(7, -24), point + Vector2(6, -14), point + Vector2(11, 0), point + Vector2(-11, 0), point + Vector2(-6, -14)]), cloth)
		canvas.draw_rect(Rect2(point + Vector2(-8, -36), Vector2(16, 17)), hair)
	match variant:
		0: # Rancher: pale cowboy hat and suspenders.
			canvas.draw_rect(Rect2(point + Vector2(-2, -23), Vector2(4, 19)), cream)
			for x in [-7, 5]:
				canvas.draw_rect(Rect2(point + Vector2(x, -24), Vector2(2, 23)), cloth.darkened(0.35))
		1: # Merchant: waistcoat, bow tie and spectacles.
			canvas.draw_rect(Rect2(point + Vector2(-7, -24), Vector2(14, 24)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-4, -23), Vector2(8, 3)), dark)
			for y in [-16, -10, -4]:
				canvas.draw_rect(Rect2(point + Vector2(-1, y), Vector2(2, 2)), dark)
		2: # Woman in a bonnet and apron over a mint dress.
			canvas.draw_rect(Rect2(point + Vector2(-3, -21), Vector2(6, 8)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-8, -15), Vector2(16, 2)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-5, -13), Vector2(10, 12)), cream)
		3: # Woman with a straw hat, braid and blue dress.
			canvas.draw_rect(Rect2(point + Vector2(-2, -24), Vector2(4, 22)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-8, -13), Vector2(16, 2)), cream)
			canvas.draw_line(point + Vector2(-6, -10), point + Vector2(-8, -1), cloth.darkened(0.2), 1)
			canvas.draw_line(point + Vector2(6, -10), point + Vector2(8, -1), cloth.darkened(0.2), 1)
	# Empty hands remain visibly unarmed on every variant.
	for x in [-14, 10]:
		canvas.draw_rect(Rect2(point + Vector2(x, -7), Vector2(4, 3)), SKIN_COLOR)
	canvas.draw_rect(Rect2(point + Vector2(-6, -35), Vector2(12, 13)), SKIN_COLOR)
	canvas.draw_rect(Rect2(point + Vector2(-6, -35), Vector2(2, 7)), hair)
	canvas.draw_rect(Rect2(point + Vector2(4, -35), Vector2(2, 7)), hair)
	for x in [-4, 3]:
		canvas.draw_rect(Rect2(point + Vector2(x, -31), Vector2(2, 2)), Color("312d29"))
	canvas.draw_rect(Rect2(point + Vector2(-1, -25), Vector2(3, 1)), SKIN_COLOR.darkened(0.3))
	match variant:
		0:
			canvas.draw_rect(Rect2(point + Vector2(-7, -40), Vector2(14, 7)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-12, -35), Vector2(24, 3)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-4, -27), Vector2(8, 2)), hair)
		1:
			canvas.draw_rect(Rect2(point + Vector2(-6, -39), Vector2(12, 5)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-5, -35), Vector2(15, 2)), hat)
			for x in [-5, 2]:
				canvas.draw_rect(Rect2(point + Vector2(x, -32), Vector2(4, 4)), dark, false, 1)
			canvas.draw_line(point + Vector2(-1, -31), point + Vector2(2, -31), dark, 1)
		2:
			canvas.draw_rect(Rect2(point + Vector2(-6, -40), Vector2(12, 4)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-8, -37), Vector2(3, 11)), cream)
			canvas.draw_rect(Rect2(point + Vector2(5, -37), Vector2(3, 11)), cream)
			canvas.draw_rect(Rect2(point + Vector2(-10, -33), Vector2(3, 4)), cloth.lightened(0.15))
			canvas.draw_rect(Rect2(point + Vector2(-4, -23), Vector2(8, 2)), cream)
		3:
			canvas.draw_rect(Rect2(point + Vector2(-7, -39), Vector2(14, 5)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-11, -35), Vector2(22, 2)), hat)
			canvas.draw_rect(Rect2(point + Vector2(-6, -36), Vector2(12, 2)), cloth)
			for y in [-27, -23, -19]:
				canvas.draw_rect(Rect2(point + Vector2(6, y), Vector2(3, 4)), hair)
				canvas.draw_rect(Rect2(point + Vector2(6, y), Vector2(1, 2)), hair.lightened(0.2))
			canvas.draw_rect(Rect2(point + Vector2(6, -15), Vector2(3, 2)), cream)
