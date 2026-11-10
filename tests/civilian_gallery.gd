extends "res://scripts/main.gd"

var examples: Array[Dictionary] = []

func _ready() -> void:
	super._ready()
	set_process(false)
	_clear_ui()
	slots.assign([Vector2.ZERO])
	for index in range(4):
		examples.append({"slot": 0, "civilian": true, "born": 0.0,
			"appearance": {"variant": index}})

func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("241e1b"))
	_center("GUNSLINGER: THE TOWNSFOLK", 33, 22, Color("f2cc7a"))
	_center("Four civilian designs: two men and two women", 54, 12)
	var labels := ["RANCHER", "MERCHANT", "BONNET & APRON", "STRAW HAT & BRAID"]
	for index in range(4):
		var x := 92 + index * 152
		draw_rect(Rect2(x - 69, 76, 138, 215), Color("41352a"))
		draw_set_transform(Vector2(x, 232), 0.0, Vector2(3, 3))
		_draw_actor(examples[index])
		draw_set_transform(Vector2.ZERO)
		var label: String = labels[index]
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_text(label, Vector2(x - width / 2, 271), 10)
	_center("All characters use one skin tone. Civilians remain unarmed and marked SAFE.", 334, 11, Color("cfb78f"))
