extends Control

const INK := Color("20382a")
const CREAM := Color("fff1cc")
const FIELD := Rect2(38, 105, 1076, 525)
const CARD := Rect2(308, 179, 536, 376)

var player_name: LineEdit
var address: LineEdit
var solo: Button
var host: Button
var join: Button
var status: Label
var _bold := FontVariation.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(1152, 720)
	_bold.base_font = ThemeDB.fallback_font
	_bold.variation_embolden = 0.78

	player_name = _field(Rect2(410, 301, 332, 42), "Player name (optional)", 20)
	solo = make_button(Rect2(410, 358, 156, 45), "Play solo", true)
	host = make_button(Rect2(586, 358, 156, 45), "Host LAN")
	add_child(solo)
	add_child(host)
	address = _field(Rect2(410, 417, 215, 42), "Host IPv4 address", 15)
	join = make_button(Rect2(635, 417, 107, 42), "Join LAN")
	add_child(join)

	status = Label.new()
	status.position = Vector2(338, 476)
	status.size = Vector2(476, 53)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", INK)
	status.add_theme_font_size_override("font_size", 15)
	add_child(status)


static func make_button(area: Rect2, caption: String, primary := false) -> Button:
	var button := Button.new()
	button.position = area.position
	button.size = area.size
	button.text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 19 if primary else 16)
	var base := Color("e9a54e") if primary else Color("2b4534")
	var border := Color("a96833") if primary else Color("4b6747")
	button.add_theme_stylebox_override("normal", _box(base, 10, border, 1))
	button.add_theme_stylebox_override("hover", _box(base.lightened(0.14), 10, border, 1))
	button.add_theme_stylebox_override("pressed", _box(base.darkened(0.12), 10, border, 1))
	button.add_theme_stylebox_override("disabled", _box(Color("d4c4a2"), 10))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 10, Color("899a53"), 2))
	var color := Color("352e24") if primary else CREAM
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, color)
	return button


func _field(area: Rect2, hint: String, limit: int) -> LineEdit:
	var field := LineEdit.new()
	field.position = area.position
	field.size = area.size
	field.placeholder_text = hint
	field.max_length = limit
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", Color("51623d"))
	field.add_theme_color_override("caret_color", INK)
	var style := _box(Color("fff8de"), 8, Color("a98959"), 1)
	style.content_margin_left = 12.0
	field.add_theme_stylebox_override("normal", style)
	field.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, 8, INK, 2))
	add_child(field)
	return field


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("162e25"))
	draw_style_box(_box(Color("243d2b"), 18), FIELD.grow(10))
	draw_style_box(_box(Color("385138"), 11), FIELD.grow(4))
	draw_polygon(PackedVector2Array([FIELD.position, Vector2(FIELD.end.x, FIELD.position.y),
		FIELD.end, Vector2(FIELD.position.x, FIELD.end.y)]), PackedColorArray([
		Color("97b862"), Color("79a64f"), Color("649247"), Color("8aaf55")
	]))
	var grass := RandomNumberGenerator.new()
	grass.seed = 38429
	for blade in 780:
		var at := Vector2(grass.randf_range(45, 1107), grass.randf_range(114, 623))
		var shade := Color("709b50") if blade % 2 == 0 else Color("92b565")
		draw_line(at, at + Vector2(grass.randf_range(-4, 3), -grass.randf_range(2, 9)), shade, 1.2, true)
	draw_rect(FIELD, Color(0.09, 0.18, 0.10, 0.23))
	draw_style_box(_box(Color(0.09, 0.15, 0.11, 0.47), 30), Rect2(CARD.position + Vector2(0, 10), CARD.size))
	draw_style_box(_box(Color("ffefc7"), 28, Color("735c35"), 2), CARD)
	draw_style_box(_box(Color.TRANSPARENT, 22, Color("dfcd9f"), 1), CARD.grow(-9))
	draw_string(_bold, Vector2(38, 59), "STOMP & SCURRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, CREAM)
	draw_string(_bold, Vector2(308, 267), "Stomp & Scurry", HORIZONTAL_ALIGNMENT_CENTER, 536, 55, INK)


static func _box(color: Color, radius: int, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(width)
	return style
