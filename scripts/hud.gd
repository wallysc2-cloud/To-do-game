## On-screen controls and status, drawn on top of the game in screen space.
## Left side: a floating stick. Right side: Jump, Dash, Sword and Fireball buttons.
extends Node2D

const Data = preload("res://scripts/data.gd")

const STICK_RADIUS := 80.0
const BUTTONS := {
	"jump": {"pos": Vector2(1170, 610), "r": 78.0, "label": "Jump", "color": Color(0.4, 0.75, 1.0)},
	"dash": {"pos": Vector2(1010, 640), "r": 60.0, "label": "Dash", "color": Color(0.7, 0.55, 1.0)},
	"attack": {"pos": Vector2(1160, 440), "r": 58.0, "label": "Sword", "color": Color(0.9, 0.9, 0.95)},
	"spell": {"pos": Vector2(1010, 490), "r": 52.0, "label": "Fire", "color": Color(1.0, 0.5, 0.15)},
}

var game: Node
var touches := {}  # finger index -> "stick" or a button name
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var held := {"jump": false, "dash": false, "attack": false, "spell": false}
var pressed := {"jump": false, "dash": false, "attack": false, "spell": false}


## Buttons are laid out for a 1280x720 screen; wider phones push them to the right edge.
func button_pos(name: String) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	return BUTTONS[name]["pos"] + Vector2(view.x - 1280.0, view.y - 720.0)


func stick_vector() -> Vector2:
	if not touches.values().has("stick"):
		return Vector2.ZERO
	return ((stick_pos - stick_origin) / STICK_RADIUS).limit_length(1.0)


## Called once per physics frame by the game; one-shot presses are cleared after.
func take_pressed() -> Dictionary:
	var out := pressed.duplicate()
	for k in pressed:
		pressed[k] = false
	return out


func release_all() -> void:
	touches.clear()
	for k in held:
		held[k] = false


func _input(event: InputEvent) -> void:
	if game.state != "playing":
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var pos: Vector2 = make_input_local(event).position
	if event is InputEventScreenTouch:
		if event.pressed:
			for name in BUTTONS:
				var b: Dictionary = BUTTONS[name]
				if pos.distance_to(button_pos(name)) <= b["r"] + 18.0:
					touches[event.index] = name
					held[name] = true
					pressed[name] = true
					get_viewport().set_input_as_handled()
					return
			if pos.x < get_viewport().get_visible_rect().size.x / 2.0 and pos.y > 110.0 and not touches.values().has("stick"):
				touches[event.index] = "stick"
				stick_origin = pos
				stick_pos = pos
		else:
			var role = touches.get(event.index)
			if role != null:
				touches.erase(event.index)
				if role in held:
					held[role] = false
	elif event is InputEventScreenDrag and touches.get(event.index) == "stick":
		stick_pos = pos


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game.state == "title" or game.player == null:
		return
	var font := ThemeDB.fallback_font
	var p = game.player
	# Hearts.
	for i in p.max_hearts:
		var c := Vector2(40 + i * 44, 40)
		var full: bool = i < p.hearts
		_heart(c, Color(0.95, 0.3, 0.35) if full else Color(0.3, 0.3, 0.35))
	draw_string(font, Vector2(30, 100), "Gold %d" % game.gold, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.85, 0.35))
	var where := "Boss lair" if game.depth == Data.DEPTHS else "Depth %d / %d" % [game.depth, Data.CAVES]
	draw_string(font, Vector2(30, 134), where, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.7))

	# Boss health bar along the top.
	var boss = game.boss
	if boss and is_instance_valid(boss):
		var view := get_viewport().get_visible_rect().size
		var bar := Rect2(view.x / 2.0 - 260.0, 46.0, 520.0, 18.0)
		draw_string(font, Vector2(bar.position.x, bar.position.y - 6.0), "The Cave King", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.85, 0.5))
		draw_rect(bar.grow(3.0), Color(0, 0, 0, 0.6))
		var frac: float = clampf(float(boss.hp) / boss.max_hp, 0.0, 1.0)
		var col := Color(0.95, 0.35, 0.3) if boss.enraged() else Color(0.85, 0.55, 0.95)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)

	# Stick.
	if touches.values().has("stick"):
		draw_arc(stick_origin, STICK_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.3), 3.0)
		draw_circle(stick_origin + stick_vector() * STICK_RADIUS, 30.0, Color(1, 1, 1, 0.3))
	elif game.show_hint:
		draw_string(font, Vector2(60, get_viewport().get_visible_rect().size.y - 80.0), "Drag here to move", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.45))

	# Buttons.
	for name in BUTTONS:
		var b: Dictionary = BUTTONS[name]
		var col: Color = b["color"]
		var bp := button_pos(name)
		var alpha := 0.55 if held[name] else 0.28
		draw_circle(bp, b["r"], Color(col, alpha))
		draw_arc(bp, b["r"], 0, TAU, 40, Color(col, 0.8), 3.0)
		if name == "spell" and p.fire_cd > 0.0:
			var frac: float = clamp(p.fire_cd / p.fire_cooldown, 0.0, 1.0)
			draw_arc(bp, b["r"] - 6.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 32, Color(0, 0, 0, 0.6), 10.0)
		draw_string(font, bp + Vector2(-60, 8), b["label"], HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(1, 1, 1, 0.85))


func _heart(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-7, -4), 9.0, col)
	draw_circle(c + Vector2(7, -4), 9.0, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -1), c + Vector2(16, -1), c + Vector2(0, 16)]), col)
