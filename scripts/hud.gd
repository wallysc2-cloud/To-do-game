## On-screen controls and status, drawn on top of the game in screen space.
## Left half: a floating stick to move. Right half: tap to jump (hold for a higher jump),
## swipe to dash that way, in any of 8 directions, even in the air.
## Sword and Fire are two small buttons above where the right thumb rests.
extends Node2D

const Data = preload("res://scripts/data.gd")

const STICK_RADIUS := 80.0
const SWIPE_DISTANCE := 28.0  # how far a finger moves before it counts as a swipe (dash)
const TAP_DELAY := 0.08       # a touch that hasn't swiped by now is a jump
const BUTTONS := {
	"attack": {"pos": Vector2(1180, 400), "r": 46.0, "label": "Sword", "color": Color(0.9, 0.9, 0.95)},
	"spell": {"pos": Vector2(1060, 440), "r": 46.0, "label": "Fire", "color": Color(1.0, 0.5, 0.15)},
}

var game: Node
var touches := {}  # finger index -> {role: "stick" | "jump" | button name, ...}
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var held := {"jump": false, "attack": false, "spell": false}
var pressed := {"jump": false, "dash": false, "attack": false, "spell": false}
var dash_dir := Vector2.ZERO
var swipe_fx := []  # [{from, to, age}] short streaks showing a swipe registered


## Buttons are laid out for a 1280x720 screen; wider phones push them to the right edge.
func button_pos(name: String) -> Vector2:
	var view := get_viewport().get_visible_rect().size
	return BUTTONS[name]["pos"] + Vector2(view.x - 1280.0, view.y - 720.0)


func _has_role(role: String) -> bool:
	for t in touches.values():
		if t["role"] == role:
			return true
	return false


func stick_vector() -> Vector2:
	if not _has_role("stick"):
		return Vector2.ZERO
	return ((stick_pos - stick_origin) / STICK_RADIUS).limit_length(1.0)


## Called once per physics frame by the game; one-shot presses are cleared after.
func take_pressed() -> Dictionary:
	# A right-side touch that hasn't turned into a swipe by now is a jump.
	var now := Time.get_ticks_msec() / 1000.0
	for t in touches.values():
		if t["role"] == "right" and now - t["start"] >= TAP_DELAY:
			_start_jump(t)
	var out := pressed.duplicate()
	out["dash_dir"] = dash_dir
	for k in pressed:
		pressed[k] = false
	dash_dir = Vector2.ZERO
	return out


func release_all() -> void:
	touches.clear()
	for k in held:
		held[k] = false


func _start_jump(t: Dictionary) -> void:
	t["role"] = "jump"
	pressed["jump"] = true
	held["jump"] = true


## Snaps a swipe to the nearest of the 8 directions.
static func snap8(v: Vector2) -> Vector2:
	var a := snappedf(v.angle(), PI / 4.0)
	return Vector2.RIGHT.rotated(a).round().normalized()


func _input(event: InputEvent) -> void:
	if game.state != "playing":
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var pos: Vector2 = make_input_local(event).position
	var view := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		if event.pressed:
			for name in BUTTONS:
				var b: Dictionary = BUTTONS[name]
				if pos.distance_to(button_pos(name)) <= b["r"] + 14.0:
					touches[event.index] = {"role": name}
					held[name] = true
					pressed[name] = true
					get_viewport().set_input_as_handled()
					return
			if pos.y < 110.0:
				return  # leave the top strip for the pause button
			if pos.x < view.x / 2.0:
				if not _has_role("stick"):
					touches[event.index] = {"role": "stick"}
					stick_origin = pos
					stick_pos = pos
			else:
				touches[event.index] = {"role": "right", "origin": pos, "start": Time.get_ticks_msec() / 1000.0}
		else:
			var t = touches.get(event.index)
			if t == null:
				return
			touches.erase(event.index)
			match t["role"]:
				"right":
					# A quick tap: jump now, already let go, so it's a short hop.
					pressed["jump"] = true
				"jump":
					held["jump"] = _has_role("jump")
				"stick", "dashed":
					pass
				_:
					held[t["role"]] = false
	elif event is InputEventScreenDrag:
		var t = touches.get(event.index)
		if t == null:
			return
		if t["role"] == "stick":
			stick_pos = pos
		elif t["role"] in ["right", "jump"]:
			var moved: Vector2 = pos - t["origin"]
			if moved.length() >= SWIPE_DISTANCE:
				# A swipe: dash that way. If it started as a jump, the jump stands and you dash from the air.
				if t["role"] == "jump":
					held["jump"] = false
				t["role"] = "dashed"
				dash_dir = snap8(moved)
				pressed["dash"] = true
				swipe_fx.append({"from": t["origin"], "to": t["origin"] + dash_dir * 90.0, "age": 0.0})


func _process(delta: float) -> void:
	for f in swipe_fx:
		f["age"] += delta
	swipe_fx = swipe_fx.filter(func(f): return f["age"] < 0.25)
	queue_redraw()


func _draw() -> void:
	if game.state == "village" or game.player == null:
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
	var view := get_viewport().get_visible_rect().size
	if _has_role("stick"):
		draw_arc(stick_origin, STICK_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.3), 3.0)
		draw_circle(stick_origin + stick_vector() * STICK_RADIUS, 30.0, Color(1, 1, 1, 0.3))
	elif game.show_hint:
		draw_string(font, Vector2(60, view.y - 80.0), "Drag here to move", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.45))
		draw_string(font, Vector2(view.x / 2.0, view.y - 80.0), "Tap here to jump, swipe to dash", HORIZONTAL_ALIGNMENT_CENTER, view.x / 2.0 - 20.0, 24, Color(1, 1, 1, 0.45))

	# Swipe streaks.
	for f in swipe_fx:
		var a: float = 0.5 * (1.0 - f["age"] / 0.25)
		draw_line(f["from"], f["to"], Color(0.7, 0.55, 1.0, a), 10.0)
		draw_circle(f["to"], 8.0, Color(0.7, 0.55, 1.0, a))

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
		draw_string(font, bp + Vector2(-60, 7), b["label"], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(1, 1, 1, 0.85))


func _heart(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-7, -4), 9.0, col)
	draw_circle(c + Vector2(7, -4), 9.0, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-16, -1), c + Vector2(16, -1), c + Vector2(0, 16)]), col)
