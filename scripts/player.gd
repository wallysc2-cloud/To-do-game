## The hero. Moves while you drag, attacks the nearest enemy when standing still.
extends Node2D

const Data = preload("res://scripts/data.gd")

var game: Node
var weapon_id := "sword"
var weapon: Dictionary
var max_hp := 100.0
var hp := 100.0
var base_speed := 270.0
var radius := 18.0
var move_input := Vector2.ZERO
var facing := Vector2.UP
var attack_timer := 0.0
var invuln := 0.0
var flash := 0.0

# Run-only boosts from boons.
var damage_mult := 1.0
var speed_mult := 1.0
var attack_speed_mult := 1.0
var pierce := 0
var chill := false
var leech := 0.0


func setup(game_node: Node, chosen_weapon: String) -> void:
	game = game_node
	weapon_id = chosen_weapon
	weapon = Data.WEAPONS[weapon_id]


func is_moving() -> bool:
	return move_input.length() > 0.15


func _process(delta: float) -> void:
	attack_timer -= delta
	invuln = max(invuln - delta, 0.0)
	flash = max(flash - delta, 0.0)

	if is_moving():
		position += move_input * base_speed * speed_mult * delta
		position = game.clamp_to_arena(position, radius)
		facing = move_input.normalized()
	elif attack_timer <= 0.0:
		_try_attack()
	queue_redraw()


func _try_attack() -> void:
	var target = game.nearest_enemy(position, weapon["range"] + 30.0)
	if target == null:
		return
	var dir: Vector2 = (target.position - position).normalized()
	facing = dir
	attack_timer = weapon["cooldown"] / attack_speed_mult
	match weapon_id:
		"sword":
			_swing(dir, weapon["damage"])
		"flame_sword":
			_swing(dir, weapon["damage"])
			game.spawn_projectile({
				"pos": position + dir * 20.0, "vel": dir * weapon["bolt_speed"],
				"damage": weapon["bolt_damage"] * damage_mult, "radius": 9.0,
				"color": Color(1.0, 0.55, 0.15), "from_player": true, "max_dist": 420.0,
				"burn_dps": weapon["burn_dps"], "burn_time": weapon["burn_time"],
				"pierce": pierce, "chill": chill,
			})
		"bow":
			game.spawn_projectile({
				"pos": position + dir * 20.0, "vel": dir * weapon["projectile_speed"],
				"damage": weapon["damage"] * damage_mult, "radius": 6.0,
				"color": Color(0.95, 0.95, 0.8), "from_player": true,
				"max_dist": weapon["range"] + 60.0, "shape": "arrow",
				"pierce": pierce, "chill": chill,
			})


func _swing(dir: Vector2, damage: float) -> void:
	var reach: float = weapon["range"]
	var half_arc: float = weapon["arc"] / 2.0
	var tint := Color(1.0, 0.6, 0.2) if weapon_id == "flame_sword" else Color(0.9, 0.95, 1.0)
	game.spawn_effect({"kind": "swing", "pos": position, "dir": dir, "radius": reach, "arc": weapon["arc"], "color": tint})
	for enemy in game.enemies.duplicate():
		var to_enemy: Vector2 = enemy.position - position
		if to_enemy.length() > reach + enemy.radius:
			continue
		if abs(dir.angle_to(to_enemy)) <= half_arc or to_enemy.length() < enemy.radius + radius:
			enemy.take_damage(damage * damage_mult)
			if not is_instance_valid(enemy) or enemy.hp <= 0.0:
				continue
			if weapon_id == "flame_sword":
				enemy.apply_burn(weapon["burn_dps"], weapon["burn_time"])
			if chill:
				enemy.apply_slow(0.7, 1.5)


func take_damage(amount: float) -> void:
	if invuln > 0.0 or hp <= 0.0:
		return
	hp = max(hp - amount, 0.0)
	invuln = 0.6
	flash = 0.15
	game.on_player_hurt(amount)
	if hp <= 0.0:
		game.on_player_died()


func heal(amount: float) -> void:
	hp = min(hp + amount, max_hp)


func _draw() -> void:
	var body := Color(0.35, 0.6, 1.0)
	if flash > 0.0:
		body = Color(1, 1, 1)
	elif invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		body.a = 0.5
	draw_circle(Vector2.ZERO, radius + 3.0, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, radius, body)
	# Weapon pointing where we face.
	var tip := facing * (radius + 16.0)
	var weapon_color := Color(1.0, 0.55, 0.15) if weapon_id == "flame_sword" else Color(0.85, 0.85, 0.9)
	if weapon_id == "bow":
		draw_arc(facing * (radius + 4.0), 12.0, facing.angle() - 1.2, facing.angle() + 1.2, 12, Color(0.7, 0.5, 0.3), 3.0)
	else:
		draw_line(facing * (radius - 2.0), tip, weapon_color, 4.0)
	# Eyes.
	var side := facing.orthogonal() * 6.0
	draw_circle(facing * 6.0 + side, 3.0, Color(0.05, 0.05, 0.1))
	draw_circle(facing * 6.0 - side, 3.0, Color(0.05, 0.05, 0.1))
