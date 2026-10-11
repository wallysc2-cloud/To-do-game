## Draws the in-run HUD: health, wave, spell buttons and the movement stick.
extends Node2D

const Data = preload("res://scripts/data.gd")

var game: Node


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game.state == "menu":
		return
	var font := ThemeDB.fallback_font
	var player = game.player
	if player == null:
		return

	# Health bar.
	var bar := Rect2(30, 40, 420, 30)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * player.hp / player.max_hp, bar.size.y)), Color(0.85, 0.25, 0.3))
	draw_rect(bar, Color(1, 1, 1, 0.4), false, 2.0)
	draw_string(font, bar.position + Vector2(10, 22), "%d / %d" % [ceili(player.hp), roundi(player.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	# Wave label.
	var wave_text := "Boss" if game.wave == Data.WAVES.size() else "Wave %d / %d" % [game.wave, Data.WAVES.size() - 1]
	draw_string(font, Vector2(30, 110), wave_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.9))

	# Spell buttons.
	for i in game.chosen_spells.size():
		var spell: Dictionary = Data.SPELLS[game.chosen_spells[i]]
		var center: Vector2 = game.spell_button_center(i)
		var r: float = game.SPELL_BUTTON_R
		var ready: bool = game.spell_cd[i] <= 0.0
		draw_circle(center, r, Color(spell["color"], 0.9 if ready else 0.35))
		draw_arc(center, r, 0, TAU, 48, Color(1, 1, 1, 0.7), 3.0)
		if not ready:
			var frac: float = game.spell_cd[i] / game.spell_cooldown(i)
			var pts := PackedVector2Array([center])
			var steps := 32
			for s in steps + 1:
				pts.append(center + Vector2.UP.rotated(TAU * frac * s / steps) * r)
			if frac > 0.97:
				draw_circle(center, r, Color(0, 0, 0, 0.55))
			elif frac > 0.03:
				draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
			draw_string(font, center + Vector2(-40, 10), "%.1f" % game.spell_cd[i], HORIZONTAL_ALIGNMENT_CENTER, 80, 28, Color.WHITE)
		draw_string(font, center + Vector2(-80, r + 30), spell["name"], HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Color(1, 1, 1, 0.85))

	# Movement stick.
	if game.joy_index != -1:
		draw_arc(game.joy_origin, game.JOY_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.35), 3.0)
		var knob: Vector2 = game.joy_origin + player.move_input * game.JOY_RADIUS
		draw_circle(knob, 26.0, Color(1, 1, 1, 0.35))
	elif game.state == "playing" and game.run_time < 6.0:
		draw_string(font, Vector2(0, game.ARENA.end.y - 40), "Drag to move. Stand still to attack.", HORIZONTAL_ALIGNMENT_CENTER, 720, 24, Color(1, 1, 1, 0.6))
