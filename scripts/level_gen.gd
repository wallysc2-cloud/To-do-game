## Builds a level the Spelunky way: a 4x4 grid of rooms with a guaranteed path from
## the entrance at the top to the exit at the bottom, each room picked from templates.
extends RefCounted

const Data = preload("res://scripts/data.gd")

const ROOM_W := 10
const ROOM_H := 8

# Tile codes stored in the grid.
const AIR := 0
const SOLID := 1
const SPIKES := 2
const BORDER := 3  # unbreakable outer wall
const PLATFORM := 4  # wooden ledge you can jump up through, or drop through with down + jump
const CRUMBLE := 5  # falls apart a moment after you stand on it

# Template legend:
#   .  air          #  solid          1  solid half the time
#   ^  spikes (on a floor) half the time
#   =  wooden ledge (jump up through it)    c  crumbling block
#   s  slime spot    b  bat spot (ceiling)    r  brute spot    g  gold
#   f  frog spot     p  spitter spot
# Room kinds: 0 = off the path, 1 = open left and right,
# 2 = open left, right and bottom, 3 = open left, right and top.
const TEMPLATES := {
	1: [
		[
			"..........",
			"..........",
			"..===..g..",
			"......===.",
			"..........",
			"...c..cc..",
			".f.....p..",
			"##########",
		],
		[
			"..........",
			"....b.....",
			"..........",
			"#..====..#",
			"..........",
			"..g....g..",
			"...p..^...",
			"##########",
		],
		[
			"..........",
			"..........",
			"...g..g...",
			"..cccccc..",
			"..........",
			"=..f......",
			"..1....1..",
			"##########",
		],
		[
			"..........",
			"..........",
			"....b.....",
			"..........",
			"..11...g..",
			".......##.",
			"..s.......",
			"##########",
		],
		[
			"..........",
			"...b......",
			"..........",
			"....##....",
			"..g.......",
			"..........",
			"......^...",
			"##########",
		],
		[
			"..........",
			"..........",
			"......g...",
			"..1..###..",
			"..........",
			"1.........",
			"##...s..^.",
			"##########",
		],
		[
			"..........",
			"......b...",
			"..........",
			"..........",
			"...g......",
			"..###..1..",
			".r........",
			"##########",
		],
	],
	2: [
		[
			"..........",
			"..........",
			"..===.....",
			"......g...",
			"..........",
			".f..cc....",
			"..........",
			"####..####",
		],
		[
			"..........",
			"......b...",
			"...g......",
			"..====....",
			"..........",
			"......===.",
			"..p.......",
			"###....###",
		],
		[
			"..........",
			"..........",
			"..b.......",
			"......g...",
			"..##..##..",
			"..........",
			".s........",
			"####..####",
		],
		[
			"..........",
			"..........",
			".......b..",
			"..........",
			".1.g......",
			"..##......",
			"......^...",
			"###....###",
		],
		[
			"..........",
			"..........",
			"..g.......",
			".###......",
			"......11..",
			"..........",
			"........s.",
			"####..####",
		],
	],
	3: [
		[
			"..........",
			"..........",
			"..........",
			"...====...",
			"..........",
			".g......f.",
			"cc.......#",
			"##########",
		],
		[
			"..........",
			"..........",
			"..........",
			"....=====.",
			"..........",
			"..g.......",
			".....p..^.",
			"##########",
		],
		[
			"..........",
			"..........",
			"..........",
			"..........",
			"#.......g#",
			"##......##",
			"...s......",
			"##########",
		],
		[
			"..........",
			"..........",
			"..........",
			".1......1.",
			"..........",
			"..g....##.",
			"......^...",
			"##########",
		],
		[
			"..........",
			"..........",
			"..........",
			"..........",
			"g.......1.",
			"##....r..#",
			"....^.....",
			"##########",
		],
	],
	0: [
		[
			"##########",
			"#.g....g.#",
			"#.======.#",
			"#........#",
			"#..f..p..#",
			"#cccccccc#",
			"#........#",
			"##########",
		],
		[
			"##########",
			"#........#",
			"#..g...b.#",
			"#..##....#",
			"#......1.#",
			"#.s....11#",
			"#........#",
			"##########",
		],
		[
			"1111111111",
			"1........1",
			"1.b....g.1",
			"1..####..1",
			"1........1",
			"1.^....s.1",
			"1........1",
			"1111111111",
		],
		[
			"..........",
			".11....11.",
			"...g......",
			"..........",
			".....b....",
			"..####....",
			"........^.",
			"##########",
		],
	],
}


## Returns a dictionary describing the level:
##   w, h: size in tiles; grid: Array of PackedByteArray rows;
##   spawn, exit: Vector2i tile cells; enemies: [{kind, cell}]; gold: [Vector2i]
static func generate(rng: RandomNumberGenerator, depth: int) -> Dictionary:
	var path := _make_path(rng)
	var kinds: Array = path["kinds"]
	var w := Data.ROOMS_X * ROOM_W + 2
	var h := Data.ROOMS_Y * ROOM_H + 2
	var grid: Array = []
	for y in h:
		var row := PackedByteArray()
		row.resize(w)
		row.fill(AIR)
		grid.append(row)
	var enemies: Array = []
	var gold: Array = []

	for ry in Data.ROOMS_Y:
		for rx in Data.ROOMS_X:
			var kind: int = kinds[ry][rx]
			var options: Array = TEMPLATES[kind]
			var tpl: Array = options[rng.randi() % options.size()]
			var flip := rng.randf() < 0.5
			for ty in ROOM_H:
				for tx in ROOM_W:
					var ch: String = tpl[ty][ROOM_W - 1 - tx if flip else tx]
					var cell := Vector2i(1 + rx * ROOM_W + tx, 1 + ry * ROOM_H + ty)
					match ch:
						"#":
							grid[cell.y][cell.x] = SOLID
						"=":
							grid[cell.y][cell.x] = PLATFORM
						"c":
							grid[cell.y][cell.x] = CRUMBLE
						"1":
							if rng.randf() < 0.5:
								grid[cell.y][cell.x] = SOLID
						"^":
							if rng.randf() < 0.4 + 0.15 * depth:
								grid[cell.y][cell.x] = SPIKES
						"s":
							if rng.randf() < 0.55 + 0.15 * depth:
								# Deeper down, some slimes are frogs instead.
								var frog := depth >= 2 and rng.randf() < 0.3
								enemies.append({"kind": "frog" if frog else "slime", "cell": cell})
						"f":
							if rng.randf() < 0.35 + 0.15 * depth:
								enemies.append({"kind": "frog", "cell": cell})
						"p":
							if rng.randf() < 0.25 + 0.15 * depth:
								enemies.append({"kind": "spitter", "cell": cell})
						"b":
							if rng.randf() < 0.45 + 0.15 * depth:
								enemies.append({"kind": "bat", "cell": cell})
						"r":
							if rng.randf() < 0.3 + 0.25 * depth:
								enemies.append({"kind": "brute", "cell": cell})
						"g":
							gold.append(cell)

	# Unbreakable border.
	for x in w:
		grid[0][x] = BORDER
		grid[h - 1][x] = BORDER
	for y in h:
		grid[y][0] = BORDER
		grid[y][w - 1] = BORDER

	var spawn := _floor_cell(grid, path["start"], rng)
	var exit := _floor_cell(grid, path["end"], rng)

	# Keep the spawn and exit safe: no enemies or spikes right next to them.
	enemies = enemies.filter(func(e): return e["cell"].distance_to(spawn) > 4.0 and e["cell"].distance_to(exit) > 2.0)
	for c in [spawn, exit]:
		for dx in range(-1, 2):
			if grid[c.y][c.x + dx] == SPIKES:
				grid[c.y][c.x + dx] = AIR

	return {"w": w, "h": h, "grid": grid, "spawn": spawn, "exit": exit, "enemies": enemies, "gold": gold}


## The Cave King's lair: a flat arena with wooden ledges to dodge shockwaves on.
## The exit on the far side stays shut until the boss is beaten.
static func generate_boss(rng: RandomNumberGenerator) -> Dictionary:
	var w := 42
	var h := 18
	var grid: Array = []
	for y in h:
		var row := PackedByteArray()
		row.resize(w)
		row.fill(AIR)
		grid.append(row)
	for x in w:
		grid[0][x] = BORDER
		for y in range(h - 3, h):
			grid[y][x] = BORDER
	for y in h:
		grid[y][0] = BORDER
		grid[y][w - 1] = BORDER
	# Ledges 3 tiles above the floor, and a higher one in the middle.
	for x in range(7, 13):
		grid[h - 6][x] = PLATFORM
	for x in range(29, 35):
		grid[h - 6][x] = PLATFORM
	for x in range(17, 25):
		grid[h - 9][x] = PLATFORM
	# A few breakable rocks to hide behind.
	for c in [Vector2i(15, h - 4), Vector2i(26, h - 4)]:
		if rng.randf() < 0.7:
			grid[c.y][c.x] = SOLID
	var gold: Array = [Vector2i(9, h - 7), Vector2i(31, h - 7), Vector2i(20, h - 10), Vector2i(21, h - 10)]
	return {"w": w, "h": h, "grid": grid, "spawn": Vector2i(3, h - 4), "exit": Vector2i(w - 4, h - 4),
		"enemies": [], "gold": gold, "boss": Vector2i(w / 2 + 6, h - 4)}


## Random walk from a top room to a bottom room, Spelunky style.
## Returns {kinds: room kind per room, start: first room, end: last room}.
static func _make_path(rng: RandomNumberGenerator) -> Dictionary:
	var kinds: Array = []
	for ry in Data.ROOMS_Y:
		var row: Array = []
		row.resize(Data.ROOMS_X)
		row.fill(0)
		kinds.append(row)
	var x := rng.randi() % Data.ROOMS_X
	var y := 0
	var start := Vector2i(x, y)
	kinds[y][x] = 1
	var dir := -1 if rng.randf() < 0.5 else 1
	while true:
		var roll := rng.randi() % 5
		var go_down := roll == 4
		if not go_down:
			var nx := x + dir
			if nx < 0 or nx >= Data.ROOMS_X:
				dir = -dir
				go_down = true
			else:
				x = nx
				if kinds[y][x] == 0:
					kinds[y][x] = 1
		if go_down:
			if y == Data.ROOMS_Y - 1:
				break
			# This room must drop into the one below.
			kinds[y][x] = 2
			y += 1
			kinds[y][x] = 3
			dir = -1 if rng.randf() < 0.5 else 1
	return {"kinds": kinds, "start": start, "end": Vector2i(x, y)}


## An air cell sitting on solid ground inside the given room, near its middle.
static func _floor_cell(grid: Array, room: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var candidates: Array = []
	for ty in range(1, ROOM_H - 1):
		for tx in range(1, ROOM_W - 1):
			var cell := Vector2i(1 + room.x * ROOM_W + tx, 1 + room.y * ROOM_H + ty)
			var below: int = grid[cell.y + 1][cell.x]
			if grid[cell.y][cell.x] == AIR and grid[cell.y - 1][cell.x] == AIR and (below == SOLID or below == BORDER):
				candidates.append(cell)
	if candidates.is_empty():
		# Carve a spot if a template left nowhere to stand.
		var cell := Vector2i(1 + room.x * ROOM_W + ROOM_W / 2, 1 + room.y * ROOM_H + ROOM_H - 2)
		grid[cell.y][cell.x] = AIR
		grid[cell.y - 1][cell.x] = AIR
		grid[cell.y + 1][cell.x] = SOLID
		return cell
	candidates.sort_custom(func(a, b): return abs(a.x - (room.x * ROOM_W + ROOM_W / 2)) < abs(b.x - (room.x * ROOM_W + ROOM_W / 2)))
	return candidates[rng.randi() % min(3, candidates.size())]
