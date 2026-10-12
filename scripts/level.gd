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


func setup(info: Dictionary, level_depth: int) -> void:
	w = info["w"]
	h = info["h"]
	grid = info["grid"]
	exit_cell = info["exit"]
	depth = level_depth
	gold.clear()
	for cell in info["gold"]:
		var big: bool = randf() < 0.25
		gold.append({"pos": Vector2((cell.x + 0.5) * T, (cell.y + 0.5) * T), "value": 5 if big else 1})
	queue_redraw()


func size_px() -> Vector2:
	return Vector2(w * T, h * T)


func tile(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return Gen.BORDER
	return grid[cy][cx]


func is_solid(cx: int, cy: int) -> bool:
	var t := tile(cx, cy)
	return t == Gen.SOLID or t == Gen.BORDER


func solid_at(p: Vector2) -> bool:
	return is_solid(floori(p.x / T), floori(p.y / T))


## Does a box (top-left pos, size) overlap any tile of the given code?
func box_touches(pos: Vector2, size: Vector2, code: int) -> bool:
	for cy in range(floori(pos.y / T), floori((pos.y + size.y - 0.01) / T) + 1):
		for cx in range(floori(pos.x / T), floori((pos.x + size.x - 0.01) / T) + 1):
			if tile(cx, cy) == code:
				return true
	return false


## Moves a box through the grid, stopping at solid tiles. One axis at a time.
## Returns {pos, hit_x, hit_y}.
func move_box(pos: Vector2, size: Vector2, motion: Vector2) -> Dictionary:
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
		else:
			var row := floori(pos.y / T)
			for cx in range(left, right + 1):
				if is_solid(cx, row):
					pos.y = (row + 1) * T
					hit_y = true
					break
	return {"pos": pos, "hit_x": hit_x, "hit_y": hit_y}


## Is there solid ground directly under the box?
func on_floor(pos: Vector2, size: Vector2) -> bool:
	var row := floori((pos.y + size.y + 1.0) / T)
	for cx in range(floori(pos.x / T), floori((pos.x + size.x - 0.01) / T) + 1):
		if is_solid(cx, row):
			return true
	return false


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
			if t != Gen.SOLID and t != Gen.SPIKES:
				continue
			var mid := Vector2((cx + 0.5) * T, (cy + 0.5) * T)
			if mid.distance_to(center) <= radius + T * 0.3:
				grid[cy][cx] = Gen.AIR
				count += 1
	if count > 0:
		queue_redraw()
	return count


func exit_rect() -> Rect2:
	return Rect2(exit_cell.x * T + 4, exit_cell.y * T - T + 4, T - 8, T * 2 - 4)


func _process(delta: float) -> void:
	exit_pulse += delta
	queue_redraw()


func _draw() -> void:
	var rock := Color(0.36, 0.27, 0.22).lerp(Color(0.25, 0.27, 0.36), (depth - 1) / 2.0)
	var rock_dark := rock.darkened(0.35)
	var rock_top := rock.lightened(0.25)
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
	# Gold.
	for g in gold:
		var big: bool = g["value"] > 1
		var r2 := 8.0 if big else 5.0
		var p: Vector2 = g["pos"] + Vector2(0, sin(exit_pulse * 3.0 + g["pos"].x) * 2.0)
		var col := Color(0.4, 0.95, 0.85) if big else Color(1.0, 0.82, 0.25)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r2), p + Vector2(r2, 0), p + Vector2(0, r2), p + Vector2(-r2, 0)]), col)
	# Exit door with a soft glow.
	var door := exit_rect()
	var glow := 0.5 + 0.5 * sin(exit_pulse * 3.0)
	draw_rect(door.grow(6.0 + 3.0 * glow), Color(1.0, 0.85, 0.4, 0.15 + 0.1 * glow))
	draw_rect(door, Color(0.2, 0.12, 0.05))
	draw_rect(door.grow(-4), Color(0.95, 0.75, 0.35, 0.6 + 0.3 * glow))
