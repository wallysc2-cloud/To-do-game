## A monster. Behaviour depends on its kind: slime, archer, brute or boss.
extends Node2D

const Data = preload("res://scripts/data.gd")

var game: Node
var kind := "slime"
var stats: Dictionary
var max_hp := 40.0
var hp := 40.0
var radius := 18.0
var speed := 100.0
var flash := 0.0

var burn_dps := 0.0
var burn_time := 0.0
var slow_mult := 1.0
var slow_time := 0.0

var action_timer := 0.0
var ring_timer := 0.0
var charge_state := ""  # "", "windup", "charging"
var charge_dir := Vector2.ZERO
var charge_left := 0.0
var spawn_fade := 0.4


func setup(game_node: Node, enemy_kind: String) -> void:
	game = game_node
	kind = enemy_kind
	stats = Data.ENEMIES[kind]
	max_hp = stats["hp"]
	hp = max_hp
	radius = stats["radius"]
	speed = stats["speed"]
	action_timer = randf_range(1.0, stats.get("charge_every", stats.get("shot_every", 2.0)))
	ring_timer = stats.get("ring_every", 0.0)


func _process(delta: float) -> void:
	flash = max(flash - delta, 0.0)
	spawn_fade = max(spawn_fade - delta, 0.0)
	_tick_status(delta)
	if hp <= 0.0:
		return
	if spawn_fade > 0.0:
		queue_redraw()
		return

	var player = game.player
	var to_player: Vector2 = player.position - position
	var dist := to_player.length()
	var dir := to_player.normalized() if dist > 0.01 else Vector2.DOWN
	var move_speed := speed * slow_mult

	match kind:
		"slime":
			position += dir * move_speed * delta
		"archer":
			var keep: float = stats["keep_away"]
			if dist < keep - 40.0:
				position -= dir * move_speed * delta
			elif dist > keep + 40.0:
				position += dir * move_speed * delta
			else:
				position += dir.orthogonal() * move_speed * 0.5 * delta
			action_timer -= delta
			if action_timer <= 0.0:
				action_timer = stats["shot_every"]
				_shoot(dir)
		"brute", "boss":
			_charger_behaviour(delta, dir, move_speed)
			if kind == "boss":
				ring_timer -= delta
				if ring_timer <= 0.0 and charge_state == "":
					ring_timer = stats["ring_every"]
					_shoot_ring()

	_separate_from_others()
	position = game.clamp_to_arena(position, radius)

	if dist < radius + player.radius:
		player.take_damage(stats["touch"])
	queue_redraw()


func _charger_behaviour(delta: float, dir: Vector2, move_speed: float) -> void:
	match charge_state:
		"":
			position += dir * move_speed * delta
			action_timer -= delta
			if action_timer <= 0.0:
				charge_state = "windup"
				charge_left = 0.6
				charge_dir = dir
		"windup":
			charge_left -= delta
			if charge_left <= 0.0:
				charge_state = "charging"
				charge_left = 0.5
		"charging":
			position += charge_dir * stats["charge_speed"] * slow_mult * delta
			charge_left -= delta
			if charge_left <= 0.0:
				charge_state = ""
				action_timer = stats["charge_every"]


func _shoot(dir: Vector2) -> void:
	game.spawn_projectile({
		"pos": position + dir * (radius + 4.0), "vel": dir * stats["shot_speed"],
		"damage": stats["shot_damage"], "radius": 7.0, "color": Color(1.0, 0.35, 0.35),
		"from_player": false, "max_dist": 900.0,
	})


func _shoot_ring() -> void:
	var count: int = stats["ring_count"]
	var offset := randf() * TAU
	for i in count:
		var dir := Vector2.RIGHT.rotated(offset + TAU * i / count)
		game.spawn_projectile({
			"pos": position + dir * (radius + 4.0), "vel": dir * stats["shot_speed"],
			"damage": stats["shot_damage"], "radius": 8.0, "color": Color(0.85, 0.4, 1.0),
			"from_player": false, "max_dist": 900.0,
		})


func _separate_from_others() -> void:
	for other in game.enemies:
		if other == self:
			continue
		var gap: Vector2 = position - other.position
		var min_dist: float = radius + other.radius
		var d := gap.length()
		if d < min_dist and d > 0.01:
			position += gap / d * (min_dist - d) * 0.5


func _tick_status(delta: float) -> void:
	if burn_time > 0.0:
		burn_time -= delta
		_lose_hp(burn_dps * delta, false)
	if slow_time > 0.0:
		slow_time -= delta
		if slow_time <= 0.0:
			slow_mult = 1.0


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	flash = 0.1
	game.spawn_effect({"kind": "text", "pos": position + Vector2(randf_range(-10, 10), -radius), "text": str(roundi(amount)), "color": Color(1, 1, 0.8)})
	_lose_hp(amount, true)


func _lose_hp(amount: float, _direct: bool) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	if hp <= 0.0:
		game.on_enemy_died(self)


func apply_burn(dps: float, duration: float) -> void:
	burn_dps = max(burn_dps, dps)
	burn_time = max(burn_time, duration)


func apply_slow(mult: float, duration: float) -> void:
	slow_mult = min(slow_mult, mult)
	slow_time = max(slow_time, duration)


func _draw() -> void:
	var col: Color = stats["color"]
	if flash > 0.0:
		col = Color(1, 1, 1)
	if spawn_fade > 0.0:
		col.a = 1.0 - spawn_fade / 0.4
	if charge_state == "windup":
		draw_line(Vector2.ZERO, charge_dir * 140.0, Color(1, 0.3, 0.3, 0.6), radius * 0.8)
	draw_circle(Vector2(0, 4), radius + 2.0, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, radius, col)
	if slow_time > 0.0:
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 24, Color(0.55, 0.85, 1.0), 3.0)
	if burn_time > 0.0:
		draw_arc(Vector2.ZERO, radius + 7.0, 0, TAU, 24, Color(1.0, 0.45, 0.1, 0.8), 2.0)
	var eye_y := -radius * 0.2
	draw_circle(Vector2(-radius * 0.35, eye_y), radius * 0.16, Color(0.05, 0.05, 0.1))
	draw_circle(Vector2(radius * 0.35, eye_y), radius * 0.16, Color(0.05, 0.05, 0.1))
	if hp < max_hp:
		var w := radius * 2.0
		draw_rect(Rect2(-w / 2.0, -radius - 12.0, w, 5.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2.0, -radius - 12.0, w * max(hp, 0.0) / max_hp, 5.0), Color(0.9, 0.25, 0.25))
