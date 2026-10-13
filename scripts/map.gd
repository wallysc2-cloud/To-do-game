## The mission map: rooms in columns from your camp on the left to the boss on the right.
## Tap a glowing room to see what it is, then tap Go (or tap it again) to head in.
extends Control

const Data = preload("res://scripts/data.gd")
const Mission = preload("res://scripts/mission.gd")

signal picked(layer: int, index: int)
signal retreat_pressed

const ROOM_COLORS := {
	"battle": Color(0.85, 0.4, 0.35), "elite": Color(0.95, 0.3, 0.55), "treasure": Color(1.0, 0.8, 0.3),
	"shrine": Color(0.45, 0.9, 0.55), "crystal": Color(0.45, 0.75, 1.0), "boss": Color(1.0, 0.6, 0.2),
}

var m: Dictionary
var profile: RefCounted
var spots := {}       # [layer, index] -> position on screen
var chosen := []      # the room you tapped, waiting for Go
var info: Label
var go_button: Button
var font: Font = ThemeDB.fallback_font


func setup(mission: Dictionary, p: RefCounted) -> void:
	m = mission
	profile = p
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	add_child(info)
	go_button = Button.new()
	go_button.text = "Go"
	go_button.add_theme_font_size_override("font_size", 26)
	go_button.pressed.connect(func(): if not chosen.is_empty(): picked.emit(chosen[0], chosen[1]))
	add_child(go_button)
	var back := Button.new()
	back.text = "Retreat"
	back.add_theme_font_size_override("font_size", 20)
	back.position = Vector2(14, 10)
	back.custom_minimum_size = Vector2(120, 52)
	back.pressed.connect(func(): retreat_pressed.emit())
	add_child(back)
	resized.connect(_layout)
	_layout()
	_update_info()


func _layout() -> void:
	var w := size.x if size.x > 0.0 else 1280.0
	var h := size.y if size.y > 0.0 else 720.0
	var cols: int = m["layers"].size() + 1
	var left := 90.0
	var step := (w - 2.0 * left) / (cols - 1)
	var top := 120.0
	var bottom := h - 210.0
	spots = {}
	spots[[-1, 0]] = Vector2(left, (top + bottom) / 2.0)
	for i in m["layers"].size():
		var layer: Array = m["layers"][i]
		for j in layer.size():
			spots[[i, j]] = Vector2(left + step * (i + 1), top + (bottom - top) * (j + 0.5) / layer.size())
	info.position = Vector2(24, h - 112)
	info.size = Vector2(w - 260, 100)
	go_button.position = Vector2(w - 220, h - 104)
	go_button.size = Vector2(196, 80)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for c in Mission.choices(m):
			if spots[c].distance_to(event.position) < 70.0:
				accept_event()
				tap_room(c)
				return


func tap_room(c: Array) -> void:
	if chosen == c:
		picked.emit(c[0], c[1])
		return
	chosen = c
	_update_info()


func _update_info() -> void:
	go_button.disabled = chosen.is_empty()
	if chosen.is_empty():
		info.text = "Tap a glowing room to choose your way. Your squad's wounds carry over from room to room."
		return
	var kind: String = Mission.room(m, chosen[0], chosen[1])["kind"]
	var rk: Dictionary = Data.ROOM_KINDS[kind]
	info.text = "%s: %s" % [rk["name"], rk["text"]]


func _draw() -> void:
	var w := size.x
	var t := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.14))
	draw_string(font, Vector2(150, 46), "Mission %d" % m["level"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	var gold_line := "Gold found %d" % m["gold"]
	if int(m["crystal"]) > 0:
		gold_line += "    +%d Focus next battle" % m["crystal"]
	draw_string(font, Vector2(150, 80), gold_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.85, 0.35))
	_draw_squad(Vector2(w - 24, 14))

	var path: Array = m.get("path", [])
	var options := Mission.choices(m)
	# Paths between rooms.
	var starts := [[-1, 0]]
	for j in m["layers"][0].size():
		_line(spots[[-1, 0]], spots[[0, j]], path.has([0, j]))
	for i in m["layers"].size():
		for j in m["layers"][i].size():
			for k in m["layers"][i][j]["links"]:
				var walked := path.has([i, j]) and path.has([i + 1, int(k)])
				_line(spots[[i, j]], spots[[i + 1, int(k)]], walked)
	# Camp.
	var camp: Vector2 = spots[starts[0]]
	draw_colored_polygon(PackedVector2Array([camp + Vector2(-30, 24), camp + Vector2(0, -28), camp + Vector2(30, 24)]), Color(0.6, 0.45, 0.3))
	draw_string(font, camp + Vector2(-60, 56), "Camp", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 1, 1, 0.6))
	# Rooms.
	for i in m["layers"].size():
		for j in m["layers"][i].size():
			var c := [i, j]
			var kind: String = m["layers"][i][j]["kind"]
			var p: Vector2 = spots[c]
			var boss := kind == "boss"
			var r := 46.0 if boss else 34.0
			var col: Color = ROOM_COLORS[kind]
			var open := options.has(c)
			var visited := path.has(c)
			if not open and not visited:
				col = col.darkened(0.55)
			if open:
				draw_circle(p, r + 10 + 4 * sin(t * 4.0), Color(col, 0.25))
			if chosen == c:
				draw_arc(p, r + 14, 0, TAU, 32, Color(1, 1, 1), 4)
			draw_circle(p, r + 3, Color(0, 0, 0, 0.6))
			draw_circle(p, r, col if not visited else col.darkened(0.3))
			_icon(kind, p, r)
			if visited:
				draw_line(p + Vector2(-14, 2), p + Vector2(-3, 13), Color.WHITE, 5)
				draw_line(p + Vector2(-3, 13), p + Vector2(16, -12), Color.WHITE, 5)
			draw_string(font, p + Vector2(-70, r + 26), Data.ROOM_KINDS[kind]["name"], HORIZONTAL_ALIGNMENT_CENTER, 140, 17, Color(1, 1, 1, 0.75 if open else 0.4))
	# Your squad's banner where you are.
	var here: Vector2 = spots[[int(m["at"][0]), int(m["at"][1])]]
	draw_line(here + Vector2(0, -40), here + Vector2(0, -78), Color(0.9, 0.9, 0.9), 3)
	draw_colored_polygon(PackedVector2Array([here + Vector2(0, -78), here + Vector2(28, -70), here + Vector2(0, -60)]), Color(0.4, 0.65, 1.0))


func _line(a: Vector2, b: Vector2, walked: bool) -> void:
	draw_line(a, b, Color(1, 0.9, 0.6, 0.9) if walked else Color(1, 1, 1, 0.18), 6.0 if walked else 3.0)


func _icon(kind: String, p: Vector2, r: float) -> void:
	var ink := Color(0.1, 0.08, 0.1, 0.85)
	match kind:
		"battle", "elite":
			draw_line(p + Vector2(-r * 0.5, -r * 0.5), p + Vector2(r * 0.5, r * 0.5), ink, 5)
			draw_line(p + Vector2(r * 0.5, -r * 0.5), p + Vector2(-r * 0.5, r * 0.5), ink, 5)
			if kind == "elite":
				draw_arc(p, r * 0.8, 0, TAU, 24, ink, 3)
		"treasure":
			draw_rect(Rect2(p + Vector2(-r * 0.55, -r * 0.3), Vector2(r * 1.1, r * 0.75)), ink, false, 4)
			draw_line(p + Vector2(-r * 0.55, 0), p + Vector2(r * 0.55, 0), ink, 3)
		"shrine":
			draw_rect(Rect2(p + Vector2(-r * 0.15, -r * 0.55), Vector2(r * 0.3, r * 1.1)), ink)
			draw_rect(Rect2(p + Vector2(-r * 0.55, -r * 0.15), Vector2(r * 1.1, r * 0.3)), ink)
		"crystal":
			var s := r * 0.5
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s * 1.3), p + Vector2(s, 0), p + Vector2(0, s * 1.3), p + Vector2(-s, 0)]), ink)
		"boss":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.55, r * 0.3), p + Vector2(-r * 0.55, -r * 0.35), p + Vector2(-r * 0.25, -r * 0.05), p + Vector2(0, -r * 0.5), p + Vector2(r * 0.25, -r * 0.05), p + Vector2(r * 0.55, -r * 0.35), p + Vector2(r * 0.55, r * 0.3)]), ink)


## Each hero's health in the top-right corner.
func _draw_squad(top_right: Vector2) -> void:
	var x := top_right.x - 3 * 190.0
	for kind in Data.HERO_ORDER:
		var st: Dictionary = profile.hero_stats(kind)
		var hp := int(m["hp"].get(kind, 0))
		var col: Color = Data.HEROES[kind]["color"]
		draw_circle(Vector2(x + 18, top_right.y + 30), 16, col if hp > 0 else Color(0.3, 0.3, 0.3))
		draw_string(font, Vector2(x + 42, top_right.y + 26), Data.HEROES[kind]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		var bar := Rect2(x + 42, top_right.y + 36, 120, 10)
		draw_rect(bar.grow(2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(120.0 * clampf(float(hp) / st["hp"], 0, 1), 10)), Color(0.35, 0.85, 0.4))
		draw_string(font, Vector2(x + 42, top_right.y + 70), ("%d / %d" % [hp, st["hp"]]) if hp > 0 else "Down", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.7))
		x += 190.0
