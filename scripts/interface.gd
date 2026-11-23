extends Control

const Game = preload("res://scripts/game.gd")
const Lan = preload("res://scripts/lan.gd")
const Actors = preload("res://scripts/actors.gd")
const INK := Color("20382a")
const CREAM := Color("fff1cc")
const MOSS := Color("c3d3a2")
const GOLD := Color("ffd681")
const CARD := Rect2(308, 179, 536, 376)

@onready var _game: Game = get_parent()
var _font := ThemeDB.fallback_font
var _bold := FontVariation.new()
var _button: Button
var _pause: Button
var _sound: Button
var _host: Button
var _join: Button
var _leave: Button
var _address: LineEdit
var _ant_choice: Button
var _shoe_choice: Button
var _ready_button: Button


func _ready() -> void:
	_bold.base_font = _font
	_bold.variation_embolden = 0.78
	_button = _make_button(Rect2(461, 427, 230, 55), true)
	_button.pressed.connect(_game.primary_action)
	_sound = _make_button(Rect2(944, 31, 77, 39))
	_sound.pressed.connect(_game.toggle_sound)
	_pause = _make_button(Rect2(1032, 31, 82, 39))
	_pause.pressed.connect(_game.toggle_pause)
	_sound.tooltip_text = "Toggle sound (M)"
	_pause.tooltip_text = "Pause or resume (Esc)"
	_host = _make_button(Rect2(586, 382, 156, 45))
	_host.text = "Host LAN"
	_host.pressed.connect(func(): _game.lan.host())
	_join = _make_button(Rect2(635, 445, 107, 42))
	_join.text = "Join LAN"
	_join.pressed.connect(func(): _game.lan.join(_address.text))
	_leave = _make_button(Rect2(1032, 31, 82, 39))
	_leave.text = "Leave"
	_leave.pressed.connect(func(): _game.lan.leave())
	_address = LineEdit.new()
	_address.position = Vector2(410, 445)
	_address.size = Vector2(215, 42)
	_address.placeholder_text = "Host IP address"
	_address.max_length = 15
	_address.add_theme_color_override("font_color", INK)
	_address.add_theme_color_override("font_placeholder_color", Color("51623d"))
	var field_style := _box(Color("fff8de"), 8, Color("a98959"), 1)
	field_style.content_margin_left = 12.0
	_address.add_theme_stylebox_override("normal", field_style)
	_address.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 8, INK, 2))
	_address.text_submitted.connect(func(value): _game.lan.join(value))
	add_child(_address)
	_ant_choice = _make_button(Rect2(354, 431, 135, 46))
	_ant_choice.text = "Ant"
	_ant_choice.toggle_mode = true
	_ant_choice.pressed.connect(func(): _game.lan.choose(Lan.Choice.ANT))
	_shoe_choice = _make_button(Rect2(508, 431, 135, 46))
	_shoe_choice.text = "Shoe"
	_shoe_choice.toggle_mode = true
	_shoe_choice.pressed.connect(func(): _game.lan.choose(Lan.Choice.SHOE))
	_ready_button = _make_button(Rect2(662, 431, 135, 46), true)
	_ready_button.pressed.connect(func(): _game.lan.toggle_ready())


func refresh() -> void:
	var solo := _game.lan.role == Lan.Role.SOLO
	var title := _game.mode == Game.Mode.TITLE
	var menu := title and solo
	_host.visible = menu
	_join.visible = menu
	_address.visible = menu
	_leave.visible = not solo
	_button.visible = _card_visible() and (solo or (_game.lan.role == Lan.Role.HOST and not title))
	var id := _game.lan.local_id()
	var can_ballot := title and not solo and _game.lan.players.has(id)
	_ant_choice.visible = can_ballot
	_shoe_choice.visible = can_ballot
	_ready_button.visible = can_ballot
	var chosen := _game.lan.choice(id)
	_ant_choice.set_pressed_no_signal(chosen == Lan.Choice.ANT)
	_shoe_choice.set_pressed_no_signal(chosen == Lan.Choice.SHOE)
	_ready_button.disabled = chosen == Lan.Choice.NONE
	_ready_button.text = "Unready" if _game.lan.ready(id) else "Ready"
	_button.position = Vector2(410, 382) if menu else Vector2(461, 427)
	_button.size = Vector2(156, 45) if menu else Vector2(230, 55)
	_pause.visible = solo and (_game.mode == Game.Mode.RUNNING or _game.mode == Game.Mode.PAUSED)
	_pause.text = "Resume" if _game.mode == Game.Mode.PAUSED else "Pause"
	_sound.text = "Muted" if _game.sound_is_muted() else "Sound"
	match _game.mode:
		Game.Mode.TITLE:
			_button.text = "Play solo"
		Game.Mode.PAUSED:
			_button.text = "Keep scurrying"
		Game.Mode.LOST:
			_button.text = "Try again" if solo else "Back to lobby"
	queue_redraw()


func _draw() -> void:
	_draw_hud()
	_draw_controls()
	if _card_visible():
		_draw_card()


func _card_visible() -> bool:
	return _game.mode == Game.Mode.TITLE or _game.mode == Game.Mode.PAUSED or (
		_game.mode == Game.Mode.LOST and _game.lost_delay <= 0.0)


func _draw_hud() -> void:
	_pill(Rect2(38, 29, 45, 45), Color("324e34"), 13)
	Actors.draw_ant(self, Vector2(60, 51), -0.55, Vector2.ONE * 0.6, 0.0, _game.clock, false)
	_text(Vector2(97, 59), "STOMP & SCURRY", 22, CREAM, _bold)

	_draw_counter(Vector2(435, 27), "DODGED", _game.score, GOLD)
	if _game.lan.role == Lan.Role.SOLO:
		_draw_counter(Vector2(560, 27), "BEST", _game.best, CREAM)
	else:
		if _game.mode != Game.Mode.TITLE:
			_draw_counter(Vector2(537, 27), "LIVE ANTS", _game.party.living_count(), CREAM)
	if _game.mode == Game.Mode.RUNNING:
		if _game.yard_event == Game.YardEvent.METEORS:
			_text(Vector2(97, 80), "METEOR SHOWER", 12, Color("ffae82"), _bold)
		elif _game.yard_event == Game.YardEvent.SPIDER_RUSH:
			var event_text := "SPIDER RUSH" if _game.event_age >= Game.RUSH_WARNING else "SPIDERS INCOMING"
			_text(Vector2(97, 80), event_text, 12, Color("e5c6ff"), _bold)
		elif _game.yard_event == Game.YardEvent.WIND_GUST:
			var side := "LEFT" if _game.wind_direction < 0.0 else "RIGHT"
			var event_text := "WIND INCOMING " if _game.event_age < Game.WIND_WARNING else "WIND PUSHES "
			_text(Vector2(97, 80), event_text + side, 12, Actors.WIND_COLOR, _bold)
		if _game.snail_active:
			var snail_text := "SNAIL INCOMING" if _game.snail_age < Game.SNAIL_WARNING else "SNAIL TRAIL"
			if _game.ant_on_snail_trail():
				snail_text = "SLOWED BY SLIME"
			_text(Vector2(97, 27), snail_text, 12, Actors.SLIME_COLOR, _bold)
		if _game.lan.role != Lan.Role.SOLO:
			_draw_party_hud()
			return
		var warning := _game.step == Game.Step.WARNING
		if warning:
			var warning_text := "STOMP INCOMING"
			if _game.stomp_power != Game.ShoePower.NONE:
				warning_text = _shoe_power_name(_game.stomp_power) + " INCOMING"
			_text(Vector2(699, 43), warning_text, 12, GOLD, _bold)
			var progress := clampf(_game.remaining / _game.warning_duration, 0.0, 1.0)
			_pill(Rect2(699, 54, 158, 7), Color("35513a"), 4)
			if progress > 0.015:
				_pill(Rect2(699, 54, 158 * progress, 7), GOLD, 4)
		elif _game.step == Game.Step.LANDED:
			var outcome := "DODGED!"
			if _game.stomp_blocked:
				outcome = "SHIELD BLOCK!"
			elif _game.stomp_evaded:
				outcome = "JUMP DODGE!"
			_text(Vector2(699, 53), outcome, 16, MOSS, _bold)
		if _game.boost_time > 0.0:
			_text(Vector2(253, 80), "SPEED  %ds" % ceili(_game.boost_time), 13, Actors.SPEED_COLOR, _bold)
		if _game.shield_time > 0.0:
			_text(Vector2(355, 80), "SHIELD  %ds" % ceili(_game.shield_time), 13, Actors.SHIELD_COLOR, _bold)
		if _game.jump_recovery > 0.0:
			_text(Vector2(445, 80), "RECOVERING  %.1fs" % _game.jump_recovery, 12, GOLD, _bold)



func _draw_party_hud() -> void:
	var id := _game.lan.local_id()
	var shoe: Game.Party.Shoe = _game.party.shoes.get(id)
	var ant: Game.Party.Runner = _game.party.runners.get(id)
	if shoe != null:
		_text(Vector2(681, 40), "YOU ARE THE SHOE", 14, CREAM, _bold)
		if shoe.step == Game.Step.WARNING:
			var title := "STOMP INCOMING" if shoe.power == Game.ShoePower.NONE else _shoe_power_name(shoe.power) + " INCOMING"
			_text(Vector2(681, 64), title, 13, GOLD, _bold)
		elif _game.party.ready_to_stomp(shoe):
			_text(Vector2(681, 64), "READY TO STOMP", 13, GOLD, _bold)
		else:
			_text(Vector2(681, 64), "SHOE RECOVERING", 13, MOSS, _bold)
		if shoe.charge != Game.ShoePower.NONE:
			_text(Vector2(681, 81), "NEXT: " + _shoe_power_name(shoe.charge), 12,
				Actors.shoe_power_color(shoe.charge), _bold)
		elif _game.shoe_pickup != Game.ShoePower.NONE:
			_text(Vector2(681, 81), "CLICK THE DIAMOND TO CHARGE", 12, MOSS, _bold)
	elif ant != null:
		var caption := "YOU ARE A ZOMBIE" if ant.zombie else "YOU ARE AN ANT"
		_text(Vector2(681, 53), caption, 14, CREAM, _bold)
		if ant.boost > 0.0:
			_text(Vector2(253, 80), "SPEED  %ds" % ceili(ant.boost), 13, Actors.SPEED_COLOR, _bold)
		if ant.shield > 0.0:
			_text(Vector2(355, 80), "SHIELD  %ds" % ceili(ant.shield), 13, Actors.SHIELD_COLOR, _bold)
		if ant.recovery > 0.0:
			_text(Vector2(445, 80), "RECOVERING  %.1fs" % ant.recovery, 12, GOLD, _bold)


func _shoe_power_name(kind: Game.ShoePower) -> String:
	match kind:
		Game.ShoePower.QUICK:
			return "QUICK STOMP"
		Game.ShoePower.WIDE:
			return "WIDE STOMP"
		_:
			return "CRATER STOMP"


func _draw_counter(at: Vector2, title: String, number: int, color: Color) -> void:
	_text(at + Vector2(0, 11), title, 11, MOSS, _bold)
	_text(at + Vector2(0, 44), "%02d" % number, 33, color, _bold)


func _draw_controls() -> void:
	if _game.party.shoes.has(_game.lan.local_id()):
		_keycap(Rect2(39, 659, 88, 30), "Left click")
		_text(Vector2(139, 679), "Aim and click to stomp or collect a shoe pickup", 15, CREAM)
		return
	_keycap(Rect2(39, 659, 70, 30), "W A S D")
	_keycap(Rect2(117, 659, 70, 30), "Arrows")
	_text(Vector2(199, 679), "Move", 15, CREAM)
	var ant: Game.Party.Runner = _game.party.runners.get(_game.lan.local_id())
	if ant != null and ant.zombie:
		_text(Vector2(265, 679), "Catch live ants by touching them", 15, CREAM)
		return
	_keycap(Rect2(265, 659, 55, 30), "Space")
	_text(Vector2(330, 679), "Jump", 15, CREAM)
	if _game.lan.role == Lan.Role.SOLO:
		_keycap(Rect2(396, 659, 40, 30), "Esc")
		_text(Vector2(448, 679), "Pause", 15, CREAM)
	draw_circle(Vector2(1106, 674), 4.5, GOLD, true, -1.0, true)
	var tip := "Pick up lightning for speed or a shield to block a hit."
	var width := _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_text(Vector2(1092 - width, 679), tip, 15, MOSS)


func _draw_card() -> void:
	draw_rect(Game.FIELD, Color(0.09, 0.18, 0.10, 0.23))
	_pill(Rect2(CARD.position + Vector2(0, 10), CARD.size), Color(0.09, 0.15, 0.11, 0.47), 30)
	draw_style_box(_box(Color("ffefc7"), 28, Color("735c35"), 2), CARD)
	draw_style_box(_box(Color.TRANSPARENT, 22, Color("dfcd9f"), 1), CARD.grow(-9.0))
	if _game.lan.role != Lan.Role.SOLO and _game.mode == Game.Mode.TITLE:
		_draw_lobby()
		return
	draw_circle(Vector2(576, 250), 44, Color("eadca7"), true, -1.0, true)
	draw_circle(Vector2(576, 250), 38, Color("f4e5b6"), true, -1.0, true)
	Actors.draw_ant(self, Vector2(576, 251), -0.53, Vector2.ONE * 1.14, 0.0, _game.clock, _game.loss == Game.Loss.SHOE or _game.loss == Game.Loss.METEOR)

	match _game.mode:
		Game.Mode.TITLE:
			_center(349, "Stomp & Scurry", 55, INK, _bold)
			_center(520, _game.lan.status, 14, Color("5d6848"), _bold)
		Game.Mode.PAUSED:
			_center(363, "Paused", 56, INK, _bold)
			_center(397, "The shoe can wait.", 21, Color("51623d"), _font)
			_center(515, "Press Esc to resume", 14, Color("5d6848"), _bold)
		Game.Mode.LOST:
			var headline := "Squished!"
			if _game.lan.role != Lan.Role.SOLO:
				headline = "All ants turned!"
			elif _game.loss == Game.Loss.SPIDER:
				headline = "Spider snack!"
			elif _game.loss == Game.Loss.METEOR:
				headline = "Meteor strike!"
			_center(363, headline, 56, INK, _bold)
			if _game.lan.role == Lan.Role.SOLO:
				_center(397, "%d dodged  ·  Best %d" % [_game.score, _game.best], 21, Color("51623d"), _font)
				_center(515, "Press Space or Enter", 14, Color("5d6848"), _bold)
			else:
				_center(397, "%d stomps dodged" % _game.score, 21, Color("51623d"), _font)
				if _game.lan.role == Lan.Role.GUEST:
					_center(467, "Waiting for the host to reopen the lobby.", 15, INK, _bold)


func _draw_lobby() -> void:
	var local := _game.lan.local_id()
	_center(230, "LAN lobby", 35, INK, _bold)
	if _game.lan.role == Lan.Role.HOST:
		var address := _game.lan.address
		var address_size := 12 if address.length() > 56 else 15
		_center(254, address, address_size, Color("51623d"), _font)
	else:
		_center(254, "%d of %d players" % [_game.lan.players.size(), Lan.MAX_PLAYERS], 15, Color("51623d"), _font)
	var ids := _game.lan.players.keys()
	ids.sort()
	for index in ids.size():
		var id: int = ids[index]
		var y := 289.0 + index * 31.0
		var color: Color = Actors.PLAYER_COLORS[index]
		draw_circle(Vector2(360, y - 5), 5.5, color.darkened(0.25), true, -1.0, true)
		var who := _game.lan.player_name(id)
		if id == local:
			who += " (you)"
		draw_string(_bold, Vector2(377, y), who, HORIZONTAL_ALIGNMENT_LEFT, 155, 15, INK)
		var role_name := "Ant" if _game.lan.choice(id) == Lan.Choice.ANT else "Shoe" if _game.lan.choice(id) == Lan.Choice.SHOE else "Picking a role"
		_text(Vector2(540, y), role_name, 15, INK)
		_text(Vector2(697, y), "Ready" if _game.lan.ready(id) else "Waiting", 15, INK)
	var hint := _game.lan.status
	if hint.is_empty():
		hint = "At least one ant and one shoe. The round starts when everyone is ready."
	_center(511, hint, 13, Color("51623d"), _bold)


func _make_button(area: Rect2, primary := false) -> Button:
	var button := Button.new()
	button.position = area.position
	button.size = area.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _bold)
	button.add_theme_font_size_override("font_size", 19 if primary else 14)
	var radius := 15 if primary else 10
	var base := Color("e9a54e") if primary else Color("2b4534")
	var border := Color("a96833") if primary else Color("4b6747")
	button.add_theme_stylebox_override("normal", _box(base, radius, border, 1))
	button.add_theme_stylebox_override("hover", _box(base.lightened(0.14), radius, border, 1))
	button.add_theme_stylebox_override("pressed", _box(base.darkened(0.12), radius, border, 1))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, radius, Color("899a53") if primary else GOLD, 2))
	var text_color := Color("352e24") if primary else CREAM
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, text_color)
	add_child(button)
	return button


func _text(at: Vector2, content: String, font_size: int, color: Color, font: Font = null) -> void:
	draw_string(_font if font == null else font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center(y: float, content: String, font_size: int, color: Color, font: Font) -> void:
	var width := font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(Vector2(576.0 - width * 0.5, y), content, font_size, color, font)


func _keycap(area: Rect2, caption: String) -> void:
	draw_style_box(_box(Color("2b4534"), 7, Color("50684c"), 1), area)
	var width := _bold.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(Vector2(area.get_center().x - width * 0.5, area.position.y + 20), caption, 12, CREAM, _bold)


func _pill(area: Rect2, color: Color, radius: int) -> void:
	draw_style_box(_box(color, radius), area)


func _box(color: Color, radius: int, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(width)
	return style
