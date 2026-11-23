extends RefCounted

const Lan = preload("res://scripts/lan.gd")
const ZOMBIE_SPEED := 252.0
const BITE_RADIUS := 29.0
const RISE_TIME := 0.75

class Runner:
	var id := 0
	var at := Vector2.ZERO
	var angle := 0.0
	var gait := 0.0
	var direction := Vector2.ZERO
	var input_age := 0.0
	var boost := 0.0
	var shield := 0.0
	var grace := 0.0
	var jump := 0.0
	var recovery := 0.0
	var jump_direction := Vector2.ZERO
	var zombie := false
	var rise := 0.0

class Shoe:
	var id := 0
	var step := 0
	var at := Vector2.ZERO
	var remaining := 0.0
	var warning := 0.0
	var landed := 0.0
	var impact := 1.0
	var scale_factor := 1.5
	var charge := 0
	var power := 0
	var terrain_at := Vector2.ZERO
	var terrain_scale := 1.5
	var terrain_time := 0.0
	var terrain := PackedVector2Array()
	var landing := PackedVector2Array()

var game
var runners: Dictionary = {}
var shoes: Dictionary = {}
var cue_serial := 0
var cue: StringName = &"start"
var _shoe_pickup_wait := 0.0
var _next_shoe_pickup := 1


func _init(world) -> void:
	game = world


func reset() -> void:
	runners.clear()
	shoes.clear()
	cue_serial = 0
	cue = &"start"
	_shoe_pickup_wait = 3.0
	_next_shoe_pickup = game.ShoePower.QUICK
	var ids: Array = game.lan.players.keys()
	ids.sort()
	var ant_count := 0
	for id in ids:
		if game.lan.choice(id) == Lan.Choice.ANT:
			var ant := Runner.new()
			ant.id = id
			ant.at = game.FIELD.get_center() + Vector2(ant_count * 125.0 - 110.0, -35.0 + (ant_count % 2) * 70.0)
			runners[id] = ant
			ant_count += 1
		elif game.lan.choice(id) == Lan.Choice.SHOE:
			var shoe := Shoe.new()
			shoe.id = id
			shoes[id] = shoe


func living_count() -> int:
	var count := 0
	for ant: Runner in runners.values():
		if not ant.zombie:
			count += 1
	return count


func nearest_live(at: Vector2) -> Runner:
	var nearest: Runner
	var best_distance := INF
	for ant: Runner in runners.values():
		if not ant.zombie and at.distance_squared_to(ant.at) < best_distance:
			nearest = ant
			best_distance = at.distance_squared_to(ant.at)
	return nearest


func set_movement(id: int, direction: Vector2) -> void:
	var ant: Runner = runners.get(id)
	if ant != null:
		ant.direction = direction
		ant.input_age = 0.0


func jump(id: int, direction: Vector2) -> void:
	var ant: Runner = runners.get(id)
	if game.mode != game.Mode.RUNNING or ant == null or ant.zombie or ant.jump > 0.0 or ant.recovery > 0.0:
		return
	ant.jump_direction = direction if not direction.is_zero_approx() else Vector2.from_angle(ant.angle)
	ant.jump = game.JUMP_DURATION
	_play(&"jump")


func tick(delta: float) -> void:
	for shoe: Shoe in shoes.values():
		shoe.terrain_time = maxf(0.0, shoe.terrain_time - delta)
	for ant: Runner in runners.values():
		_move_runner(ant, delta)
	_update_ant_pickup(delta)
	_update_shoe_pickup(delta)
	for shoe: Shoe in shoes.values():
		_tick_shoe(shoe, delta)
	for zombie: Runner in runners.values():
		if zombie.zombie and zombie.rise <= 0.0:
			hit_near(zombie.at, BITE_RADIUS, &"bite")


func tick_jumps(delta: float) -> void:
	for ant: Runner in runners.values():
		if ant.jump > 0.0:
			ant.jump = maxf(0.0, ant.jump - delta)
			if ant.jump <= 0.00001:
				ant.jump = 0.0
				ant.recovery = game.JUMP_RECOVERY
		else:
			ant.recovery = maxf(0.0, ant.recovery - delta)


func _move_runner(ant: Runner, delta: float) -> void:
	ant.input_age += delta
	ant.boost = maxf(0.0, ant.boost - delta)
	ant.shield = maxf(0.0, ant.shield - delta)
	ant.grace = maxf(0.0, ant.grace - delta)
	if ant.rise > 0.0:
		ant.rise = maxf(0.0, ant.rise - delta)
		return
	var direction := ant.direction if ant.input_age <= 0.35 else Vector2.ZERO
	var speed: float = ZOMBIE_SPEED if ant.zombie else game.RUN_SPEED
	if ant.boost > 0.0:
		speed *= game.BOOST_MULTIPLIER
	if ant.jump > 0.0:
		direction = ant.jump_direction
		speed = game.JUMP_SPEED
	elif ant.recovery > 0.0:
		speed *= game.RECOVERY_MULTIPLIER
	if game.on_slime(ant.at, ant.jump > 0.0):
		speed *= game.SLIME_SPEED_MULTIPLIER
	var velocity := direction * speed
	if game.yard_event == game.YardEvent.WIND_GUST and game.event_age >= game.WIND_WARNING:
		velocity.x += game.wind_direction * game.WIND_SPEED
	if not velocity.is_zero_approx():
		var destination := (ant.at + velocity * delta).clamp(game.RUN_BOUNDS.position, game.RUN_BOUNDS.end)
		var obstacles: Array[PackedVector2Array] = []
		for shoe: Shoe in shoes.values():
			if shoe.terrain_time > 0.0 and not Geometry2D.is_point_in_polygon(ant.at, shoe.terrain):
				obstacles.append(shoe.terrain)
		ant.at = game.move_around_terrain(ant.at, destination, obstacles)
	if not direction.is_zero_approx():
		ant.angle = lerp_angle(ant.angle, direction.angle(), minf(1.0, delta * 18.0))
		ant.gait = fmod(ant.gait + delta * 24.0 * speed / game.RUN_SPEED, TAU)


func _update_ant_pickup(delta: float) -> void:
	if game.power == game.Power.NONE:
		game._power_delay -= delta
		if game._power_delay <= 0.0:
			game._spawn_power()
		return
	for ant: Runner in runners.values():
		if ant.zombie or ant.at.distance_squared_to(game.power_position) > game.PICKUP_RADIUS * game.PICKUP_RADIUS:
			continue
		if game.power == game.Power.SPEED:
			ant.boost = game.BOOST_TIME
		else:
			ant.shield = game.SHIELD_DURATION
		game.power = game.Power.NONE
		game._power_delay = game.PICKUP_INTERVAL
		_play(&"pickup")
		break


func _update_shoe_pickup(delta: float) -> void:
	if game.shoe_pickup != game.ShoePower.NONE:
		return
	_shoe_pickup_wait -= delta
	if _shoe_pickup_wait > 0.0:
		return
	for shoe: Shoe in shoes.values():
		if shoe.charge == game.ShoePower.NONE:
			var area: Rect2 = game.FIELD.grow(-65.0)
			game.shoe_pickup_position = Vector2(game._rng.randf_range(area.position.x, area.end.x),
				game._rng.randf_range(area.position.y, area.end.y))
			game.shoe_pickup = _next_shoe_pickup
			_next_shoe_pickup = game.ShoePower.QUICK if _next_shoe_pickup == game.ShoePower.DENIAL else _next_shoe_pickup + 1
			return


func request_stomp(id: int, target: Vector2) -> void:
	var shoe: Shoe = shoes.get(id)
	if shoe == null or game.mode != game.Mode.RUNNING or not target.is_finite() or not game.FIELD.has_point(target):
		return
	if game._over_shoe_pickup(target) and shoe.charge == game.ShoePower.NONE:
		shoe.charge = game.shoe_pickup
		game.shoe_pickup = game.ShoePower.NONE
		_shoe_pickup_wait = game.SHOE_PICKUP_INTERVAL
		_play(&"pickup")
		return
	if not ready_to_stomp(shoe):
		return
	shoe.step = game.Step.WARNING
	shoe.at = target
	shoe.scale_factor = aiming_scale(shoe)
	shoe.power = shoe.charge
	shoe.charge = game.ShoePower.NONE
	shoe.warning = 0.60 if shoe.power == game.ShoePower.QUICK else 0.9
	shoe.remaining = shoe.warning
	shoe.landing = game.footprint(target, 0.0, shoe.scale_factor)
	_play(&"warning")


func aiming_scale(shoe: Shoe) -> float:
	return game.SHOE_SCALE * game.WIDE_SCALE if shoe.charge == game.ShoePower.WIDE else game.SHOE_SCALE


func ready_to_stomp(shoe: Shoe) -> bool:
	return shoe.step == game.Step.WAITING and shoe.remaining <= 0.0


func _tick_shoe(shoe: Shoe, delta: float) -> void:
	shoe.impact += delta
	shoe.remaining = maxf(0.0, shoe.remaining - delta)
	if shoe.remaining > 0.0:
		return
	if shoe.step == game.Step.WARNING:
		shoe.step = game.Step.LANDED
		shoe.impact = 0.0
		shoe.landed = 0.5
		shoe.remaining = shoe.landed
		_play(&"impact")
		if shoe.power == game.ShoePower.DENIAL:
			shoe.terrain_at = shoe.at
			shoe.terrain_scale = shoe.scale_factor
			shoe.terrain_time = game.DENIAL_DURATION
			var outlines := Geometry2D.offset_polygon(shoe.landing, game.BODY_RADIUS, Geometry2D.JOIN_ROUND)
			shoe.terrain = shoe.landing.duplicate() if outlines.is_empty() else outlines[0]
		var hit := false
		for ant: Runner in runners.values():
			if not ant.zombie and ant.jump <= 0.0 and game.ant_in_footprint(ant.at, shoe.landing):
				hit = true
				_hit(ant, &"impact")
		if not hit:
			game.score += 1
	elif shoe.step == game.Step.LANDED:
		shoe.step = game.Step.WAITING
		shoe.remaining = 0.44


func hit_near(at: Vector2, radius: float, sound: StringName = &"bite") -> void:
	for ant: Runner in runners.values():
		if not ant.zombie and at.distance_squared_to(ant.at) <= radius * radius:
			_hit(ant, sound)


func _hit(ant: Runner, sound: StringName) -> bool:
	if ant.zombie or ant.jump > 0.0 or ant.grace > 0.0:
		return false
	if ant.shield > 0.0:
		ant.grace = minf(game.SHIELD_GRACE, ant.shield)
		ant.shield = 0.0
		_play(&"shield")
		return false
	ant.zombie = true
	ant.rise = RISE_TIME
	ant.boost = 0.0
	ant.recovery = 0.0
	_play(sound)
	return true


func _play(sound: StringName) -> void:
	cue_serial += 1
	cue = sound
	game._sound.play_cue(sound)


func snapshot() -> Array:
	var runner_data := []
	for ant: Runner in runners.values():
		runner_data.append([ant.id, ant.at, ant.angle, ant.gait, ant.zombie, ant.rise, ant.jump, ant.recovery, ant.boost, ant.shield, ant.grace])
	var shoe_data := []
	for shoe: Shoe in shoes.values():
		shoe_data.append([shoe.id, shoe.step, shoe.at, shoe.remaining, shoe.warning, shoe.landed,
			shoe.impact, shoe.scale_factor, shoe.charge, shoe.power, shoe.terrain_at, shoe.terrain_scale, shoe.terrain_time])
	return [runner_data, shoe_data, cue_serial, cue]


func apply_snapshot(data: Array) -> void:
	for item: Array in data[0]:
		var ant: Runner = runners.get(item[0])
		if ant == null:
			continue
		ant.at = item[1]
		ant.angle = item[2]
		ant.gait = item[3]
		ant.zombie = item[4]
		ant.rise = item[5]
		ant.jump = item[6]
		ant.recovery = item[7]
		ant.boost = item[8]
		ant.shield = item[9]
		ant.grace = item[10]
	for item: Array in data[1]:
		var shoe: Shoe = shoes.get(item[0])
		if shoe == null:
			continue
		shoe.step = item[1]
		shoe.at = item[2]
		shoe.remaining = item[3]
		shoe.warning = item[4]
		shoe.landed = item[5]
		shoe.impact = item[6]
		shoe.scale_factor = item[7]
		shoe.charge = item[8]
		shoe.power = item[9]
		shoe.terrain_at = item[10]
		shoe.terrain_scale = item[11]
		shoe.terrain_time = item[12]
	if cue_serial != data[2]:
		cue_serial = data[2]
		game._sound.play_cue(data[3])
