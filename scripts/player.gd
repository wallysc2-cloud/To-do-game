## The hero. Celeste-style movement: coyote time, jump buffering, wall jumps, dash.
## position is the top-left corner of the hitbox.
extends Node2D

const Data = preload("res://scripts/data.gd")

const SIZE := Vector2(18, 26)
## Boosts that carry over from one level to the next within a run.
const BOOST_PROPS := ["hearts", "max_hearts", "air_jumps", "max_dashes", "sword_reach", "fire_cooldown",
	"stomp_heal", "dash_strike", "fire_count", "blast_radius", "sword_damage", "spike_boots", "magnet"]

var game: Node
var level: Node
var vel := Vector2.ZERO
var facing := 1
var grounded := false
var coyote := 0.0
var jump_buffer := 0.0
var wall_lock := 0.0
var dashes_left := 1
var dash_time := 0.0
var dash_dir := Vector2.ZERO
var air_jumps_left := 0
var invuln := 0.0
var attack_time := 0.0
var attack_cd := 0.0
var fire_cd := 0.0
var squash := Vector2.ONE
var trail: Array = []
var drop_time := 0.0  # dropping down through a wooden ledge

var hearts := Data.MAX_HEARTS
var max_hearts := Data.MAX_HEARTS

# Run-only boosts.
var air_jumps := 0
var max_dashes := Data.DASH_COUNT
var sword_reach := Data.SWORD_REACH
var fire_cooldown := Data.FIREBALL_COOLDOWN
var stomp_heal := false
var dash_strike := false
var fire_count := 1
var blast_radius := Data.FIREBALL_RADIUS
var sword_damage := 1
var spike_boots := false
var magnet := false


func center() -> Vector2:
	return position + SIZE / 2.0


func rect() -> Rect2:
	return Rect2(position, SIZE)


func is_dashing() -> bool:
	return dash_time > 0.0


func step(delta: float, inp: Dictionary) -> void:
	coyote -= delta
	jump_buffer -= delta
	wall_lock -= delta
	invuln = max(invuln - delta, 0.0)
	attack_time -= delta
	attack_cd -= delta
	fire_cd -= delta
	drop_time -= delta
	squash = squash.lerp(Vector2.ONE, min(delta * 12.0, 1.0))

	var x_in: float = inp["x"]
	var y_in: float = inp["y"]
	if x_in != 0.0 and wall_lock <= 0.0:
		facing = 1 if x_in > 0.0 else -1
	if inp["jump_pressed"]:
		jump_buffer = Data.JUMP_BUFFER
	if grounded:
		coyote = Data.COYOTE_TIME
		dashes_left = max_dashes
		air_jumps_left = air_jumps

	# Dash: 8 directions, straight ahead if no direction is held.
	if inp["dash_pressed"] and dashes_left > 0 and not is_dashing():
		var d := Vector2(signf(x_in), signf(y_in))
		if d == Vector2.ZERO:
			d = Vector2(facing, 0)
		dash_dir = d.normalized()
		dash_time = Data.DASH_TIME
		dashes_left -= 1
		jump_buffer = 0.0
		squash = Vector2(1.3, 0.75) if dash_dir.y == 0.0 else Vector2(0.75, 1.3)
		game.on_dash(self)

	# Down + jump on a wooden ledge drops you through it.
	if grounded and y_in > 0.0 and jump_buffer > 0.0 and level.on_ledge_only(position, SIZE):
		drop_time = 0.2
		jump_buffer = 0.0
		grounded = false
		coyote = 0.0
		position.y += 2.0

	var wall: int = level.wall_side(position, SIZE) if not grounded else 0

	if is_dashing():
		dash_time -= delta
		vel = dash_dir * Data.DASH_SPEED
		trail.append({"pos": position, "age": 0.0})
		if dash_time <= 0.0:
			vel *= 0.55
			if dash_dir.y < 0.0:
				vel.y = max(vel.y, -260.0)
	else:
		var accel := Data.GROUND_ACCEL if grounded else Data.AIR_ACCEL
		if wall_lock > 0.0:
			accel *= 0.25
		vel.x = move_toward(vel.x, x_in * Data.RUN_SPEED, accel * delta)

		var g := Data.GRAVITY
		if vel.y > 0.0:
			g *= Data.FALL_GRAVITY_MULT
		elif not inp["jump_held"]:
			g *= Data.SHORT_HOP_GRAVITY_MULT
		vel.y = min(vel.y + g * delta, Data.MAX_FALL)

		# Slide down walls you push into.
		if wall != 0 and signf(x_in) == wall and vel.y > Data.WALL_SLIDE_SPEED:
			vel.y = Data.WALL_SLIDE_SPEED

		if jump_buffer > 0.0:
			if coyote > 0.0:
				_jump(Data.JUMP_SPEED)
			elif wall != 0:
				vel = Vector2(-wall * Data.WALL_JUMP_X, -Data.WALL_JUMP_Y)
				facing = -wall
				wall_lock = Data.WALL_JUMP_LOCK
				jump_buffer = 0.0
				squash = Vector2(0.75, 1.3)
				game.spawn_dust(center() + Vector2(wall * SIZE.x / 2.0, 0), 4)
			elif air_jumps_left > 0:
				air_jumps_left -= 1
				_jump(Data.JUMP_SPEED * 0.9)
				game.spawn_dust(center() + Vector2(0, SIZE.y / 2.0), 6)

	var was_grounded := grounded
	var fall_speed := vel.y
	var dropping := drop_time > 0.0
	var res: Dictionary = level.move_box(position, SIZE, vel * delta, dropping)
	position = res["pos"]
	if res["hit_x"]:
		vel.x = 0.0
		if is_dashing() and dash_dir.y == 0.0:
			dash_time = 0.0
	if res["hit_y"]:
		vel.y = 0.0
	grounded = level.on_floor(position, SIZE, dropping) and vel.y >= 0.0
	if grounded:
		level.step_on(position, SIZE)
	if grounded and not was_grounded:
		if fall_speed > 300.0:
			squash = Vector2(1.3, 0.7)
			game.spawn_dust(center() + Vector2(0, SIZE.y / 2.0), 5)

	# Attacks.
	if inp["attack_pressed"] and attack_cd <= 0.0:
		attack_time = 0.12
		attack_cd = Data.SWORD_COOLDOWN
		game.on_sword(self, sword_rect())
	if inp["spell_pressed"] and fire_cd <= 0.0:
		fire_cd = fire_cooldown
		game.on_fireball(self)

	for t in trail:
		t["age"] += delta
	trail = trail.filter(func(t): return t["age"] < 0.18)
	queue_redraw()


func _jump(speed: float) -> void:
	vel.y = -speed
	coyote = 0.0
	jump_buffer = 0.0
	grounded = false
	squash = Vector2(0.7, 1.3)
	game.spawn_dust(center() + Vector2(0, SIZE.y / 2.0), 4)


func sword_rect() -> Rect2:
	var y := position.y - 4.0
	if facing > 0:
		return Rect2(position.x + SIZE.x - 4.0, y, sword_reach, SIZE.y + 8.0)
	return Rect2(position.x + 4.0 - sword_reach, y, sword_reach, SIZE.y + 8.0)


func bounce() -> void:
	vel.y = -Data.STOMP_BOUNCE
	dashes_left = max_dashes
	air_jumps_left = air_jumps
	dash_time = 0.0
	squash = Vector2(0.7, 1.3)


func hurt(from: Vector2) -> void:
	if invuln > 0.0 or hearts <= 0:
		return
	hearts -= 1
	invuln = Data.HURT_INVULN
	dash_time = 0.0
	var away := signf(center().x - from.x)
	if away == 0.0:
		away = -facing
	vel = Vector2(away * 260.0, -380.0)
	game.on_player_hurt()


func _draw() -> void:
	# Dash afterimages, drawn relative to our current position.
	for t in trail:
		var a: float = 0.35 * (1.0 - t["age"] / 0.18)
		draw_rect(Rect2(t["pos"] - position, SIZE), Color(0.5, 0.8, 1.0, a))

	var flicker := invuln > 0.0 and int(invuln * 16.0) % 2 == 0
	var body := Color(0.35, 0.6, 1.0)
	if dashes_left == 0 and not grounded:
		body = Color(0.55, 0.55, 0.75)  # out of dashes, like Celeste's hair colour change
	if flicker:
		body.a = 0.35
	var s := SIZE * squash
	var origin := Vector2((SIZE.x - s.x) / 2.0, SIZE.y - s.y)
	draw_rect(Rect2(origin, s), body)
	# Scarf.
	draw_rect(Rect2(origin + Vector2(0, s.y * 0.35), Vector2(s.x, 4)), Color(0.95, 0.35, 0.3, body.a))
	# Eyes look where we face.
	var eye_y := origin.y + s.y * 0.22
	var ex := origin.x + s.x / 2.0 + facing * 3.0
	draw_rect(Rect2(ex - 4, eye_y, 3, 4), Color(0.05, 0.05, 0.1, body.a))
	draw_rect(Rect2(ex + 2, eye_y, 3, 4), Color(0.05, 0.05, 0.1, body.a))
	# Sword slash.
	if attack_time > 0.0:
		var r := sword_rect()
		r.position -= position
		var arc_center := Vector2(SIZE.x / 2.0, SIZE.y / 2.0)
		var start := -PI / 2.0 if facing > 0 else PI / 2.0
		draw_arc(arc_center, sword_reach, start, start + PI * facing, 12, Color(1, 1, 1, 0.8 * attack_time / 0.12), 4.0)
		draw_rect(r, Color(1, 1, 1, 0.12))
