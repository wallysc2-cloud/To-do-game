## The Fireball spell: flies straight and explodes on whatever it hits, blasting away blocks.
extends Node2D

var vel := Vector2.ZERO
var age := 0.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var flicker := 1.0 + sin(age * 40.0) * 0.15
	draw_circle(Vector2.ZERO, 12.0 * flicker, Color(1.0, 0.45, 0.1, 0.35))
	draw_circle(Vector2.ZERO, 7.0 * flicker, Color(1.0, 0.65, 0.2))
	draw_circle(Vector2.ZERO, 3.5, Color(1.0, 0.95, 0.7))
