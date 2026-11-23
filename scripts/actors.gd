extends Node2D

const Game = preload("res://scripts/game.gd")
const INK := Color("342729")
const PLAYER_COLORS := [Color("f9c77f"), Color("a9deff"), Color("f1b4d8"), Color("e4f3a6")]
const CREAM := Color("ffefba")
const SPEED_COLOR := Color("ffe28a")
const SHIELD_COLOR := Color("aeeefb")
const QUICK_COLOR := Color("ffae82")
const WIDE_COLOR := Color("e5c6ff")
const DENIAL_COLOR := Color("d8f495")
const WIND_COLOR := Color("c4f5e8")
const SLIME_COLOR := Color("86ecde")
const SPIDER_INK := Color("302737")

@onready var _game: Game = get_parent().get_parent()
var _sole := PackedVector2Array(Game.SOLE)


func _draw() -> void:
	if _game.mode == Game.Mode.TITLE:
		_draw_title_scene()
		return
	if _game.lan.role != Game.Lan.Role.SOLO:
		_draw_party()
		return

	if _game.loss == Game.Loss.SPIDER:
		var bite_age := Game.LOSS_DELAY - _game.lost_delay
		var bite := sin(clampf(bite_age / 0.28, 0.0, 1.0) * PI)
		var lunge := Vector2.from_angle(_game.spider_angle) * (bite * 12.0)
		var index := _game.spider_biter
		var at := _game.spider_position
		var angle := _game.spider_angle
		if index >= 0 and index < _game.rush_spiders.size():
			at = _game.rush_spiders[index]
			angle = _game.rush_angles[index]
			lunge = Vector2.from_angle(angle) * (bite * 12.0)
		_draw_spider(at + lunge, angle, _game.spider_gait, bite)
		return

	if _game.step == Game.Step.WARNING and _game.loss != Game.Loss.METEOR:
		var progress := 1.0 - _game.remaining / _game.warning_duration
		var accent := DENIAL_COLOR if _game.stomp_power == Game.ShoePower.DENIAL else CREAM
		_draw_shadow(_game.shadow_position, _game.shoe_angle, progress, _game.stomp_scale, accent)
	if _game.loss != Game.Loss.METEOR:
		_draw_stomp()
	if _game.snail_active:
		_draw_snail_event()
	_draw_yard_event()

	if _game.impact_age < 0.46:
		_draw_impact(_game.shadow_position, _game.impact_age / 0.46)
	_draw_spider(_game.spider_position, _game.spider_angle, _game.spider_gait)
	if _game.power != Game.Power.NONE:
		_draw_power()
	if _game.shoe_pickup != Game.ShoePower.NONE:
		_draw_shoe_pickup()
	var squashed := _game.loss == Game.Loss.SHOE or _game.loss == Game.Loss.METEOR
	if _game.loss != Game.Loss.SHOE or _game.impact_age > 0.56:
		_draw_active_power()
		var body_scale := Vector2(1.15, 0.42) if squashed else Vector2.ONE
		var draw_position := _game.ant_position
		if _game.jump_time > 0.0:
			var height := sin(PI * _game.jump_time / Game.JUMP_DURATION) * 37.0
			_ellipse(self, draw_position, Vector2(24, 13), Color(0.14, 0.20, 0.12, 0.43))
			draw_position.y -= height
			body_scale *= 1.0 + height * 0.005
		draw_ant(self, draw_position, _game.ant_angle, body_scale, _game.gait, _game.clock, squashed)


func _draw_party() -> void:
	var own_id := _game.lan.local_id()
	for shoe: Game.Party.Shoe in _game.party.shoes.values():
		if shoe.terrain_time > 0.0:
			_draw_denial_terrain(shoe.terrain_at, shoe.terrain_scale, shoe.terrain_time)
	for shoe: Game.Party.Shoe in _game.party.shoes.values():
		var color: Color = PLAYER_COLORS[_game.lan.slot(shoe.id) - 1]
		if shoe.step == Game.Step.WARNING:
			var progress := 1.0 - shoe.remaining / shoe.warning
			var glow := DENIAL_COLOR if shoe.power == Game.ShoePower.DENIAL else color
			_draw_shadow(shoe.at, 0.0, progress, shoe.scale_factor, glow)
			if progress > 0.78:
				var drop := pow(1.0 - (progress - 0.78) / 0.22, 1.5)
				_draw_shoe(shoe.at - Vector2(0, 410 * drop), 0.0, 1.0 + 0.36 * drop, shoe.scale_factor)
			draw_string(ThemeDB.fallback_font, shoe.at + Vector2(-15, 25 + 13 * _game.lan.slot(shoe.id)),
				"P%d" % _game.lan.slot(shoe.id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		elif shoe.step == Game.Step.LANDED:
			var lift := clampf(1.0 - shoe.remaining / 0.25, 0.0, 1.0)
			_draw_shoe(shoe.at - Vector2(0, 390 * lift * lift), 0.0, 1.0 + lift * 0.32, shoe.scale_factor)
			if shoe.impact < 0.46:
				_draw_impact(shoe.at, shoe.impact / 0.46)
		if own_id == shoe.id and _game.mode == Game.Mode.RUNNING and _game.party.ready_to_stomp(shoe):
			var aim := get_global_mouse_position()
			if Game.FIELD.has_point(aim) and not (_game._over_shoe_pickup(aim) and shoe.charge == Game.ShoePower.NONE):
				draw_set_transform(aim, 0.0, Vector2.ONE * _game.party.aiming_scale(shoe))
				_outline(self, _sole, color, 1.7)
				draw_set_transform(Vector2.ZERO)
	if _game.snail_active:
		_draw_snail_event()
	_draw_yard_event()
	_draw_spider(_game.spider_position, _game.spider_angle, _game.spider_gait)
	if _game.power != Game.Power.NONE:
		_draw_power()
	if _game.shoe_pickup != Game.ShoePower.NONE:
		_draw_shoe_pickup()
	for ant: Game.Party.Runner in _game.party.runners.values():
		_draw_runner(ant, own_id == ant.id)


func _draw_runner(ant: Game.Party.Runner, is_local: bool) -> void:
	var at := ant.at
	var size := Vector2.ONE
	if ant.jump > 0.0:
		var height := sin(PI * ant.jump / Game.JUMP_DURATION) * 37.0
		_ellipse(self, at, Vector2(24, 13), Color(0.14, 0.20, 0.12, 0.43))
		at.y -= height
		size *= 1.0 + height * 0.005
	elif ant.rise > 0.0:
		size.y = lerpf(1.0, 0.5, ant.rise / Game.Party.RISE_TIME)
	if ant.shield > 0.0 or ant.grace > 0.0:
		draw_circle(at, 32.0, SHIELD_COLOR, false, 2.5, true)
	if ant.boost > 0.0:
		var behind := Vector2.from_angle(ant.angle) * -1.0
		draw_line(at + behind * 35.0, at + behind * 47.0, SPEED_COLOR, 2.5, true)
	var tint: Color = PLAYER_COLORS[_game.lan.slot(ant.id) - 1]
	if is_local:
		draw_circle(at, 28.0, tint, false, 1.9, true)
	draw_ant(self, at, ant.angle, size, ant.gait, _game.clock, false, ant.zombie)
	var caption := "YOU" if is_local else "P%d" % _game.lan.slot(ant.id)
	draw_string(ThemeDB.fallback_font, at + Vector2(-15, 42), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tint)


func _draw_yard_event() -> void:
	if _game.yard_event == Game.YardEvent.SPIDER_RUSH and _game.event_age >= Game.RUSH_WARNING:
		for index in _game.rush_spiders.size():
			_draw_spider(_game.rush_spiders[index], _game.rush_angles[index], _game.event_age * 18.0 + index * PI)
	elif _game.yard_event == Game.YardEvent.WIND_GUST:
		_draw_wind()
	elif _game.yard_event == Game.YardEvent.METEORS:
		for index in range(maxi(0, _game.meteors_landed - 2), _game.meteor_targets.size()):
			var until_impact := Game.meteor_impact_time(index) - _game.event_age
			var at := _game.meteor_targets[index]
			if index < _game.meteors_landed:
				var age := maxf(0.0, -until_impact)
				if _game.mode == Game.Mode.LOST:
					age += Game.LOSS_DELAY - _game.lost_delay
				if age < 0.48:
					var fade := 1.0 - age / 0.48
					draw_circle(at, Game.METEOR_RADIUS, Color(0.47, 0.19, 0.08, 0.52 * fade), true, -1.0, true)
					draw_circle(at, Game.METEOR_RADIUS + age * 95.0, Color(1, 0.70, 0.34, fade), false, 3.0, true)
				continue
			if _game.mode != Game.Mode.RUNNING and _game.mode != Game.Mode.PAUSED:
				return
			if until_impact > Game.METEOR_WARNING + Game.METEOR_SPACING * 0.5:
				return
			var urgency := 1.0 - clampf(until_impact / Game.METEOR_WARNING, 0.0, 1.0)
			draw_circle(at, Game.METEOR_RADIUS, Color(0.32, 0.11, 0.09, 0.42), true, -1.0, true)
			draw_circle(at, Game.METEOR_RADIUS, Color(1, 0.57, 0.27, 0.6 + urgency * 0.4), false, 3.0, true)
			draw_circle(at, Game.METEOR_RADIUS * maxf(0.12, urgency), Color(1, 0.82, 0.52, 0.73), false, 1.6, true)
			if until_impact < 0.32:
				var height := maxf(0.0, until_impact / 0.32)
				var head := at - Vector2(100, 300) * height
				draw_line(head - Vector2(16, 44), head, Color("ff8f59"), 7.0, true)
				draw_circle(head, 11.0, Color("ffcf7f"), true, -1.0, true)
				draw_circle(head, 6.0, Color("734138"), true, -1.0, true)


func _draw_snail_event() -> void:
	var trail := _game.snail_trail
	if not trail.is_empty():
		var wet_edge := Color(0.14, 0.35, 0.33, 0.76)
		var wet_center := Color(0.35, 0.76, 0.67, 0.76)
		var radius := Game.SLIME_WIDTH * 0.5
		draw_circle(trail[0], radius, wet_edge, true, -1.0, true)
		if trail.size() >= 2:
			draw_polyline(trail, wet_edge, Game.SLIME_WIDTH, true)
			draw_circle(trail[-1], radius, wet_edge, true, -1.0, true)
			draw_polyline(trail, wet_center, Game.SLIME_WIDTH * 0.67, true)
		for index in range(0, trail.size(), 3):
			var glint := trail[index] + Vector2(-5, -7 + (index % 4) * 4)
			draw_line(glint, glint + Vector2(8, -1), Color(0.75, 1.0, 0.93, 0.7), 2.2, true)
	var elapsed := _game.snail_age - Game.SNAIL_WARNING
	if elapsed >= 0.0 and elapsed < Game.SNAIL_DURATION:
		_draw_snail(_game.snail_position_at(elapsed), _game.snail_direction, _game.clock)


func _draw_snail(at: Vector2, direction: float, time: float) -> void:
	var beat := time * 10.8
	var stretch := sin(beat)
	var shell_bob := cos(beat) * 2.1
	var head := Vector2(24.0 + stretch * 4.5, -2.0 - shell_bob)
	draw_set_transform(at + Vector2(3, 5), 0.0, Vector2(direction, 1.0))
	_ellipse(self, Vector2(-2, 8), Vector2(38, 17), Color(0.16, 0.13, 0.18, 0.33))
	draw_set_transform(at, 0.0, Vector2(direction, 1.0))

	var foot := PackedVector2Array([
		Vector2(-36.0 - stretch * 4.0, 7), Vector2(-32, 0), Vector2(-21, -3),
		Vector2(-7, -1), Vector2(6, -4), head + Vector2(8, -7), head + Vector2(13, 1),
		head + Vector2(10, 10), Vector2(21, 16), Vector2(7, 19), Vector2(-14, 17), Vector2(-31, 13),
	])
	draw_colored_polygon(foot, Color("596957"))
	_outline(self, foot, SPIDER_INK, 4.2)
	var crest := PackedVector2Array()
	for index in 10:
		var x := -29.0 + index * 6.0
		var y := 8.0 + sin(beat - index * 0.6) * 2.4
		crest.append(Vector2(x, y))
	draw_polyline(crest, Color("9ca982"), 3.0, true)
	_ellipse(self, head, Vector2(14, 12), SPIDER_INK)
	_ellipse(self, head + Vector2(-1, -2), Vector2(11, 9), Color("7c9070"))
	draw_line(head + Vector2(7, 4), head + Vector2(10, 3), Color("3e4b40"), 1.9, true)

	var blink := smoothstep(0.92, 1.0, cos(time * 2.15))
	for index in 2:
		var root := head + Vector2(1.0 + index * 7.0, -6.0)
		var sway := sin(beat * 0.7 + index * 1.3) * 4.0
		var tip := head + Vector2(1.0 + index * 12.0 + sway, -29.0 + index * 5.0 + cos(beat + index) * 2.4)
		var stalk := PackedVector2Array([root, root.lerp(tip, 0.57) + Vector2(-3, 0), tip])
		draw_polyline(stalk, SPIDER_INK, 5.0, true)
		draw_polyline(stalk, Color("a3ac84"), 2.1, true)
		_ellipse(self, tip, Vector2(5.7, 5.3), SPIDER_INK)
		_ellipse(self, tip + Vector2(0.8, 0), Vector2(3.7, lerpf(3.7, 0.9, blink)), Color("ffe2b4"))
		if blink < 0.65:
			draw_circle(tip + Vector2(2, 0), 1.65, SPIDER_INK, true, -1.0, true)

	var shell := Vector2(-11.0 - stretch * 2.4, -10.0 + shell_bob)
	_ellipse(self, shell, Vector2(25, 22), SPIDER_INK)
	_ellipse(self, shell + Vector2(0, 1), Vector2(21, 18), Color("624555"))
	_ellipse(self, shell + Vector2(-2, -3), Vector2(18, 15), Color("94615d"))
	_arc(self, shell, Vector2(19.0, 17.0), 3.48, 5.20, Color("d7a788"), 2.6)
	_arc(self, shell + Vector2(1, 2), Vector2(19.0, 15.0), 0.18, 1.94, Color("50394b"), 2.7)
	var spiral := PackedVector2Array()
	for index in 29:
		var progress := float(index) / 28.0
		var angle := progress * TAU * 1.58 + stretch * 0.10
		spiral.append(shell + Vector2(-2, -1) + Vector2.from_angle(angle) * (1.4 + progress * 14.3))
	draw_polyline(spiral, Color("4b3547"), 3.3, true)
	draw_line(shell + Vector2(-13, -7), shell + Vector2(-9, -11), Color("e0a986"), 2.2, true)
	draw_set_transform(Vector2.ZERO)


func _draw_wind() -> void:
	var age := _game.event_age
	var direction := _game.wind_direction
	var fade := minf(1.0, (Game.WIND_WARNING + Game.WIND_DURATION - age) * 2.0)
	var active := age >= Game.WIND_WARNING
	var color := Color(WIND_COLOR, fade * (0.63 if active else 0.31))
	for index in 10:
		var offset := fposmod(age * (190.0 + (index % 4) * 43.0) + index * 109.0, Game.FIELD.size.x + 100.0)
		var x := Game.FIELD.get_center().x + direction * (offset - (Game.FIELD.size.x + 100.0) * 0.5)
		var y := Game.FIELD.position.y + 37.0 + index * 49.0 + sin(age * 3.0 + index) * 9.0
		var end := Vector2(x, y)
		var length := 29.0 + (index % 3) * 10.0
		draw_line(end - Vector2(direction * length, -3.0), end, color, 2.3, true)
		draw_line(end - Vector2(direction * (length + 12.0), -4.0),
			end - Vector2(direction * (length + 6.0), -3.4), color, 1.5, true)


func _draw_power() -> void:
	var at := _game.power_position
	var floating := at + Vector2(0.0, sin(_game.clock * 4.0) * 3.0)
	var is_speed := _game.power == Game.Power.SPEED
	var accent := SPEED_COLOR if is_speed else SHIELD_COLOR
	draw_circle(at + Vector2(0, 5), 22.0, Color(0.13, 0.18, 0.13, 0.42), true, -1.0, true)
	draw_circle(floating, 21.0, Color("283c34"), true, -1.0, true)
	draw_circle(floating, 19.0, accent, false, 2.5, true)
	draw_set_transform(floating)
	if is_speed:
		draw_colored_polygon(PackedVector2Array([
			Vector2(1, -14), Vector2(-10, 2), Vector2(-1, 2),
			Vector2(-4, 14), Vector2(11, -4), Vector2(2, -4),
		]), accent)
	else:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, -12), Vector2(10, -8), Vector2(8, 4),
			Vector2(0, 12), Vector2(-8, 4), Vector2(-10, -8),
		]), accent)
		draw_polyline(PackedVector2Array([Vector2(-4, -1), Vector2(-1, 3), Vector2(5, -4)]),
			Color("26474e"), 2.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_shoe_pickup() -> void:
	var at := _game.shoe_pickup_position
	var point := at + Vector2(0.0, sin(_game.clock * 4.0) * 3.0)
	var kind := _game.shoe_pickup
	var accent := shoe_power_color(kind)
	draw_circle(at + Vector2(0, 6), 24.0, Color(0.13, 0.18, 0.13, 0.42), true, -1.0, true)
	draw_set_transform(point)
	var diamond := PackedVector2Array([Vector2(0, -26), Vector2(26, 0), Vector2(0, 26), Vector2(-26, 0)])
	draw_colored_polygon(diamond, Color("392b3c"))
	_outline(self, diamond, accent, 2.6)
	match kind:
		Game.ShoePower.QUICK:
			draw_circle(Vector2.ZERO, 11.0, accent, false, 2.4, true)
			draw_polyline(PackedVector2Array([Vector2(0, -7), Vector2.ZERO, Vector2(5, 3)]), accent, 2.5, true)
		Game.ShoePower.WIDE:
			draw_line(Vector2(-12, 0), Vector2(12, 0), accent, 2.5, true)
			for side in [-1.0, 1.0]:
				draw_polyline(PackedVector2Array([Vector2(side * 6, -6), Vector2(side * 13, 0),
					Vector2(side * 6, 6)]), accent, 2.5, true)
		Game.ShoePower.DENIAL:
			_draw_barrier_icon(accent)
	draw_set_transform(Vector2.ZERO)


static func shoe_power_color(kind: Game.ShoePower) -> Color:
	match kind:
		Game.ShoePower.QUICK:
			return QUICK_COLOR
		Game.ShoePower.WIDE:
			return WIDE_COLOR
		_:
			return DENIAL_COLOR


func _draw_barrier_icon(accent: Color) -> void:
	draw_circle(Vector2.ZERO, 11.0, accent, false, 2.4, true)
	draw_line(Vector2(-8, 8), Vector2(8, -8), accent, 2.6, true)


func _draw_denial_terrain(at: Vector2, scale_factor: float, remaining: float) -> void:
	var fade := clampf(remaining / 0.9, 0.0, 1.0)
	draw_set_transform(at, 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(_sole, Color(0.16, 0.22, 0.14, 0.82 * fade))
	for index in 7:
		var y := -77.0 + index * 24.0
		draw_line(Vector2(-24, y + 14), Vector2(24, y - 14), Color(0.65, 0.78, 0.42, 0.33 * fade), 5.0, true)
	var accent := Color(DENIAL_COLOR, fade)
	_outline(self, _sole, accent, 3.4)
	_draw_barrier_icon(accent)
	draw_set_transform(Vector2.ZERO)


func _draw_active_power() -> void:
	if _game.boost_time > 0.0:
		var behind := Vector2.from_angle(_game.ant_angle) * -1.0
		for index in 3:
			var start := _game.ant_position + behind * (30.0 + index * 8.0) + behind.orthogonal() * (index - 1) * 8.0
			draw_line(start, start + behind * 11.0, SPEED_COLOR, 2.5, true)
	if _game.shield_time > 0.0 or _game.shield_grace > 0.0:
		var radius := 34.0
		var tint := SHIELD_COLOR
		if _game.shield_time <= 0.0:
			radius += (1.0 - _game.shield_grace / Game.SHIELD_GRACE) * 17.0
			tint.a = _game.shield_grace / Game.SHIELD_GRACE
		draw_circle(_game.ant_position, radius, Color(tint, tint.a * 0.14), true, -1.0, true)
		draw_circle(_game.ant_position, radius, tint, false, 2.5, true)


func _draw_stomp() -> void:
	if _game.step == Game.Step.WARNING:
		var progress := 1.0 - _game.remaining / _game.warning_duration
		if progress > 0.78:
			var drop := pow(1.0 - (progress - 0.78) / 0.22, 1.5)
			_draw_shoe(_game.shadow_position - Vector2(0, 410 * drop), _game.shoe_angle, 1.0 + 0.36 * drop, _game.stomp_scale)
	elif _game.step == Game.Step.LANDED:
		var lift := clampf(1.0 - _game.remaining / minf(0.25, _game.landed_duration), 0.0, 1.0)
		if _game.loss == Game.Loss.SHOE:
			lift = clampf((_game.impact_age - 0.36) * 2.2, 0.0, 1.0)
		_draw_shoe(_game.shadow_position - Vector2(0, 390 * lift * lift), _game.shoe_angle, 1.0 + 0.32 * lift, _game.stomp_scale)


func _draw_title_scene() -> void:
	var bob := sin(_game.clock * 2.1) * 4.0
	_draw_shadow(Vector2(938, 408), -0.55, 0.36)
	_draw_shoe(Vector2(981, 298 + bob), -0.55, 1.13)
	_draw_spider(Vector2(143, 503 - bob), -1.16, _game.clock * 4.0)
	draw_ant(self, Vector2(177, 398 + bob), -0.55, Vector2.ONE * 1.65, 0.0, _game.clock, false)
	for index in 3:
		var center := Vector2(112 - index * 14, 425 + index * 8)
		draw_line(center, center + Vector2(-15, 8), Color(1.0, 0.92, 0.63, 0.68), 2.5, true)


func _draw_shadow(at: Vector2, angle: float, progress: float, scale_factor := Game.SHOE_SCALE, accent := CREAM) -> void:
	draw_set_transform(at, angle, Vector2.ONE * scale_factor)
	var pulse := 0.5 + sin(progress * 21.0) * 0.5
	var shadow_color := Color(0.12, 0.12, 0.10, 0.59 + 0.19 * progress)
	draw_colored_polygon(_sole, shadow_color)
	_outline(self, _sole, Color(0.23, 0.20, 0.12, 0.7), 7.0)
	_outline(self, _sole, accent.lerp(Color("ffc478") if accent == CREAM else accent.darkened(0.18), progress), 2.8)
	for index in _sole.size():
		if index % 2 == 0:
			var point := _sole[index]
			var approach := point.normalized() * (12.0 + (1.0 - progress) * 14.0)
			draw_line(point + approach, point + approach * 0.63,
				Color(1.0, 0.9, 0.59, 0.46 + pulse * 0.35), 2.2, true)
	draw_circle(Vector2(0, -7), 11.0, Color(1.0, 0.84, 0.53, 0.23), true, -1.0, true)
	draw_line(Vector2(0, -13), Vector2(0, -7), CREAM, 2.2, true)
	draw_circle(Vector2(0, -2), 1.3, CREAM, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_shoe(at: Vector2, angle: float, perspective_scale: float, scale_factor := Game.SHOE_SCALE) -> void:
	var size := Vector2.ONE * (scale_factor * perspective_scale)
	draw_set_transform(at + Vector2(4, 9) * scale_factor, angle, size)
	draw_colored_polygon(_sole, Color("74594b"))
	_outline(self, _sole, INK, 5.0)
	draw_set_transform(at + Vector2(2, 4) * scale_factor, angle, size)
	draw_colored_polygon(_sole, Color("f7dfad"))
	_outline(self, _sole, INK, 3.0)
	draw_set_transform(at, angle, size)
	var upper := PackedVector2Array()
	for point in _sole:
		upper.append(point * Vector2(0.91, 0.97))
	draw_colored_polygon(upper, Color("b84936"))
	_outline(self, upper, Color("5b342d"), 2.4)

	var toe := PackedVector2Array([Vector2(-47, -68), Vector2(-44, -87), Vector2(-36, -102),
		Vector2(-23, -112), Vector2(-9, -115), Vector2(15, -113), Vector2(31, -102),
		Vector2(42, -85), Vector2(46, -66), Vector2(29, -68), Vector2(6, -73),
		Vector2(-22, -71)])
	draw_colored_polygon(toe, Color("ed8f65"))
	_arc(self, Vector2(-2, -71), Vector2(43, 35), 3.58, 5.60, Color("ffc289"), 2.4)
	draw_polyline(PackedVector2Array([Vector2(-43, -63), Vector2(-20, -65), Vector2(4, -66),
		Vector2(29, -62), Vector2(44, -60)]), Color("713930"), 2.3, true)
	for side in [-1.0, 1.0]:
		var stripe := PackedVector2Array([Vector2(35 * side, -48), Vector2(42 * side, -38),
			Vector2(26 * side, -5), Vector2(23 * side, 13), Vector2(20 * side, 3)])
		draw_colored_polygon(stripe, Color("f7bd83"))
		_arc(self, Vector2(-2, 60), Vector2(29, 46), 0.2 if side > 0.0 else 1.91,
			1.24 if side > 0.0 else 2.90, Color("e17a55"), 2.0)

	_ellipse(self, Vector2(-3, 62), Vector2(27, 38), Color("843c31"))
	_ellipse(self, Vector2(-3, 61), Vector2(23, 34), Color("f2aa78"))
	_ellipse(self, Vector2(-3, 65), Vector2(18, 27), Color("402b2d"))
	_ellipse(self, Vector2(-4, 71), Vector2(13, 17), Color("654236"))
	var tongue := PackedVector2Array([Vector2(-18, -58), Vector2(17, -58), Vector2(14, 32),
		Vector2(4, 41), Vector2(-10, 40), Vector2(-18, 32)])
	draw_colored_polygon(tongue, Color("df7652"))
	_outline(self, tongue, Color("8d4838"), 1.8)
	for index in 5:
		var y := -48.0 + index * 13.0
		draw_circle(Vector2(-15, y), 3.4, Color("774038"), true, -1.0, true)
		draw_circle(Vector2(15, y), 3.4, Color("774038"), true, -1.0, true)
		draw_line(Vector2(-15, y), Vector2(15, y + 2), Color("ffedc1"), 3.6, true)
	_ellipse(self, Vector2(-3, 20), Vector2(4, 3), Color("fff2cc"))
	_arc(self, Vector2(-11, 22), Vector2(8, 4), 0.0, TAU, Color("ffedc1"), 2.7)
	_arc(self, Vector2(5, 22), Vector2(8, 4), 0.0, TAU, Color("ffedc1"), 2.7)
	draw_line(Vector2(-3, 22), Vector2(-13, 35), Color("ffedc1"), 2.4, true)
	draw_line(Vector2(-3, 22), Vector2(6, 32), Color("ffedc1"), 2.4, true)
	draw_set_transform(Vector2.ZERO)


func _draw_impact(at: Vector2, progress: float) -> void:
	var fade := 1.0 - progress
	var expansion := 1.0 - fade * fade
	draw_arc(at, 39.0 + expansion * 110.0, 0.0, TAU, 52, Color(1, 0.9, 0.57, fade * 0.75), 3.5, true)
	for index in 23:
		var angle := index * 2.39996
		var direction := Vector2.from_angle(angle)
		var point := at + direction * (60.0 + expansion * (56.0 + index % 7 * 13.0))
		point.y -= sin(progress * PI) * (11.0 + index % 5 * 3.0)
		var color := Color(1.0, 0.83, 0.51, fade) if index % 3 == 0 else Color(0.29, 0.42, 0.19, fade)
		draw_line(point, point + direction * (4.0 + fade * 6.0), color, 2.5, true)


func _draw_spider(at: Vector2, angle: float, gait: float, bite := 0.0) -> void:
	draw_set_transform(at + Vector2(3, 6), angle)
	_ellipse(self, Vector2(-6, 0), Vector2(30, 21), Color(0.16, 0.13, 0.18, 0.33))
	draw_set_transform(at, angle)
	for side in [-1.0, 1.0]:
		for index in 4:
			var stride := sin(gait + index * PI + side * PI * 0.5) * 5.0
			var hip := Vector2(11.0 - index * 7.0, side * 8.0)
			var knee := Vector2(23.0 - index * 15.0 + stride, side * (25.0 + index * 1.8))
			var foot := Vector2(39.0 - index * 23.0 + stride, side * (31.0 + index * 1.8))
			draw_polyline(PackedVector2Array([hip, knee, foot]), SPIDER_INK, 4.6, true)
			draw_line(hip, knee, Color("75627e"), 1.6, true)
			draw_circle(foot, 2.2, SPIDER_INK, true, -1.0, true)
		var jaw := Vector2(27.0 + 4.0 * bite, side * (5.0 + 3.0 * bite))
		draw_polyline(PackedVector2Array([Vector2(15, side * 6.0), Vector2(24, side * 10.0), jaw]),
			SPIDER_INK, 3.3, true)
	_ellipse(self, Vector2(-11, 0), Vector2(22, 18), SPIDER_INK)
	_ellipse(self, Vector2(-12, -1), Vector2(18, 14), Color("55435e"))
	_arc(self, Vector2(-9, 0), Vector2(13, 16), 3.6, 4.8, Color("8a7591"), 2.0)
	_ellipse(self, Vector2(11, 0), Vector2(15, 13), SPIDER_INK)
	_ellipse(self, Vector2(11, -1), Vector2(12, 10), Color("65516b"))
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(18, side * 4.0), 3.0, Color("ffe2b4"), true, -1.0, true)
		draw_circle(Vector2(19, side * 4.0), 1.45, SPIDER_INK, true, -1.0, true)
		draw_circle(Vector2(13, side * 7.0), 1.6, Color("e6b7a5"), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


static func draw_ant(canvas: CanvasItem, at: Vector2, angle: float, size: Vector2,
		gait: float, time: float, flattened: bool, zombie := false) -> void:
	canvas.draw_set_transform(at + Vector2(2, 4), angle, size)
	_ellipse(canvas, Vector2(-3, 0), Vector2(25, 13), Color(0.16, 0.19, 0.12, 0.31))
	canvas.draw_set_transform(at, angle, size)
	for side in [-1.0, 1.0]:
		for index in 3:
			var step := sin(gait + float(index) * PI + side * PI * 0.5) * 4.0
			var start := Vector2(5.0 - index * 7.0, 3.0 * side)
			var knee := Vector2(9.0 - index * 10.0 + step, (12.0 + index) * side)
			var foot := Vector2(15.0 - index * 15.0 + step, (20.0 - (index % 2) * 2.0) * side)
			canvas.draw_polyline(PackedVector2Array([start, knee, foot]), INK, 2.9, true)
			canvas.draw_circle(foot, 1.5, INK, true, -1.0, true)
		var wiggle := sin(time * 5.0 + side) * 1.7
		var tip := Vector2(30.0, side * (12.0 + wiggle))
		canvas.draw_polyline(PackedVector2Array([Vector2(17, side * 4), Vector2(24, side * 9), tip]), INK, 2.4, true)
		canvas.draw_circle(tip, 2.2, INK, true, -1.0, true)
	_ellipse(canvas, Vector2(-16, 0), Vector2(16, 10.6), INK)
	_ellipse(canvas, Vector2(-16, -0.5), Vector2(13, 8.2), Color("55715b") if zombie else Color("a24c34"))
	_ellipse(canvas, Vector2(-20, -3.5), Vector2(6, 2.1), Color("b7d78b") if zombie else Color("e69358"))
	_ellipse(canvas, Vector2(-1, 0), Vector2(11, 8.7), INK)
	_ellipse(canvas, Vector2(-1, -0.5), Vector2(8, 6.2), Color("708f67") if zombie else Color("c4653e"))
	_ellipse(canvas, Vector2(13, 0), Vector2(12.5, 10.2), INK)
	_ellipse(canvas, Vector2(13, -0.7), Vector2(10, 7.8), Color("678864") if zombie else Color("b95435"))
	for side in [-1.0, 1.0]:
		var eye := Vector2(16.5, side * 4.0)
		if flattened:
			canvas.draw_line(eye - Vector2(1.5, 1.5), eye + Vector2(1.5, 1.5), CREAM, 1.2, true)
			canvas.draw_line(eye - Vector2(1.5, -1.5), eye + Vector2(1.5, -1.5), CREAM, 1.2, true)
		else:
			_ellipse(canvas, eye, Vector2(3.3, 2.7), Color("f6d887") if zombie else Color("fff0ca"))
			canvas.draw_circle(eye + Vector2(1, 0), 1.45, INK, true, -1.0, true)
	if zombie:
		canvas.draw_polyline(PackedVector2Array([Vector2(-22, -6), Vector2(-18, 1), Vector2(-22, 4),
			Vector2(-17, 8)]), Color("293d35"), 2.4, true)
		for side in [-1.0, 1.0]:
			canvas.draw_polyline(PackedVector2Array([Vector2(23, side * 6.0), Vector2(29, side * 8.0),
				Vector2(34, side * 3.0)]), INK, 4.5, true)
			canvas.draw_line(Vector2(29, side * 7.0), Vector2(33, side * 3.0), CREAM, 1.8, true)
	canvas.draw_set_transform(Vector2.ZERO)


static func _ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 36:
		points.append(center + Vector2.from_angle(float(index) * TAU / 36.0) * radius)
	canvas.draw_colored_polygon(points, color)


static func _arc(canvas: CanvasItem, center: Vector2, radius: Vector2, start: float,
		end: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 29:
		points.append(center + Vector2.from_angle(lerpf(start, end, float(index) / 28.0)) * radius)
	canvas.draw_polyline(points, color, width, true)


static func _outline(canvas: CanvasItem, shape: PackedVector2Array, color: Color, width: float) -> void:
	var closed := shape.duplicate()
	closed.append(shape[0])
	canvas.draw_polyline(closed, color, width, true)
