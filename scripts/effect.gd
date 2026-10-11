## Short-lived visuals: sword swings, explosion rings and damage numbers.
extends Node2D

var kind := "ring"
var life := 0.3
var age := 0.0
var color := Color.WHITE
var radius := 50.0
var dir := Vector2.RIGHT
var arc := 2.0
var text := ""


func setup(p: Dictionary) -> void:
	kind = p["kind"]
	position = p["pos"]
	color = p.get("color", Color.WHITE)
	radius = p.get("radius", 50.0)
	dir = p.get("dir", Vector2.RIGHT)
	arc = p.get("arc", 2.0)
	text = p.get("text", "")
	life = {"swing": 0.15, "ring": 0.3, "text": 0.7}.get(kind, 0.3)
	z_index = 20 if kind == "text" else 5


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	if kind == "text":
		position.y -= 50.0 * delta
	queue_redraw()


func _draw() -> void:
	var t := age / life
	var c := Color(color, 1.0 - t)
	match kind:
		"swing":
			var a := dir.angle()
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				pts.append(Vector2.RIGHT.rotated(a - arc / 2.0 + arc * i / 12.0) * radius)
			draw_colored_polygon(pts, Color(color, 0.35 * (1.0 - t)))
			draw_arc(Vector2.ZERO, radius, a - arc / 2.0, a + arc / 2.0, 16, c, 3.0)
		"ring":
			draw_circle(Vector2.ZERO, radius * (0.4 + 0.6 * t), Color(color, 0.25 * (1.0 - t)))
			draw_arc(Vector2.ZERO, radius * (0.4 + 0.6 * t), 0, TAU, 32, c, 4.0)
		"text":
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(-30, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 60, 22, c)
