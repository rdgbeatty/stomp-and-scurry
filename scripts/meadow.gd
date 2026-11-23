extends Node2D

const SIZE := Vector2(1152, 720)
const FIELD := Rect2(38, 105, 1076, 525)
const GRASS := [Color("709b50"), Color("82a95c"), Color("92b565"), Color("5a8c49")]
const FLOWERS := [Color("fff3c4"), Color("ffd889"), Color("eac5cd"), Color("e8e9ae")]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("162e25"))
	draw_style_box(_panel(Color("243d2b"), 18), FIELD.grow(10.0))
	draw_style_box(_panel(Color("385138"), 11), FIELD.grow(4.0))
	draw_polygon(PackedVector2Array([
		FIELD.position, Vector2(FIELD.end.x, FIELD.position.y), FIELD.end,
		Vector2(FIELD.position.x, FIELD.end.y),
	]), PackedColorArray([Color("97b862"), Color("79a64f"), Color("649247"), Color("8aaf55")]))
	_draw_lawn_bands()

	var rng := RandomNumberGenerator.new()
	rng.seed = 38429
	for index in 1250:
		var point := _random_point(rng, 7.0)
		var color: Color = GRASS[rng.randi_range(0, GRASS.size() - 1)]
		var length := rng.randf_range(2.0, 9.0)
		draw_line(point, point + Vector2(rng.randf_range(-4.0, 3.0), -length), color, rng.randf_range(0.8, 1.7), true)
	for index in 115:
		var point := _random_point(rng, 12.0)
		_draw_tuft(point, rng.randf_range(0.45, 1.08), GRASS[rng.randi_range(0, 2)])
	for index in 175:
		var point := _random_point(rng, 5.0)
		draw_circle(point, rng.randf_range(0.7, 2.1), Color(0.92, 0.89, 0.56, 0.28), true, -1.0, true)

	# Keep the larger plants around the clearing so they never hide the ant.
	var patches := [
		Vector2(83, 154), Vector2(202, 137), Vector2(370, 139), Vector2(784, 136),
		Vector2(1000, 142), Vector2(1080, 184), Vector2(86, 318), Vector2(1067, 382),
		Vector2(84, 512), Vector2(130, 586), Vector2(252, 600), Vector2(430, 595),
		Vector2(703, 602), Vector2(901, 596), Vector2(1043, 569),
	]
	for point: Vector2 in patches:
		for index in rng.randi_range(2, 5):
			var offset := Vector2(rng.randf_range(-25.0, 25.0), rng.randf_range(-13.0, 16.0))
			_draw_flower(point + offset, rng.randf_range(0.64, 1.12), rng.randi_range(0, 3))
	for point: Vector2 in [Vector2(135, 228), Vector2(1001, 226), Vector2(204, 534), Vector2(965, 511)]:
		_draw_pebble(point, rng.randf_range(0.85, 1.28))
	draw_rect(FIELD, Color(0.23, 0.32, 0.15, 0.46), false, 2.0)


func _draw_lawn_bands() -> void:
	for index in 6:
		var band := PackedVector2Array()
		for column in 28:
			var x := FIELD.position.x + FIELD.size.x * float(column) / 27.0
			var y := FIELD.position.y + index * 81.0 + 35.0 + sin(x * 0.007 + index * 0.5) * 15.0
			band.append(Vector2(x, y))
		for column in range(27, -1, -1):
			var x := FIELD.position.x + FIELD.size.x * float(column) / 27.0
			var y := FIELD.position.y + index * 81.0 + 60.0 + sin(x * 0.007 + index * 0.5) * 16.0
			band.append(Vector2(x, minf(y, FIELD.end.y)))
		draw_colored_polygon(band, Color(0.39, 0.56, 0.24, 0.12))


func _random_point(rng: RandomNumberGenerator, margin: float) -> Vector2:
	return Vector2(rng.randf_range(FIELD.position.x + margin, FIELD.end.x - margin),
		rng.randf_range(FIELD.position.y + margin, FIELD.end.y - margin))


func _draw_tuft(point: Vector2, scale_factor: float, color: Color) -> void:
	draw_set_transform(point, 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4, 0), Vector2(-12, -10), Vector2(-4, -5), Vector2(-5, -18),
		Vector2(1, -7), Vector2(8, -14), Vector2(5, -4), Vector2(11, -6), Vector2(5, 0),
	]), color)
	draw_set_transform(Vector2.ZERO)


func _draw_flower(point: Vector2, scale_factor: float, variant: int) -> void:
	draw_set_transform(point, 0.0, Vector2.ONE * scale_factor)
	draw_line(Vector2(0, 6), Vector2(2, -12), Color("5c843f"), 2.1, true)
	draw_colored_polygon(PackedVector2Array([Vector2(1, 3), Vector2(-9, -3), Vector2(-5, -5), Vector2(2, 0)]), Color("6f9143"))
	draw_colored_polygon(PackedVector2Array([Vector2(1, 0), Vector2(7, -6), Vector2(11, -6), Vector2(7, -1)]), Color("9eb953"))
	for index in 5:
		var petal := Vector2.from_angle(float(index) * TAU / 5.0 + variant) * 4.4
		draw_circle(Vector2(2, -12) + petal, 3.6, FLOWERS[variant], true, -1.0, true)
	draw_circle(Vector2(2, -12), 2.4, Color("db9c47"), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_pebble(point: Vector2, scale_factor: float) -> void:
	draw_set_transform(point, 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(PackedVector2Array([Vector2(-12, 2), Vector2(-8, -6), Vector2(2, -9),
		Vector2(10, -5), Vector2(13, 2), Vector2(2, 6), Vector2(-8, 5)]), Color("678958"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(-6, -6), Vector2(2, -9),
		Vector2(9, -5), Vector2(7, -1), Vector2(-2, 1)]), Color("aec285"))
	draw_set_transform(Vector2.ZERO)


func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
