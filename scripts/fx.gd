## Short-lived visuals: dust, debris, sparkles, explosion rings and floating text.
extends Node2D

var kind := "bit"
var vel := Vector2.ZERO
var gravity := 0.0
var life := 0.4
var age := 0.0
var color := Color.WHITE
var size := 4.0
var text := ""


func setup(p: Dictionary) -> void:
	kind = p.get("kind", "bit")
	position = p["pos"]
	vel = p.get("vel", Vector2.ZERO)
	gravity = p.get("gravity", 0.0)
	life = p.get("life", 0.4)
	color = p.get("color", Color.WHITE)
	size = p.get("size", 4.0)
	text = p.get("text", "")
	z_index = 30 if kind == "text" else 10


func _process(delta: float) -> void:
	age += delta
	if age >= life:
		queue_free()
		return
	vel.y += gravity * delta
	position += vel * delta
	queue_redraw()


func _draw() -> void:
	var k := age / life
	var c := Color(color, color.a * (1.0 - k))
	match kind:
		"bit":
			var s := size * (1.0 - k * 0.5)
			draw_rect(Rect2(-s / 2.0, -s / 2.0, s, s), c)
		"ring":
			draw_arc(Vector2.ZERO, size * (0.3 + 0.7 * k), 0, TAU, 32, c, 5.0 * (1.0 - k) + 1.0)
			draw_circle(Vector2.ZERO, size * (0.3 + 0.7 * k), Color(c, c.a * 0.25))
		"text":
			draw_string(ThemeDB.fallback_font, Vector2(-40, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 80, 14, c)
