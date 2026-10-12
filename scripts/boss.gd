## The Cave King, the boss at the bottom of the run. Each attack is telegraphed by a short
## wind-up: it leaps and slams the floor (shockwaves run along the ground, so get on a ledge
## or jump), lobs a volley of rocks, or charges, and stuns itself if it hits a wall.
## Hits land twice as hard while it's stunned. Below half health it gets faster.
## position is the top-left corner of the hitbox.
extends Node2D

const Data = preload("res://scripts/data.gd")

var game: Node
var level: Node
var kind := "boss"
var stats: Dictionary = Data.BOSS
var size: Vector2 = Data.BOSS["size"]
var hp: int = Data.BOSS["hp"]
var max_hp: int = Data.BOSS["hp"]
var vel := Vector2.ZERO
var dir := -1
var flash := 0.0
var t := 0.0

var state := "idle"  # idle, walk, windup, leap, spit, charge, stunned
var state_time := 0.0
var next_attack := ""
var last_attack := ""
var airborne := false
var volley_left := 0
var volley_cd := 0.0


func setup(game_node: Node, level_node: Node, cell: Vector2i) -> void:
	game = game_node
	level = level_node
	var T := Data.TILE
	position = Vector2(cell.x * T + T / 2.0 - size.x / 2.0, (cell.y + 1) * T - size.y)
	_enter("idle", 1.5)


func center() -> Vector2:
	return position + size / 2.0


func rect() -> Rect2:
	return Rect2(position, size)


func enraged() -> bool:
	return hp * 2 <= max_hp


func harmless() -> bool:
	return state == "stunned"


func _enter(new_state: String, time: float) -> void:
	state = new_state
	state_time = time


func step(delta: float) -> void:
	t += delta
	flash = max(flash - delta, 0.0)
	state_time -= delta
	var player = game.player
	var to_player: float = player.center().x - center().x
	var speed_mult := 1.35 if enraged() else 1.0

	match state:
		"idle":
			vel.x = move_toward(vel.x, 0.0, 900.0 * delta)
			if state_time <= 0.0:
				_pick_attack()
		"walk":
			dir = 1 if to_player > 0.0 else -1
			vel.x = dir * stats["speed"] * speed_mult
			if state_time <= 0.0:
				_pick_attack()
		"windup":
			vel.x = 0.0
			if state_time <= 0.0:
				_start_attack(next_attack, to_player)
		"leap":
			if airborne and level.on_floor(position, size, true) and vel.y >= 0.0:
				airborne = false
				vel.x = 0.0
				game.boss_slam(self)
				_enter("idle", 0.9 / speed_mult)
			elif state_time <= 0.0:
				airborne = false
				_enter("idle", 0.5)
		"spit":
			vel.x = 0.0
			volley_cd -= delta
			if volley_cd <= 0.0 and volley_left > 0:
				volley_left -= 1
				volley_cd = 0.22
				# Aim each rock to come down around the player, spread a little.
				var air_time := 0.9
				var target: Vector2 = player.center() + Vector2(randf_range(-70.0, 70.0), 0.0)
				var mouth := center() + Vector2(dir * 20.0, -12.0)
				var d := target - mouth
				game.spawn_shot(mouth, Vector2(d.x / air_time, d.y / air_time - 0.5 * 800.0 * air_time), 800.0, "rock")
			if volley_left <= 0 and volley_cd <= 0.0:
				_enter("idle", 0.8 / speed_mult)
		"charge":
			vel.x = dir * stats["charge_speed"] * speed_mult
			if state_time <= 0.0:
				_enter("idle", 0.6)
		"stunned":
			vel.x = 0.0
			if state_time <= 0.0:
				_enter("idle", 0.4)

	vel.y = min(vel.y + Data.GRAVITY * delta, Data.MAX_FALL * 1.4)
	# The boss never stands on wooden ledges; they're your safe spots.
	var res: Dictionary = level.move_box(position, size, vel * delta, true)
	position = res["pos"]
	if res["hit_y"]:
		vel.y = 0.0
	if res["hit_x"] and state == "charge":
		_enter("stunned", 1.6)
		game.on_boss_bonk(self)
	queue_redraw()


func _pick_attack() -> void:
	if state == "idle" and randf() < 0.35:
		_enter("walk", randf_range(0.7, 1.3))
		return
	var options := ["leap", "spit", "charge"]
	options.erase(last_attack)
	next_attack = options[randi() % options.size()]
	last_attack = next_attack
	_enter("windup", 0.35 if enraged() else 0.55)


func _start_attack(attack: String, to_player: float) -> void:
	dir = 1 if to_player > 0.0 else -1
	match attack:
		"leap":
			vel = Vector2(clampf(to_player * 1.1, -380.0, 380.0), -stats["leap_speed"])
			airborne = true
			_enter("leap", 3.0)
		"spit":
			volley_left = 5 if enraged() else 3
			volley_cd = 0.0
			_enter("spit", 3.0)
		"charge":
			_enter("charge", 2.4)


func hit(amount: int) -> void:
	if hp <= 0:
		return
	if state == "stunned":
		amount *= 2
	hp -= amount
	flash = 0.1
	if hp <= 0:
		game.on_enemy_killed(self)


func _draw() -> void:
	var col: Color = stats["color"]
	if enraged():
		col = col.lerp(Color(0.75, 0.3, 0.3), 0.35)
	if flash > 0.0:
		col = Color.WHITE
	var shake := Vector2.ZERO
	if state == "windup":
		shake = Vector2(sin(t * 60.0) * 2.0, 0)
	var squash := Vector2.ONE
	if state == "windup" and next_attack == "leap":
		squash = Vector2(1.12, 0.85)
	elif state == "charge":
		squash = Vector2(1.1, 0.92)
	var s := size * squash
	var o := Vector2((size.x - s.x) / 2.0, size.y - s.y) + shake
	# Body and shoulders.
	draw_rect(Rect2(o + Vector2(0, 10), Vector2(s.x, s.y - 10)), col)
	draw_rect(Rect2(o + Vector2(6, 0), Vector2(s.x - 12, 14)), col.lightened(0.1))
	draw_rect(Rect2(o + Vector2(0, s.y - 8), Vector2(s.x, 8)), col.darkened(0.3))
	# Glowing cracks once it's angry.
	if enraged():
		var glow := Color(1.0, 0.55, 0.2, 0.7 + 0.3 * sin(t * 8.0))
		draw_line(o + Vector2(10, 22), o + Vector2(22, 34), glow, 2.0)
		draw_line(o + Vector2(s.x - 12, 18), o + Vector2(s.x - 20, 36), glow, 2.0)
	# Crown.
	var gold := Color(1.0, 0.8, 0.25)
	for i in 3:
		var cx := o.x + s.x / 2.0 + (i - 1) * 12.0
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 6, o.y + 2), Vector2(cx, o.y - 12), Vector2(cx + 6, o.y + 2)]), gold)
	# Eyes, glowing hot during a wind-up so you can see what's coming.
	var eye := Color(1.0, 0.35, 0.2)
	if state == "windup":
		eye = Color(1.0, 0.9, 0.4)
	var ex := o.x + s.x / 2.0 + dir * 8.0
	draw_rect(Rect2(ex - 12, o.y + 18, 8, 6), eye)
	draw_rect(Rect2(ex + 4, o.y + 18, 8, 6), eye)
	# Stunned: little stars circling its head.
	if state == "stunned":
		for i in 3:
			var a := t * 5.0 + i * TAU / 3.0
			var p := Vector2(size.x / 2.0, -16) + Vector2(cos(a) * 22.0, sin(a) * 6.0)
			draw_circle(p, 3.0, Color(1, 1, 0.6))
