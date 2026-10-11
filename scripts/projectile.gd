## Arrows, fire bolts, fireballs and enemy shots.
extends Node2D

var game: Node
var vel := Vector2.ZERO
var damage := 10.0
var radius := 6.0
var color := Color.WHITE
var from_player := true
var max_dist := 600.0
var travelled := 0.0
var shape := "orb"
var explode_radius := 0.0
var burn_dps := 0.0
var burn_time := 0.0
var pierce := 0
var chill := false
var already_hit: Array = []


func setup(game_node: Node, p: Dictionary) -> void:
	game = game_node
	position = p["pos"]
	vel = p["vel"]
	damage = p["damage"]
	radius = p.get("radius", 6.0)
	color = p.get("color", Color.WHITE)
	from_player = p.get("from_player", true)
	max_dist = p.get("max_dist", 600.0)
	shape = p.get("shape", "orb")
	explode_radius = p.get("explode_radius", 0.0)
	burn_dps = p.get("burn_dps", 0.0)
	burn_time = p.get("burn_time", 0.0)
	pierce = p.get("pierce", 0)
	chill = p.get("chill", false)


func _process(delta: float) -> void:
	var step := vel * delta
	position += step
	travelled += step.length()
	if travelled > max_dist or not game.ARENA.grow(40.0).has_point(position):
		_finish(false)
		return
	if from_player:
		for enemy in game.enemies:
			if enemy in already_hit:
				continue
			if position.distance_to(enemy.position) < radius + enemy.radius:
				_hit_enemy(enemy)
				return
	else:
		var player = game.player
		if position.distance_to(player.position) < radius + player.radius:
			player.take_damage(damage)
			queue_free()
			return
	queue_redraw()


func _hit_enemy(enemy: Node) -> void:
	if explode_radius > 0.0:
		_finish(true)
		return
	already_hit.append(enemy)
	enemy.take_damage(damage)
	if is_instance_valid(enemy) and enemy.hp > 0.0:
		if burn_time > 0.0:
			enemy.apply_burn(burn_dps, burn_time)
		if chill:
			enemy.apply_slow(0.7, 1.5)
	if pierce > 0:
		pierce -= 1
		return
	queue_free()


func _finish(hit: bool) -> void:
	# Fireballs explode wherever they stop.
	if explode_radius > 0.0 and (hit or from_player):
		game.explode(position, explode_radius, damage, color, burn_dps, burn_time)
	queue_free()


func _draw() -> void:
	if shape == "arrow":
		var back := -vel.normalized() * 16.0
		draw_line(back, Vector2.ZERO, color, 3.0)
		draw_circle(Vector2.ZERO, 3.0, color)
	else:
		draw_circle(Vector2.ZERO, radius + 3.0, Color(color, 0.3))
		draw_circle(Vector2.ZERO, radius, color)
