extends Node2D

const Lan = preload("res://scripts/lan.gd")
const Party = preload("res://scripts/party.gd")
const Sound = preload("res://scripts/sound.gd")
const FIELD := Rect2(38, 105, 1076, 525)
const RUN_BOUNDS := Rect2(62, 126, 1028, 483)
const SCORE_PATH := "user://scores.cfg"
const RUN_SPEED := 300.0
const BODY_RADIUS := 10.0
const SHOE_SCALE := 1.5
const WIDE_SCALE := 1.30
const CRATER_DURATION := 8.0
const SHOE_PICKUP_RADIUS := 29.0
const SHOE_PICKUP_INTERVAL := 5.0
const SPIDER_SPAWN := Vector2(245, 493)
const SPIDER_SPEED := 126.0
const SPIDER_RADIUS := 23.0
const JUMP_DURATION := 0.30
const JUMP_SPEED := 660.0
const JUMP_RECOVERY := 1.7
const RECOVERY_MULTIPLIER := 0.60
const BOOST_TIME := 5.0
const BOOST_MULTIPLIER := 1.45
const PICKUP_RADIUS := 29.0
const PICKUP_INTERVAL := 3.5
const SHIELD_DURATION := 15.0
const SHIELD_GRACE := 1.0
const LOSS_DELAY := 0.78
const METEOR_RADIUS := 92.0
const METEOR_WARNING := 1.45
const METEOR_SPACING := 0.42
const METEOR_COUNT := 32
const METEOR_DURATION := 16.0
# Visits every cell and spaces the next four impacts apart, including across the wrap.
const METEOR_GRID_ORDER := [
	26, 2, 23, 8, 12, 18, 22, 0, 4, 28, 14, 17, 3, 27, 13, 7,
	9, 19, 29, 6, 31, 1, 25, 21, 11, 15, 24, 5, 10, 30, 16, 20,
]
const SNAIL_WARNING := 1.0
const SNAIL_DURATION := 10.0
const SNAIL_FIRST_DELAY := Vector2(9.0, 14.0)
const SNAIL_RETURN_DELAY := Vector2(12.0, 18.0)
const SLIME_LIFETIME := 6.0
const SLIME_SAMPLE_INTERVAL := 0.20
const SLIME_WIDTH := 48.0
const SLIME_SPEED_MULTIPLIER := 0.25
const WIND_WARNING := 1.0
const WIND_DURATION := 6.0
const WIND_SPEED := 120.0
const RUSH_WARNING := 1.2
const RUSH_DURATION := 8.0
const SOLE := [
	Vector2(-10, -119), Vector2(15, -117), Vector2(34, -106), Vector2(46, -88),
	Vector2(51, -64), Vector2(49, -43), Vector2(42, -18), Vector2(33, 7),
	Vector2(30, 30), Vector2(35, 57), Vector2(35, 82), Vector2(27, 103),
	Vector2(13, 113), Vector2(-10, 115), Vector2(-27, 108), Vector2(-38, 94),
	Vector2(-42, 72), Vector2(-39, 49), Vector2(-33, 26), Vector2(-32, 3),
	Vector2(-42, -20), Vector2(-51, -44), Vector2(-54, -67), Vector2(-50, -89),
	Vector2(-40, -106), Vector2(-26, -116),
]

enum Mode { TITLE, RUNNING, PAUSED, LOST }
enum Step { WAITING, WARNING, LANDED }
enum Loss { NONE, SHOE, SPIDER, METEOR }
enum YardEvent { NONE, METEORS, SPIDER_RUSH, WIND_GUST }
enum Power { NONE, SPEED, SHIELD }
enum ShoePower { NONE, QUICK, WIDE, CRATER }

const YARD_EVENTS: Array[YardEvent] = [YardEvent.METEORS, YardEvent.SPIDER_RUSH, YardEvent.WIND_GUST]

var mode := Mode.TITLE
var step := Step.WAITING
var score := 0
var best := 0
var clock := 0.0
var remaining := 0.0
var warning_duration := 0.0
var landed_duration := 0.0
var lost_delay := 0.0
var ant_position := FIELD.get_center()
var ant_angle := -0.6
var gait := 0.0
var moving := false
var loss := Loss.NONE
var spider_position := SPIDER_SPAWN
var spider_angle := -0.4
var spider_gait := 0.0
var yard_event := YardEvent.NONE
var event_age := 0.0
var meteor_targets := PackedVector2Array()
var meteors_landed := 0
var wind_direction := 0.0
var _meteor_seed := 0
var snail_active := false
var snail_age := 0.0
var _snail_wait := 0.0
var _snail_rng := RandomNumberGenerator.new()
var snail_direction := 1.0
var snail_lane := 0.0
var snail_trail := PackedVector2Array()
var _slime_start := -1
var _slime_end := -1
var rush_spiders := PackedVector2Array()
var rush_angles := PackedFloat32Array()
var spider_biter := -1
var _event_wait := 0.0
var shadow_position := Vector2.ZERO
var shoe_angle := 0.0
var stomp_scale := SHOE_SCALE
var stomp_power := ShoePower.NONE
var shoe_pickup := ShoePower.NONE
var shoe_pickup_position := Vector2.ZERO
var landing_shape := PackedVector2Array()
var impact_age := 1.0
var power := Power.NONE
var power_position := Vector2.ZERO
var boost_time := 0.0
var shield_time := 0.0
var shield_grace := 0.0
var stomp_blocked := false
var stomp_evaded := false
var jump_time := 0.0
var jump_recovery := 0.0
var _jump_direction := Vector2.ZERO

var _next_power := Power.SPEED
var _power_delay := 0.0
var _pickup_count := 0

var lan: Lan
var party: Party
var _movement_send_time := 0.0
var _snapshot_time := 0.0
var _rng := RandomNumberGenerator.new()
var _sound: Node
@onready var _actors: Node2D = $PlayfieldClip/Actors
@onready var _interface: Control = $Interface


func _ready() -> void:
	_bind_keys(&"scurry_left", [KEY_A, KEY_LEFT])
	_bind_keys(&"scurry_right", [KEY_D, KEY_RIGHT])
	_bind_keys(&"scurry_up", [KEY_W, KEY_UP])
	_bind_keys(&"scurry_down", [KEY_S, KEY_DOWN])
	var scores := ConfigFile.new()
	if scores.load(SCORE_PATH) == OK:
		best = maxi(0, int(scores.get_value("scores", "best", 0)))
	_sound = Sound.new()
	add_child(_sound)
	lan = Lan.new()
	lan.name = "LAN"
	add_child(lan)
	lan.changed.connect(_lan_changed)
	party = Party.new(self)
	lan.lobby_changed.connect(_lobby_changed)
	lan.begin_round.connect(_start_run)
	lan.stomp_requested.connect(party.request_stomp)
	lan.movement_received.connect(party.set_movement)
	lan.jump_requested.connect(party.jump)
	lan.state_received.connect(_apply_snapshot)
	_interface.refresh()
	_start_from_launcher.call_deferred()


func _start_from_launcher() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 6 and args[0] == "--game-pack":
		_start_from_pack(args)
		return
	if args.size() < 2 or args.size() > 3:
		return
	if args[0] != "--launcher-host" and args[0] != "--launcher-join":
		return
	if args.size() == 3 and args[2].length() <= 108:
		lan.local_player_name = Lan.clean_player_name(Marshalls.base64_to_utf8(args[2]))
	if args[0] == "--launcher-host":
		lan.changed.connect(_write_launcher_status.bind(args[1]))
		lan.host()
	else:
		lan.join(args[1])


func _start_from_pack(args: PackedStringArray) -> void:
	if args[1].length() != 64 or not args[1].is_valid_hex_number(false):
		return
	lan.pack_build = args[1]
	if args[5] != "-" and args[5].length() <= 108:
		lan.local_player_name = Lan.clean_player_name(Marshalls.base64_to_utf8(args[5]))
	if args[3] == "host":
		lan.changed.connect(_write_launcher_status.bind(args[2]))
		lan.host()
		return
	if args[3] == "join":
		lan.join(args[4])
	elif args[3] == "solo":
		_start_run()
	else:
		return
	if args[2].is_absolute_path():
		var marker := FileAccess.open(args[2], FileAccess.WRITE)
		if marker != null:
			marker.store_string("ready")


func _write_launcher_status(path: String) -> void:
	if not path.is_absolute_path():
		return
	var marker := FileAccess.open(path, FileAccess.WRITE)
	if marker != null:
		marker.store_string("ready" if lan.role == Lan.Role.HOST else lan.status)


func _bind_keys(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var input := InputEventKey.new()
		input.physical_keycode = key
		InputMap.action_add_event(action, input)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE and mode == Mode.RUNNING and (lan.role == Lan.Role.SOLO or party.runners.has(lan.local_id())):
		if lan.role == Lan.Role.SOLO:
			_try_jump()
		else:
			lan.request_jump(_movement_input())
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if get_viewport().gui_get_focus_owner() is LineEdit:
				return
			if lan.role == Lan.Role.SOLO and mode != Mode.RUNNING and (mode != Mode.LOST or lost_delay <= 0.0):
				primary_action()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if lan.role == Lan.Role.SOLO and (mode == Mode.RUNNING or mode == Mode.PAUSED):
				toggle_pause()
				get_viewport().set_input_as_handled()
		KEY_M:
			toggle_sound()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == Mode.RUNNING and lan.role == Lan.Role.SOLO:
		toggle_pause()


func primary_action() -> void:
	if lan.role != Lan.Role.SOLO:
		if lan.role == Lan.Role.HOST and mode == Mode.LOST and lost_delay <= 0.0:
			lan.reopen_lobby()
		return
	lan.status = ""
	match mode:
		Mode.TITLE, Mode.LOST:
			_start_run()
		Mode.PAUSED:
			toggle_pause()


func toggle_pause() -> void:
	if mode == Mode.RUNNING:
		mode = Mode.PAUSED
	elif mode == Mode.PAUSED:
		mode = Mode.RUNNING
	_interface.refresh()


func toggle_sound() -> void:
	_sound.toggle_mute()
	_interface.refresh()


func sound_is_muted() -> bool:
	return _sound.muted


func _start_run() -> void:
	mode = Mode.RUNNING
	step = Step.WAITING
	score = 0
	remaining = 0.65 if lan.role == Lan.Role.SOLO else 0.0
	lost_delay = 0.0
	ant_position = FIELD.get_center()
	ant_angle = -0.6
	gait = 0.0
	moving = false
	loss = Loss.NONE
	spider_position = SPIDER_SPAWN
	spider_angle = (ant_position - spider_position).angle()
	spider_gait = 0.0
	impact_age = 1.0
	boost_time = 0.0
	shield_time = 0.0
	shield_grace = 0.0
	stomp_blocked = false
	stomp_evaded = false
	jump_time = 0.0
	jump_recovery = 0.0
	_pickup_count = 0
	_next_power = Power.SPEED if _rng.randf() < 0.5 else Power.SHIELD
	_spawn_power()
	stomp_scale = SHOE_SCALE
	stomp_power = ShoePower.NONE
	shoe_pickup = ShoePower.NONE
	party.reset()
	_movement_send_time = 0.0
	_snapshot_time = 0.0
	yard_event = YardEvent.NONE
	event_age = 0.0
	_event_wait = _rng.randf_range(12.0, 18.0)
	meteor_targets.clear()
	meteors_landed = 0
	wind_direction = 0.0
	snail_active = false
	snail_age = 0.0
	_snail_wait = _snail_rng.randf_range(SNAIL_FIRST_DELAY.x, SNAIL_FIRST_DELAY.y)
	_clear_snail_trail()
	rush_spiders.clear()
	rush_angles.clear()
	spider_biter = -1
	_sound.play_cue(&"start")
	_interface.refresh()


func _physics_process(delta: float) -> void:
	if lan.role == Lan.Role.GUEST:
		clock += delta
		if mode == Mode.RUNNING and party.runners.has(lan.local_id()):
			_movement_send_time += delta
			if _movement_send_time >= 1.0 / 30.0:
				_movement_send_time = 0.0
				lan.send_movement(_movement_input())
		_actors.queue_redraw()
		return
	if mode == Mode.PAUSED:
		return
	clock += delta
	impact_age += delta
	if mode == Mode.RUNNING:
		if lan.role == Lan.Role.SOLO:
			_tick_solo(delta)
		else:
			party.set_movement(lan.local_id(), _movement_input())
			party.tick(delta)
			var target := party.nearest_live(spider_position)
			if target != null:
				ant_position = target.at
		if mode == Mode.RUNNING:
			_move_spider(delta)
		if mode == Mode.RUNNING:
			_tick_yard_event(delta)
		if mode == Mode.RUNNING:
			_tick_snail(delta)
			if lan.role == Lan.Role.SOLO:
				_tick_jump(delta)
			else:
				party.tick_jumps(delta)
				if party.living_count() == 0:
					_end_run(Loss.NONE)
	elif mode == Mode.LOST and lost_delay > 0.0:
		lost_delay = maxf(0.0, lost_delay - delta)
		if lost_delay <= 0.0:
			_interface.refresh()
	_actors.queue_redraw()
	_interface.queue_redraw()
	if lan.role == Lan.Role.HOST and lan.in_round:
		_snapshot_time += delta
		if _snapshot_time >= 1.0 / 30.0:
			_snapshot_time = 0.0
			_publish_snapshot()


func _movement_input() -> Vector2:
	return Input.get_vector(&"scurry_left", &"scurry_right", &"scurry_up", &"scurry_down")


func _tick_solo(delta: float) -> void:
	boost_time = maxf(0.0, boost_time - delta)
	shield_time = maxf(0.0, shield_time - delta)
	shield_grace = maxf(0.0, shield_grace - delta)
	_move_ant(delta)
	_update_power(delta)
	remaining = maxf(0.0, remaining - delta)
	if remaining > 0.0:
		return
	match step:
		Step.WAITING:
			_warn(_movement_input())
		Step.WARNING:
			_land()
		Step.LANDED:
			step = Step.WAITING
			remaining = maxf(0.14, 0.58 - score * 0.024)


func _try_jump() -> void:
	if jump_time > 0.0 or jump_recovery > 0.0:
		return
	_jump_direction = Input.get_vector(&"scurry_left", &"scurry_right", &"scurry_up", &"scurry_down")
	if _jump_direction.is_zero_approx():
		_jump_direction = Vector2.from_angle(ant_angle)
	jump_time = JUMP_DURATION
	_sound.play_cue(&"jump")


func _tick_jump(delta: float) -> void:
	if jump_time > 0.0:
		jump_time = maxf(0.0, jump_time - delta)
		if jump_time <= 0.00001:
			jump_time = 0.0
			jump_recovery = JUMP_RECOVERY
	else:
		jump_recovery = maxf(0.0, jump_recovery - delta)


func _move_ant(delta: float) -> void:
	var direction := Input.get_vector(&"scurry_left", &"scurry_right", &"scurry_up", &"scurry_down")
	var speed := RUN_SPEED * BOOST_MULTIPLIER if boost_time > 0.0 else RUN_SPEED
	if jump_time > 0.0:
		direction = _jump_direction
		speed = JUMP_SPEED
	elif jump_recovery > 0.0:
		speed *= RECOVERY_MULTIPLIER
	if ant_on_snail_trail():
		speed *= SLIME_SPEED_MULTIPLIER
	var velocity := direction * speed
	if yard_event == YardEvent.WIND_GUST and event_age >= WIND_WARNING:
		velocity.x += wind_direction * WIND_SPEED
	if not velocity.is_zero_approx():
		var destination := (ant_position + velocity * delta).clamp(RUN_BOUNDS.position, RUN_BOUNDS.end)
		ant_position = destination
	moving = not direction.is_zero_approx()
	if moving:
		ant_angle = lerp_angle(ant_angle, direction.angle(), minf(1.0, delta * 18.0))
		gait = fmod(gait + delta * 24.0 * speed / RUN_SPEED, TAU)


func move_around_terrain(from: Vector2, destination: Vector2, obstacles: Array[PackedVector2Array]) -> Vector2:
	if obstacles.is_empty() or from.is_equal_approx(destination):
		return destination
	var clipped := _clip_terrain_motion(from, destination, obstacles)
	if clipped.is_equal_approx(destination):
		return clipped
	var tangent := Vector2.ZERO
	var best_distance := INF
	for polygon in obstacles:
		for index in polygon.size():
			var start := polygon[index]
			var end := polygon[(index + 1) % polygon.size()]
			var nearest := Geometry2D.get_closest_point_to_segment(clipped, start, end)
			var distance := clipped.distance_squared_to(nearest)
			if distance < best_distance:
				best_distance = distance
				tangent = (end - start).normalized()
	var slide := (clipped + tangent * (destination - clipped).dot(tangent)).clamp(RUN_BOUNDS.position, RUN_BOUNDS.end)
	var best := _clip_terrain_motion(clipped, slide, obstacles)
	var attempted := destination - from
	# At a corner, the next edge can block the slide. Try either input axis.
	for axis_target in [Vector2(destination.x, from.y), Vector2(from.x, destination.y)]:
		var candidate := _clip_terrain_motion(from, axis_target, obstacles)
		if (candidate - best).dot(attempted) > 0.0:
			best = candidate
	return best


func _clip_terrain_motion(from: Vector2, destination: Vector2, obstacles: Array[PackedVector2Array]) -> Vector2:
	if from.is_equal_approx(destination):
		return destination
	var travel := destination - from
	var limit := travel.length()
	for polygon in obstacles:
		for index in polygon.size():
			var next := (index + 1) % polygon.size()
			var crossing: Variant = Geometry2D.segment_intersects_segment(from, destination,
				polygon[index], polygon[next])
			if crossing != null:
				limit = minf(limit, maxf(0.0, from.distance_to(crossing) - 0.2))
	return from + travel.normalized() * limit


func _move_spider(delta: float) -> void:
	var target := ant_position - spider_position
	var base_speed := SPIDER_SPEED if lan.role == Lan.Role.SOLO else 105.0
	var speed := base_speed + minf(90.0, score * 4.0)
	spider_position = spider_position.move_toward(ant_position, speed * delta)
	spider_angle = lerp_angle(spider_angle, target.angle(), minf(1.0, delta * 12.0))
	spider_gait = fmod(spider_gait + delta * (12.0 + speed * 0.038), TAU)
	if lan.role != Lan.Role.SOLO:
		party.hit_near(spider_position, SPIDER_RADIUS + BODY_RADIUS)
	elif _spider_bites(spider_position, -1):
		spider_angle = target.angle()


func _spider_bites(at: Vector2, index: int) -> bool:
	var reach := SPIDER_RADIUS + BODY_RADIUS
	if jump_time > 0.0 or at.distance_squared_to(ant_position) > reach * reach or _blocks_hit():
		return false
	spider_biter = index
	_sound.play_cue(&"bite")
	_end_run(Loss.SPIDER)
	return true


func _start_yard_event(kind: YardEvent) -> void:
	yard_event = kind
	event_age = 0.0
	_sound.play_cue(&"event")
	match kind:
		YardEvent.METEORS:
			meteors_landed = 0
			_meteor_seed = _rng.randi()
			meteor_targets = _make_meteor_targets(_meteor_seed)
		YardEvent.SPIDER_RUSH:
			var top := FIELD.position.y + 42.0
			var bottom := FIELD.end.y - 42.0
			var far_y := bottom if ant_position.y < FIELD.get_center().y else top
			rush_spiders = PackedVector2Array([
				Vector2(FIELD.position.x + 18.0, far_y), Vector2(FIELD.end.x - 18.0, far_y),
			])
			rush_angles = PackedFloat32Array([0.0, PI])
		YardEvent.WIND_GUST:
			wind_direction = -1.0 if _rng.randf() < 0.5 else 1.0


static func _make_meteor_targets(seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var targets := PackedVector2Array()
	var area := FIELD.grow(-METEOR_RADIUS - 12.0)
	var cell_size := area.size / Vector2(8, 4)
	var first := rng.randi_range(0, METEOR_COUNT - 1)
	var order_direction := -1 if rng.randf() < 0.5 else 1
	var flip_x := rng.randf() < 0.5
	var flip_y := rng.randf() < 0.5
	for index in METEOR_COUNT:
		var cell: int = METEOR_GRID_ORDER[posmod(first + index * order_direction, METEOR_COUNT)]
		var column := cell % 8
		var row := floori(cell / 8.0)
		var position_in_grid := Vector2(7 - column if flip_x else column, 3 - row if flip_y else row)
		var jitter := Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-5.0, 5.0))
		targets.append(area.position + (position_in_grid + Vector2(0.5, 0.5)) * cell_size + jitter)
	return targets


func _tick_yard_event(delta: float) -> void:
	if yard_event == YardEvent.NONE:
		_event_wait -= delta
		if _event_wait <= 0.0:
			_start_yard_event(YARD_EVENTS[_rng.randi_range(0, YARD_EVENTS.size() - 1)])
		return
	event_age += delta
	match yard_event:
		YardEvent.METEORS:
			_tick_meteors()
		YardEvent.SPIDER_RUSH:
			_tick_spider_rush(delta)
		YardEvent.WIND_GUST:
			if event_age >= WIND_WARNING + WIND_DURATION:
				_finish_yard_event()


func _tick_snail(delta: float) -> void:
	if not snail_active:
		_snail_wait -= delta
		if _snail_wait <= 0.0:
			_start_snail()
		return
	snail_age += delta
	if snail_age >= SNAIL_WARNING + SNAIL_DURATION + SLIME_LIFETIME:
		snail_active = false
		_clear_snail_trail()
		_snail_wait = _snail_rng.randf_range(SNAIL_RETURN_DELAY.x, SNAIL_RETURN_DELAY.y)
	else:
		_refresh_snail_trail()


func _start_snail() -> void:
	snail_active = true
	snail_age = 0.0
	snail_direction = -1.0 if _snail_rng.randf() < 0.5 else 1.0
	snail_lane = _snail_rng.randf_range(FIELD.position.y + 120.0, FIELD.end.y - 120.0)
	_clear_snail_trail()
	_sound.play_cue(&"event")


func snail_position_at(elapsed: float) -> Vector2:
	var progress := clampf(elapsed / SNAIL_DURATION, 0.0, 1.0)
	var half_width := FIELD.size.x * 0.5 - 19.0
	var x := FIELD.get_center().x + (progress * 2.0 - 1.0) * half_width * snail_direction
	var y := snail_lane + sin(progress * TAU * 1.35) * 64.0
	return Vector2(x, y)


func _clear_snail_trail() -> void:
	snail_trail.clear()
	_slime_start = -1
	_slime_end = -1


func _refresh_snail_trail() -> void:
	var elapsed := snail_age - SNAIL_WARNING
	if elapsed < 0.0:
		return
	var first := maxi(0, ceili((elapsed - SLIME_LIFETIME) / SLIME_SAMPLE_INTERVAL))
	var last := floori(minf(elapsed, SNAIL_DURATION) / SLIME_SAMPLE_INTERVAL)
	if first == _slime_start and last == _slime_end:
		return
	_slime_start = first
	_slime_end = last
	snail_trail.clear()
	for index in range(first, last + 1):
		snail_trail.append(snail_position_at(index * SLIME_SAMPLE_INTERVAL))


func ant_on_snail_trail() -> bool:
	var ant: Party.Runner = party.runners.get(lan.local_id())
	if lan.role != Lan.Role.SOLO:
		return ant != null and on_slime(ant.at, ant.jump > 0.0)
	return on_slime(ant_position, jump_time > 0.0)


func on_slime(position: Vector2, airborne: bool) -> bool:
	if not snail_active or airborne or snail_trail.is_empty():
		return false
	var reach := SLIME_WIDTH * 0.5 + BODY_RADIUS
	var reach_squared := reach * reach
	if snail_trail.size() == 1:
		return position.distance_squared_to(snail_trail[0]) <= reach_squared
	for index in range(1, snail_trail.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(position, snail_trail[index - 1], snail_trail[index])
		if position.distance_squared_to(nearest) <= reach_squared:
			return true
	return false


func _tick_meteors() -> void:
	while meteors_landed < meteor_targets.size() and event_age >= meteor_impact_time(meteors_landed):
		var point := meteor_targets[meteors_landed]
		meteors_landed += 1
		_sound.play_cue(&"impact")
		var reach := METEOR_RADIUS + BODY_RADIUS
		if lan.role != Lan.Role.SOLO:
			party.hit_near(point, reach, &"impact")
		elif jump_time <= 0.0 and point.distance_squared_to(ant_position) <= reach * reach and not _blocks_hit():
			_end_run(Loss.METEOR)
			return
	if event_age >= METEOR_DURATION:
		_finish_yard_event()


func _tick_spider_rush(delta: float) -> void:
	if event_age >= RUSH_WARNING + RUSH_DURATION:
		_finish_yard_event()
	elif event_age >= RUSH_WARNING:
		for index in rush_spiders.size():
			var destination := ant_position
			if lan.role != Lan.Role.SOLO:
				var ant := party.nearest_live(rush_spiders[index])
				if ant != null:
					destination = ant.at
			var target := destination - rush_spiders[index]
			rush_angles[index] = lerp_angle(rush_angles[index], target.angle(), minf(1.0, delta * 12.0))
			rush_spiders[index] = rush_spiders[index].move_toward(destination, 115.0 * delta)
			if lan.role != Lan.Role.SOLO:
				party.hit_near(rush_spiders[index], SPIDER_RADIUS + BODY_RADIUS)
			elif _spider_bites(rush_spiders[index], index):
				rush_angles[index] = target.angle()
				return


func _finish_yard_event() -> void:
	yard_event = YardEvent.NONE
	meteor_targets.clear()
	meteors_landed = 0
	wind_direction = 0.0
	rush_spiders.clear()
	rush_angles.clear()
	_event_wait = _rng.randf_range(17.0, 25.0)


static func meteor_impact_time(index: int) -> float:
	return METEOR_WARNING + index * METEOR_SPACING


func _update_power(delta: float) -> void:
	if power == Power.NONE:
		_power_delay -= delta
		if _power_delay <= 0.0:
			_spawn_power()
	elif ant_position.distance_squared_to(power_position) <= PICKUP_RADIUS * PICKUP_RADIUS:
		if power == Power.SPEED:
			boost_time = BOOST_TIME
		else:
			shield_time = SHIELD_DURATION
		power = Power.NONE
		_power_delay = PICKUP_INTERVAL
		_pickup_count += 1
		_sound.play_cue(&"pickup")


func _spawn_power() -> void:
	var area := RUN_BOUNDS.grow(-36.0)
	var safest_distance := -1.0
	for attempt in 8:
		var point := Vector2(_rng.randf_range(area.position.x, area.end.x),
			_rng.randf_range(area.position.y, area.end.y))
		var distance := minf(point.distance_squared_to(ant_position), point.distance_squared_to(spider_position))
		if distance > safest_distance:
			safest_distance = distance
			power_position = point
		if distance >= 125.0 * 125.0:
			break
	power = Power.SPEED if shield_time > 0.0 else _next_power
	_next_power = Power.SHIELD if power == Power.SPEED else Power.SPEED


func _blocks_hit() -> bool:
	if shield_grace > 0.0:
		return true
	if shield_time <= 0.0:
		return false
	shield_grace = minf(SHIELD_GRACE, shield_time)
	shield_time = 0.0
	_sound.play_cue(&"shield")
	return true


func _warn(direction: Vector2) -> void:
	step = Step.WARNING
	warning_duration = maxf(0.47, 1.30 - score * 0.051)
	remaining = warning_duration
	var lead := minf(80.0, score * 6.0)
	shadow_position = (ant_position + direction * lead).clamp(FIELD.position + Vector2.ONE * 45, FIELD.end - Vector2.ONE * 45)
	shoe_angle = _rng.randf_range(-0.75, 0.75)
	if _rng.randf() < 0.5:
		shoe_angle += PI
	_begin_warning()


func _begin_warning() -> void:
	landing_shape = footprint(shadow_position, shoe_angle, stomp_scale)
	_sound.play_cue(&"warning")
	_interface.refresh()


func _land() -> void:
	step = Step.LANDED
	landed_duration = maxf(0.33, 0.56 - score * 0.013)
	remaining = landed_duration
	impact_age = 0.0
	_sound.play_cue(&"impact")
	stomp_blocked = false
	var under_shoe := _ant_in_shadow()
	stomp_evaded = under_shoe and jump_time > 0.0
	if under_shoe and not stomp_evaded:
		if _blocks_hit():
			stomp_blocked = true
			return
		_end_run(Loss.SHOE)
		return
	score += 1
	if lan.role == Lan.Role.SOLO and score > best:
		best = score
		var scores := ConfigFile.new()
		scores.set_value("scores", "best", best)
		scores.save(SCORE_PATH)
	_sound.play_cue(&"dodge")
	_interface.refresh()


func _end_run(reason: Loss) -> void:
	loss = reason
	moving = false
	mode = Mode.LOST
	lost_delay = LOSS_DELAY
	_interface.refresh()


static func footprint(center: Vector2, angle: float, scale_factor: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in SOLE:
		points.append(center + (point * scale_factor).rotated(angle))
	return points


static func crater_rim(center := Vector2.ZERO, scale_factor := 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SOLE.size():
		var edge: Vector2 = SOLE[index]
		var rubble := 9.0 if index % 3 == 0 else 5.0
		points.append(center + (edge + edge.normalized() * rubble) * scale_factor)
	return points


func _ant_in_shadow() -> bool:
	return ant_in_footprint(ant_position, landing_shape)


static func ant_in_footprint(position: Vector2, polygon: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(position, polygon):
		return true
	for index in polygon.size():
		var next := (index + 1) % polygon.size()
		var edge := Geometry2D.get_closest_point_to_segment(position, polygon[index], polygon[next])
		if position.distance_squared_to(edge) <= BODY_RADIUS * BODY_RADIUS:
			return true
	return false


func _lan_changed() -> void:
	mode = Mode.TITLE
	score = 0
	loss = Loss.NONE
	party.runners.clear()
	party.shoes.clear()
	_interface.refresh()


func _lobby_changed() -> void:
	if not lan.in_round:
		mode = Mode.TITLE
		party.runners.clear()
		party.shoes.clear()
	_interface.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target := get_global_mouse_position()
		var shoe: Party.Shoe = party.shoes.get(lan.local_id())
		if shoe != null and mode == Mode.RUNNING and FIELD.has_point(target):
			lan.request_stomp(target)


func _over_shoe_pickup(target: Vector2) -> bool:
	return shoe_pickup != ShoePower.NONE and target.distance_squared_to(shoe_pickup_position) <= SHOE_PICKUP_RADIUS * SHOE_PICKUP_RADIUS


func _publish_snapshot() -> void:
	lan.publish({
		"mode": mode, "score": score, "lost_delay": lost_delay, "party": party.snapshot(),
		"shoe_pickup": shoe_pickup, "shoe_pickup_position": shoe_pickup_position,
		"spider": spider_position, "spider_angle": spider_angle, "spider_gait": spider_gait,
		"power": power, "power_position": power_position,
		"yard_event": yard_event, "event_age": event_age, "wind_direction": wind_direction,
		"meteor_seed": _meteor_seed,
		"snail_active": snail_active, "snail_age": snail_age, "snail_direction": snail_direction, "snail_lane": snail_lane,
		"meteors_landed": meteors_landed, "rush_spiders": rush_spiders, "rush_angles": rush_angles,
	})

func _apply_snapshot(state: Dictionary) -> void:
	if not state.has("party"):
		lan.leave("Both players need the latest build.")
		return
	var previous_event := yard_event
	var previous_snail := snail_active
	var previous_meteors := meteors_landed
	var previous_mode := mode
	var card_was_hidden := lost_delay > 0.0
	mode = state.mode
	score = state.score
	lost_delay = state.lost_delay
	party.apply_snapshot(state.party)
	shoe_pickup = state.shoe_pickup
	shoe_pickup_position = state.shoe_pickup_position
	spider_position = state.spider
	spider_angle = state.spider_angle
	spider_gait = state.spider_gait
	yard_event = state.yard_event
	event_age = state.event_age
	wind_direction = state.wind_direction
	# A shared seed keeps the full meteor pattern out of the periodic LAN snapshots.
	if yard_event == YardEvent.METEORS:
		if previous_event != YardEvent.METEORS or _meteor_seed != state.meteor_seed:
			_meteor_seed = state.meteor_seed
			meteor_targets = _make_meteor_targets(_meteor_seed)
	elif previous_event == YardEvent.METEORS:
		meteor_targets.clear()
	meteors_landed = state.meteors_landed
	snail_active = state.snail_active
	if snail_active:
		if not previous_snail or snail_direction != state.snail_direction or snail_lane != state.snail_lane or state.snail_age < snail_age:
			_clear_snail_trail()
		snail_age = state.snail_age
		snail_direction = state.snail_direction
		snail_lane = state.snail_lane
		_refresh_snail_trail()
	elif previous_snail:
		_clear_snail_trail()
	rush_spiders = state.rush_spiders
	rush_angles = state.rush_angles
	if (yard_event != YardEvent.NONE and yard_event != previous_event) or (snail_active and not previous_snail):
		_sound.play_cue(&"event")
	if yard_event == YardEvent.METEORS and meteors_landed > previous_meteors:
		_sound.play_cue(&"impact")
	power = state.power
	power_position = state.power_position
	if previous_mode != mode or (card_was_hidden and lost_delay <= 0.0):
		_interface.refresh()
	_actors.queue_redraw()
	_interface.queue_redraw()
