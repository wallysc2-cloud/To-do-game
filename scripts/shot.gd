## Enemy projectiles: spitter globs, the boss's rocks and its ground shockwaves.
## position is the centre. The game moves them and checks what they hit.
extends Node2D

var kind := "glob"
var vel := Vector2.ZERO
var gravity := 0.0
var age := 0.0
var life := 4.0
var size := Vector2(12, 12)


func rect() -> Rect2:
	return Rect2(position - size / 2.0, size)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	match kind:
		"glob":
			draw_circle(Vector2.ZERO, 7.0, Color(0.95, 0.85, 0.3, 0.35))
			draw_circle(Vector2.ZERO, 5.0, Color(0.9, 0.75, 0.2))
		"rock":
			draw_circle(Vector2.ZERO, 8.0, Color(0.45, 0.38, 0.5))
			draw_circle(Vector2(-2, -2), 3.0, Color(0.6, 0.52, 0.66))
		"wave":
			var d := signf(vel.x)
			# A jagged crest leaning the way it travels.
			var pts := PackedVector2Array([
				Vector2(-size.x / 2.0, size.y / 2.0), Vector2(size.x / 4.0 * d, -size.y / 2.0),
				Vector2(size.x / 2.0, size.y / 2.0)])
			draw_colored_polygon(pts, Color(1.0, 0.6, 0.25, 0.85))
			draw_rect(Rect2(-size.x / 2.0, size.y / 2.0 - 4, size.x, 4), Color(1, 0.85, 0.5, 0.7))
