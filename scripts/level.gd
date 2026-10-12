## The tile grid: drawing, collision and blasting holes in it.
extends Node2D

const Data = preload("res://scripts/data.gd")
const Gen = preload("res://scripts/level_gen.gd")
const T := Data.TILE

var w := 0
var h := 0
var grid: Array = []
var exit_cell := Vector2i.ZERO
var depth := 1
var exit_pulse := 0.0
var gold: Array = []  # [{pos: Vector2 centre, value: int}]
var exit_open := true  # false in the boss lair until the boss is beaten
var crumbling := {}  # cell -> seconds since it was first stepped on
var game: Node


func setup(info: Dictionary, level_depth: int) -> void:
	w = info["w"]
	h = info["h"]
	grid = info["grid"]
	exit_cell = info["exit"]
	depth = level_depth
	exit_open = not info.has("boss")
	crumbling.clear()
	gold.clear()
	for cell in info["gold"]:
		var big: bool = randf() < 0.25
		add_gold(Vector2((cell.x + 0.5) * T, (cell.y + 0.5) * T), 5 if big else 1)
	queue_redraw()


func add_gold(pos: Vector2, value: int) -> void:
	gold.append({"pos": pos, "value": value})


func size_px() -> Vector2:
	return Vector2(w * T, h * T)


func tile(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return Gen.BORDER
	return grid[cy][cx]


func is_solid(cx: int, cy: int) -> bool:
	var t := tile(cx, cy)
	return t == Gen.SOLID or t == Gen.BORDER or t == Gen.CRUMBLE


func solid_at(p: Vector2) -> bool:
	return is_solid(floori(p.x / T), floori(p.y / T))


## Something a walker can stand on: solid ground or a wooden ledge.
func standable_at(p: Vector2) -> bool:
	return solid_at(p) or tile(floori(p.x / T), floori(p.y / T)) == Gen.PLATFORM


## Does a box (top-left pos, size) overlap any tile of the given code?
func box_touches(pos: Vector2, size: Vector2, code: int) -> bool:
	for cy in range(floori(pos.y / T), floori((pos.y + size.y - 0.01) / T) + 1):
		for cx in range(floori(pos.x / T), floori((pos.x + size.x - 0.01) / T) + 1):
			if tile(cx, cy) == code:
				return true
	return false


## Moves a box through the grid, stopping at solid tiles. One axis at a time.
## Wooden ledges only stop you when you fall onto them from above, unless drop is set.
## Returns {pos, hit_x, hit_y}.
func move_box(pos: Vector2, size: Vector2, motion: Vector2, drop := false) -> Dictionary:
	var hit_x := false
	var hit_y := false
	if motion.x != 0.0:
		pos.x += motion.x
		var top := floori(pos.y / T)
		var bottom := floori((pos.y + size.y - 0.01) / T)
		if motion.x > 0.0:
			var col := floori((pos.x + size.x - 0.01) / T)
			for cy in range(top, bottom + 1):
				if is_solid(col, cy):
					pos.x = col * T - size.x
					hit_x = true
					break
		else:
			var col := floori(pos.x / T)
			for cy in range(top, bottom + 1):
				if is_solid(col, cy):
					pos.x = (col + 1) * T
					hit_x = true
					break
	if motion.y != 0.0:
		var old_bottom := pos.y + size.y
		pos.y += motion.y
		var left := floori(pos.x / T)
		var right := floori((pos.x + size.x - 0.01) / T)
		if motion.y > 0.0:
			var row := floori((pos.y + size.y - 0.01) / T)
			for cx in range(left, right + 1):
				if is_solid(cx, row):
					pos.y = row * T - size.y
					hit_y = true
					break
			if not hit_y and not drop and old_bottom <= row * T + 0.01:
				for cx in range(left, right + 1):
					if tile(cx, row) == Gen.PLATFORM:
						pos.y = row * T - size.y
						hit_y = true
						break
		else:
			var row := floori(pos.y / T)
			for cx in range(left, right + 1):
				if is_solid(cx, row):
					pos.y = (row + 1) * T
					hit_y = true
					break
	return {"pos": pos, "hit_x": hit_x, "hit_y": hit_y}


## Is there ground (or a ledge, unless dropping through) directly under the box?
func on_floor(pos: Vector2, size: Vector2, drop := false) -> bool:
	var bottom := pos.y + size.y
	var row := floori((bottom + 1.0) / T)
	for cx in range(floori(pos.x / T), floori((pos.x + size.x - 0.01) / T) + 1):
		if is_solid(cx, row):
			return true
		if not drop and tile(cx, row) == Gen.PLATFORM and absf(bottom - row * T) < 1.5:
			return true
	return false


## Standing on a wooden ledge with no solid ground under the box?
func on_ledge_only(pos: Vector2, size: Vector2) -> bool:
	return on_floor(pos, size) and not on_floor(pos, size, true)


## Starts the countdown on any crumbling blocks under the box.
func step_on(pos: Vector2, size: Vector2) -> void:
	var row := floori((pos.y + size.y + 1.0) / T)
	for cx in range(floori(pos.x / T), floori((pos.x + size.x - 0.01) / T) + 1):
		var cell := Vector2i(cx, row)
		if tile(cx, row) == Gen.CRUMBLE and not crumbling.has(cell):
			crumbling[cell] = 0.0


## -1 if a wall touches the box's left side, 1 for the right side, 0 for none.
func wall_side(pos: Vector2, size: Vector2) -> int:
	var top := floori((pos.y + 4.0) / T)
	var bottom := floori((pos.y + size.y - 4.0) / T)
	for cy in range(top, bottom + 1):
		if is_solid(floori((pos.x - 2.0) / T), cy):
			return -1
		if is_solid(floori((pos.x + size.x + 1.0) / T), cy):
			return 1
	return 0


## Blows a round hole in the level. Returns how many tiles were destroyed.
func blast(center: Vector2, radius: float) -> int:
	var count := 0
	var r := ceili(radius / T)
	var c := Vector2i(floori(center.x / T), floori(center.y / T))
	for cy in range(c.y - r, c.y + r + 1):
		for cx in range(c.x - r, c.x + r + 1):
			var t := tile(cx, cy)
			if t != Gen.SOLID and t != Gen.SPIKES and t != Gen.CRUMBLE:
				continue
			var mid := Vector2((cx + 0.5) * T, (cy + 0.5) * T)
			if mid.distance_to(center) <= radius + T * 0.3:
				grid[cy][cx] = Gen.AIR
				crumbling.erase(Vector2i(cx, cy))
				count += 1
	if count > 0:
		queue_redraw()
	return count


func exit_rect() -> Rect2:
	return Rect2(exit_cell.x * T + 4, exit_cell.y * T - T + 4, T - 8, T * 2 - 4)


func _process(delta: float) -> void:
	exit_pulse += delta
	for cell in crumbling.keys():
		crumbling[cell] += delta
		if crumbling[cell] >= Data.CRUMBLE_TIME:
			crumbling.erase(cell)
			grid[cell.y][cell.x] = Gen.AIR
			if game:
				game.on_crumble(cell)
	queue_redraw()


func _draw() -> void:
	var rock := Color(0.36, 0.27, 0.22).lerp(Color(0.25, 0.27, 0.36), clampf((depth - 1) / 2.0, 0.0, 1.0))
	var rock_dark := rock.darkened(0.35)
	var rock_top := rock.lightened(0.25)
	var wood := Color(0.62, 0.45, 0.26)
	draw_rect(Rect2(Vector2.ZERO, size_px()), Color(0.08, 0.07, 0.1))
	for cy in h:
		for cx in w:
			var t: int = grid[cy][cx]
			var r := Rect2(cx * T, cy * T, T, T)
			match t:
				Gen.SOLID, Gen.BORDER:
					draw_rect(r, rock_dark if t == Gen.BORDER else rock)
					if not is_solid(cx, cy - 1):
						draw_rect(Rect2(r.position, Vector2(T, 5)), rock_top)
					# A little texture so the walls don't look flat.
					if (cx * 7 + cy * 13) % 5 == 0:
						draw_rect(Rect2(r.position + Vector2(8, 12), Vector2(6, 4)), rock_dark)
				Gen.SPIKES:
					for i in 3:
						var x0 := cx * T + i * T / 3.0
						var pts := PackedVector2Array([Vector2(x0, (cy + 1) * T), Vector2(x0 + T / 6.0, cy * T + 10), Vector2(x0 + T / 3.0, (cy + 1) * T)])
						draw_colored_polygon(pts, Color(0.8, 0.8, 0.85))
				Gen.PLATFORM:
					draw_rect(Rect2(r.position, Vector2(T, 7)), wood)
					draw_rect(Rect2(r.position + Vector2(0, 7), Vector2(T, 2)), wood.darkened(0.4))
					draw_rect(Rect2(r.position + Vector2(T / 2.0 - 2, 9), Vector2(4, 8)), wood.darkened(0.3))
				Gen.CRUMBLE:
					var cell := Vector2i(cx, cy)
					var jitter := Vector2.ZERO
					if crumbling.has(cell):
						jitter = Vector2(sin(exit_pulse * 70.0 + cx) * 2.0, 0)
					var cr := Rect2(r.position + jitter + Vector2(1, 1), Vector2(T - 2, T - 2))
					var col := rock.lightened(0.18)
					draw_rect(cr, col)
					# Cracks.
					var o := cr.position
					draw_line(o + Vector2(6, 4), o + Vector2(14, 15), col.darkened(0.45), 2.0)
					draw_line(o + Vector2(14, 15), o + Vector2(10, 26), col.darkened(0.45), 2.0)
					draw_line(o + Vector2(14, 15), o + Vector2(24, 18), col.darkened(0.45), 2.0)
	# Gold.
	for g in gold:
		var big: bool = g["value"] > 1
		var r2 := 8.0 if big else 5.0
		var p: Vector2 = g["pos"] + Vector2(0, sin(exit_pulse * 3.0 + g["pos"].x) * 2.0)
		var col := Color(0.4, 0.95, 0.85) if big else Color(1.0, 0.82, 0.25)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r2), p + Vector2(r2, 0), p + Vector2(0, r2), p + Vector2(-r2, 0)]), col)
	# Exit door with a soft glow, barred shut while the boss lives.
	var door := exit_rect()
	draw_rect(door, Color(0.2, 0.12, 0.05))
	if exit_open:
		var glow := 0.5 + 0.5 * sin(exit_pulse * 3.0)
		draw_rect(door.grow(6.0 + 3.0 * glow), Color(1.0, 0.85, 0.4, 0.15 + 0.1 * glow))
		draw_rect(door.grow(-4), Color(0.95, 0.75, 0.35, 0.6 + 0.3 * glow))
	else:
		for i in 3:
			var x := door.position.x + 4 + i * (door.size.x - 8) / 2.0
			draw_line(Vector2(x, door.position.y), Vector2(x, door.end.y), Color(0.5, 0.5, 0.55), 3.0)
