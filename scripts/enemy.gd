## Monsters. Slimes and brutes patrol ledges, bats sleep on the ceiling until you come close,
## frogs hop at you and spitters lob globs from where they sit.
## position is the top-left corner of the hitbox.
extends Node2D

const Data = preload("res://scripts/data.gd")

var game: Node
var level: Node
var kind := "slime"
var stats: Dictionary
var size := Vector2(24, 18)
var hp := 2
var vel := Vector2.ZERO
var dir := 1
var awake := false
var flash := 0.0
var t := 0.0
var cooldown := 0.0  # frog: time until the next hop; spitter: time until the next shot


func setup(game_node: Node, level_node: Node, enemy_kind: String, cell: Vector2i) -> void:
	game = game_node
	level = level_node
	kind = enemy_kind
	stats = Data.ENEMIES[kind]
	size = stats["size"]
	hp = stats["hp"]
	dir = -1 if randf() < 0.5 else 1
	cooldown = randf_range(0.5, 1.5)
	var T := Data.TILE
	if kind == "bat":
		position = Vector2(cell.x * T + (T - size.x) / 2.0, cell.y * T)
		# Hang from the nearest ceiling above.
		while position.y > T and not level.solid_at(position + Vector2(size.x / 2.0, -2.0)):
			position.y -= T
	else:
		position = Vector2(cell.x * T + (T - size.x) / 2.0, (cell.y + 1) * T - size.y)


func center() -> Vector2:
	return position + size / 2.0


func rect() -> Rect2:
	return Rect2(position, size)


func step(delta: float) -> void:
	t += delta
	flash = max(flash - delta, 0.0)
	var speed: float = stats["speed"]
	match kind:
		"slime", "brute":
			vel.x = dir * speed
			vel.y = min(vel.y + Data.GRAVITY * delta, Data.MAX_FALL)
			var res: Dictionary = level.move_box(position, size, vel * delta)
			position = res["pos"]
			if res["hit_y"]:
				vel.y = 0.0
			if res["hit_x"]:
				dir = -dir
			elif level.on_floor(position, size):
				# Turn around at ledges instead of walking off.
				var ahead := Vector2(position.x + (size.x + 2.0 if dir > 0 else -2.0), position.y + size.y + 4.0)
				if not level.standable_at(ahead):
					dir = -dir
		"frog":
			var player = game.player
			vel.y = min(vel.y + Data.GRAVITY * delta, Data.MAX_FALL)
			var on_ground: bool = level.on_floor(position, size)
			if on_ground and vel.y >= 0.0:
				vel.x = 0.0
				cooldown -= delta
				if cooldown <= 0.0:
					var dx: float = player.center().x - center().x
					if absf(dx) < stats["range"] and absf(player.center().y - center().y) < stats["range"]:
						dir = 1 if dx > 0.0 else -1
					else:
						dir = -1 if randf() < 0.5 else 1
					vel = Vector2(dir * speed, -stats["hop"])
					cooldown = randf_range(1.0, 1.6)
			var res: Dictionary = level.move_box(position, size, vel * delta)
			position = res["pos"]
			if res["hit_y"]:
				vel.y = 0.0
			if res["hit_x"]:
				vel.x = -vel.x * 0.5
				dir = -dir
		"spitter":
			var player = game.player
			vel.x = move_toward(vel.x, 0.0, 600.0 * delta)
			vel.y = min(vel.y + Data.GRAVITY * delta, Data.MAX_FALL)
			var res: Dictionary = level.move_box(position, size, vel * delta)
			position = res["pos"]
			if res["hit_y"]:
				vel.y = 0.0
			var to_player: Vector2 = player.center() - center()
			dir = 1 if to_player.x > 0.0 else -1
			cooldown -= delta
			if cooldown <= 0.0 and to_player.length() < stats["range"]:
				cooldown = stats["cooldown"]
				# Lob it so it comes down near where you're standing.
				var air_time := 0.8
				var v := Vector2(to_player.x / air_time, to_player.y / air_time - 0.5 * 700.0 * air_time)
				game.spawn_shot(center() + Vector2(dir * 8.0, -8.0), v, 700.0, "glob")
		"bat":
			var player = game.player
			if not awake and center().distance_to(player.center()) < stats["wake_range"]:
				awake = true
			if awake:
				var to_player: Vector2 = player.center() - center()
				var wobble := Vector2(0, sin(t * 8.0) * 40.0)
				vel = vel.lerp(to_player.normalized() * speed + wobble, min(delta * 3.0, 1.0))
				var res: Dictionary = level.move_box(position, size, vel * delta)
				position = res["pos"]
	queue_redraw()


func hit(amount: int) -> void:
	hp -= amount
	flash = 0.1
	awake = true
	if hp <= 0:
		game.on_enemy_killed(self)


func _draw() -> void:
	var col: Color = stats["color"]
	if flash > 0.0:
		col = Color.WHITE
	match kind:
		"slime":
			var bob := absf(sin(t * 6.0)) * 3.0
			draw_rect(Rect2(Vector2(0, bob), size - Vector2(0, bob)), col)
			draw_rect(Rect2(Vector2(size.x / 2.0 + dir * 4.0 - 5.0, 5 + bob), Vector2(3, 3)), Color.BLACK)
			draw_rect(Rect2(Vector2(size.x / 2.0 + dir * 4.0 + 2.0, 5 + bob), Vector2(3, 3)), Color.BLACK)
		"brute":
			draw_rect(Rect2(Vector2.ZERO, size), col)
			draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, 6)), col.darkened(0.3))
			draw_rect(Rect2(Vector2(size.x / 2.0 + dir * 5.0 - 2.0, 9), Vector2(4, 4)), Color(1, 0.9, 0.3))
		"frog":
			var crouch := 3.0 if level.on_floor(position, size) and cooldown < 0.25 else 0.0
			draw_rect(Rect2(Vector2(0, 4 + crouch), size - Vector2(0, 4 + crouch)), col)
			draw_circle(Vector2(size.x / 2.0 + dir * 5.0 - 4.0, 5 + crouch), 4.0, col)
			draw_circle(Vector2(size.x / 2.0 + dir * 5.0 + 4.0, 5 + crouch), 4.0, col)
			draw_rect(Rect2(Vector2(size.x / 2.0 + dir * 5.0 - 5.0, 4 + crouch), Vector2(2, 2)), Color.BLACK)
			draw_rect(Rect2(Vector2(size.x / 2.0 + dir * 5.0 + 3.0, 4 + crouch), Vector2(2, 2)), Color.BLACK)
		"spitter":
			# Swells up just before it spits.
			var swell := 3.0 if cooldown < 0.35 else 0.0
			draw_rect(Rect2(Vector2(-swell / 2.0, 6 - swell), Vector2(size.x + swell, size.y - 6 + swell)), col)
			draw_circle(Vector2(size.x / 2.0 + dir * 7.0, 11), 4.0 + swell / 2.0, Color(0.25, 0.15, 0.05))
			draw_rect(Rect2(Vector2(size.x / 2.0 - dir * 3.0 - 2.0, 8), Vector2(4, 4)), Color.BLACK)
		"bat":
			var flap := sin(t * (18.0 if awake else 2.0)) * (6.0 if awake else 1.0)
			var mid := size / 2.0
			draw_colored_polygon(PackedVector2Array([mid, Vector2(-6, mid.y - flap), Vector2(0, mid.y + 4)]), col)
			draw_colored_polygon(PackedVector2Array([mid, Vector2(size.x + 6, mid.y - flap), Vector2(size.x, mid.y + 4)]), col)
			draw_circle(mid, 7.0, col.darkened(0.2))
			draw_rect(Rect2(mid + Vector2(-4, -2), Vector2(2, 2)), Color(1, 0.3, 0.3))
			draw_rect(Rect2(mid + Vector2(2, -2), Vector2(2, 2)), Color(1, 0.3, 0.3))
