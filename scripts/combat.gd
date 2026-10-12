## The rules of a battle, with no drawing, so the self-test can play thousands of them.
## A battle is a small grid. Each of your heroes can move once and act once per turn.
## The squad shares Focus: it pays for special abilities and sprints, refills a little each
## turn, and glowing crystals on the floor give more.
extends RefCounted

const Data = preload("res://scripts/data.gd")

const FLOOR := 0
const WALL := 1
const CRYSTAL := 2

const SPELLS := ["spark", "fireball", "mend"]
const SHOTS := ["shoot", "aimed", "pin"]
const DIRS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var rng: RandomNumberGenerator
var w := Data.GRID_W
var h := Data.GRID_H
var grid: Array = []    # grid[y][x]
var units: Array = []   # dictionaries, see _make_unit
var focus := 0
var turn := 1
var events: Array = []  # what happened, for the screen to animate: {type, ...}
var gold_found := 0
var next_id := 1
var focus_bonus := 0    # extra Focus per turn from gear


# ---------------------------------------------------------------- setting up

## heroes: [{kind, hp (current), stats}] from the squad; enemies: monster kinds.
func setup(r: RandomNumberGenerator, heroes: Array, enemy_kinds: Array, level: int, start_focus: int) -> void:
	rng = r
	_make_map()
	focus = start_focus
	var hero_cells := _free_cells_in_columns(0, 1)
	for hd in heroes:
		if hd["hp"] <= 0:
			continue
		var u := _make_unit("hero", hd["kind"], hero_cells.pop_back())
		var st: Dictionary = hd["stats"]
		u["max_hp"] = st["hp"]
		u["hp"] = mini(hd["hp"], st["hp"])
		u["move"] = st["move"]
		u["armour"] = st["armour"]
		u["mods"] = st
		focus_bonus += st["focus"]
		units.append(u)
	var enemy_cells := _free_cells_in_columns(w - 3, w - 1)
	for kind in enemy_kinds:
		if enemy_cells.is_empty():
			break
		var e := _make_unit("enemy", kind, enemy_cells.pop_back())
		# Each mission level makes monsters a little tougher.
		e["max_hp"] += (level - 1) * (3 if kind == "boss" else 1)
		e["hp"] = e["max_hp"]
		e["damage"] += (level - 1) / 2
		units.append(e)


func _make_unit(side: String, kind: String, cell: Vector2i) -> Dictionary:
	var base: Dictionary = Data.HEROES[kind] if side == "hero" else Data.ENEMIES[kind]
	var u := {
		"id": next_id, "side": side, "kind": kind, "name": base["name"], "cell": cell,
		"hp": base["hp"], "max_hp": base["hp"], "move": base["move"], "armour": base["armour"],
		"moved": false, "acted": false, "rooted": 0, "color": base["color"], "mods": {},
		"damage": base.get("damage", 0), "range": base.get("range", 1),
	}
	next_id += 1
	return u


## A random room: a few walls (never blocking the way across) and two Focus crystals.
func _make_map() -> void:
	while true:
		grid = []
		for y in h:
			var row := []
			row.resize(w)
			row.fill(FLOOR)
			grid.append(row)
		var walls := rng.randi_range(5, 9)
		for i in walls:
			var c := Vector2i(rng.randi_range(2, w - 4), rng.randi_range(0, h - 1))
			grid[c.y][c.x] = WALL
			# Sometimes a short wall segment instead of a single block.
			if rng.randf() < 0.4:
				var d: Vector2i = DIRS4[rng.randi() % 4]
				var c2 := c + d
				if c2.x >= 2 and c2.x <= w - 4 and c2.y >= 0 and c2.y < h:
					grid[c2.y][c2.x] = WALL
		for i in 2:
			var c := Vector2i(rng.randi_range(2, w - 4), rng.randi_range(0, h - 1))
			if grid[c.y][c.x] == FLOOR:
				grid[c.y][c.x] = CRYSTAL
		if _left_reaches_right():
			return


func _left_reaches_right() -> bool:
	var start := Vector2i(0, 0)
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in DIRS4:
			var n: Vector2i = c + d
			if in_bounds(n) and not seen.has(n) and grid[n.y][n.x] != WALL:
				seen[n] = true
				queue.append(n)
	# Every open tile must be reachable, so nobody is ever walled in.
	for y in h:
		for x in w:
			if grid[y][x] != WALL and not seen.has(Vector2i(x, y)):
				return false
	return true


func _free_cells_in_columns(x0: int, x1: int) -> Array:
	var cells := []
	for x in range(x0, x1 + 1):
		for y in h:
			if grid[y][x] == FLOOR:
				cells.append(Vector2i(x, y))
	# Shuffle with the battle's own dice, so a seed always gives the same battle.
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	return cells


# ---------------------------------------------------------------- queries

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func unit_at(c: Vector2i) -> Dictionary:
	for u in units:
		if u["hp"] > 0 and u["cell"] == c:
			return u
	return {}


func is_open(c: Vector2i) -> bool:
	return in_bounds(c) and grid[c.y][c.x] != WALL and unit_at(c).is_empty()


func alive(side: String) -> Array:
	return units.filter(func(u): return u["side"] == side and u["hp"] > 0)


func result() -> String:
	if alive("enemy").is_empty():
		return "win"
	if alive("hero").is_empty():
		return "lose"
	return ""


static func dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Can a shot go from a to b? Walls block it; units don't.
func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for i in range(1, steps):
		var t := float(i) / steps
		var p := Vector2(a).lerp(Vector2(b), t)
		var c := Vector2i(roundi(p.x), roundi(p.y))
		if grid[c.y][c.x] == WALL:
			return false
	return true


## Tiles a unit can walk to this turn: {cell: steps}. Units block the way.
func reachable(u: Dictionary, max_steps: int) -> Dictionary:
	var out := {u["cell"]: 0}
	var queue := [u["cell"]]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if out[c] >= max_steps:
			continue
		for d in DIRS4:
			var n: Vector2i = c + d
			if not out.has(n) and is_open(n):
				out[n] = out[c] + 1
				queue.append(n)
	return out


func hero_move(u: Dictionary) -> int:
	return maxi(1, u["move"])


func ability_range(u: Dictionary, id: String) -> int:
	var r: int = Data.ABILITIES[id]["range"]
	if id in SHOTS:
		r += u["mods"].get("range", 0)
	return r


## Cells this ability can be aimed at right now.
func targets(u: Dictionary, id: String) -> Array:
	var ab: Dictionary = Data.ABILITIES[id]
	var out := []
	var r := ability_range(u, id)
	if ab.get("around", false):
		return [u["cell"]] if not _adjacent_units(u["cell"], "enemy").is_empty() else []
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if dist(u["cell"], c) > r or not line_of_sight(u["cell"], c):
				continue
			var t := unit_at(c)
			if ab.get("ally", false):
				if not t.is_empty() and t["side"] == "hero" and t["hp"] < t["max_hp"]:
					out.append(c)
			elif ab.has("radius"):
				if grid[c.y][c.x] != WALL:
					out.append(c)
			elif not t.is_empty() and t["side"] == "enemy":
				out.append(c)
	return out


func can_use(u: Dictionary, id: String) -> bool:
	return not u["acted"] and focus >= Data.ABILITIES[id]["cost"] and not targets(u, id).is_empty()


func _adjacent_units(c: Vector2i, side: String) -> Array:
	return units.filter(func(o): return o["hp"] > 0 and o["side"] == side and dist(o["cell"], c) == 1)


# ---------------------------------------------------------------- your turn

## Moves a hero. sprint spends 1 Focus for extra steps.
func move_hero(u: Dictionary, to: Vector2i, sprint := false) -> bool:
	if u["moved"] or u["side"] != "hero":
		return false
	var steps := hero_move(u) + (Data.SPRINT_MOVE if sprint else 0)
	if sprint and focus < 1:
		return false
	var reach := reachable(u, steps)
	if not reach.has(to) or to == u["cell"]:
		return false
	if sprint:
		focus -= 1
	_walk(u, to)
	u["moved"] = true
	return true


func _walk(u: Dictionary, to: Vector2i) -> void:
	var from: Vector2i = u["cell"]
	u["cell"] = to
	events.append({"type": "move", "unit": u["id"], "from": from, "to": to})
	if u["side"] == "hero" and grid[to.y][to.x] == CRYSTAL:
		grid[to.y][to.x] = FLOOR
		focus = mini(Data.FOCUS_MAX, focus + Data.CRYSTAL_FOCUS)
		events.append({"type": "focus", "cell": to, "amount": Data.CRYSTAL_FOCUS})


func use_ability(u: Dictionary, id: String, at: Vector2i) -> bool:
	if not can_use(u, id) or not targets(u, id).has(at):
		return false
	var ab: Dictionary = Data.ABILITIES[id]
	focus -= ab["cost"]
	u["acted"] = true
	events.append({"type": "ability", "unit": u["id"], "ability": id, "at": at})
	var bonus: int = u["mods"].get("damage", 0)
	if id in SPELLS:
		bonus = u["mods"].get("spell", 0) + u["mods"].get("damage", 0) / 2
	if ab.has("heal"):
		_heal(unit_at(at), ab["heal"] + u["mods"].get("spell", 0))
	elif ab.get("around", false):
		for e in _adjacent_units(u["cell"], "enemy"):
			_hurt(e, ab["damage"] + bonus)
	elif ab.has("radius"):
		for o in units.duplicate():
			if o["hp"] > 0 and dist(o["cell"], at) <= ab["radius"]:
				_hurt(o, ab["damage"] + bonus)
	else:
		var t := unit_at(at)
		_hurt(t, ab["damage"] + bonus)
		if t["hp"] > 0 and ab.has("push"):
			_push(t, u["cell"], ab["push"])
		if t["hp"] > 0 and ab.get("root", false):
			t["rooted"] = 1
			events.append({"type": "text", "cell": t["cell"], "text": "Pinned!"})
	return true


func _hurt(t: Dictionary, amount: int) -> void:
	var dealt := maxi(1, amount - t["armour"])
	t["hp"] = maxi(0, t["hp"] - dealt)
	events.append({"type": "hit", "unit": t["id"], "amount": dealt, "cell": t["cell"]})
	if t["hp"] <= 0:
		events.append({"type": "die", "unit": t["id"], "cell": t["cell"]})
		if t["side"] == "enemy":
			gold_found += Data.ENEMIES[t["kind"]]["gold"]


func _heal(t: Dictionary, amount: int) -> void:
	var before: int = t["hp"]
	t["hp"] = mini(t["max_hp"], t["hp"] + amount)
	events.append({"type": "heal", "unit": t["id"], "amount": t["hp"] - before, "cell": t["cell"]})


## Knocks a unit away from a spot. Slamming into a wall, the edge or someone hurts.
func _push(t: Dictionary, from: Vector2i, tiles: int) -> void:
	var d := Vector2i(signi(t["cell"].x - from.x), signi(t["cell"].y - from.y))
	for i in tiles:
		var n: Vector2i = t["cell"] + d
		if not is_open(n):
			events.append({"type": "text", "cell": t["cell"], "text": "Slam!"})
			_hurt(t, 2 + t["armour"])
			return
		_walk(t, n)


func end_player_turn() -> void:
	for u in alive("hero"):
		u["moved"] = true
		u["acted"] = true


func start_player_turn() -> void:
	turn += 1
	focus = mini(Data.FOCUS_MAX, focus + Data.FOCUS_PER_TURN + focus_bonus)
	for u in alive("hero"):
		u["moved"] = false
		u["acted"] = false


# ---------------------------------------------------------------- monsters' turn

## One monster takes its turn.
func enemy_act(e: Dictionary) -> void:
	if e["hp"] <= 0 or alive("hero").is_empty():
		return
	var stats: Dictionary = Data.ENEMIES[e["kind"]]
	if e["kind"] == "boss":
		_boss_act(e)
		return
	if stats["ai"] == "healer":
		var hurt_friends: Array = alive("enemy").filter(func(o): return o["hp"] < o["max_hp"] and o["id"] != e["id"] and dist(o["cell"], e["cell"]) <= e["range"])
		if not hurt_friends.is_empty():
			hurt_friends.sort_custom(func(a, b): return a["hp"] - a["max_hp"] < b["hp"] - b["max_hp"])
			_heal(hurt_friends[0], stats["heal"])
			return
	if _try_attack(e):
		return
	if e["rooted"] > 0:
		e["rooted"] -= 1
		return
	if stats["ai"] in ["ranged", "healer"]:
		_move_to_firing_spot(e)
	else:
		_move_toward_heroes(e)
	_try_attack(e)


func _attackable_heroes(e: Dictionary) -> Array:
	return alive("hero").filter(func(hh): return dist(hh["cell"], e["cell"]) <= e["range"] and line_of_sight(e["cell"], hh["cell"]))


func _try_attack(e: Dictionary) -> bool:
	var hs := _attackable_heroes(e)
	if hs.is_empty():
		return false
	hs.sort_custom(func(a, b): return a["hp"] < b["hp"])
	events.append({"type": "attack", "unit": e["id"], "at": hs[0]["cell"]})
	_hurt(hs[0], e["damage"])
	return true


## Walk as far as possible along the shortest path toward the nearest hero.
func _move_toward_heroes(e: Dictionary) -> void:
	var path := _path_to_heroes(e)
	if path.size() <= 1:
		return
	var steps := mini(e["move"], path.size() - 1)
	# Don't step onto a hero's own tile; the path's last cell is next to one.
	_walk(e, path[steps])


## Breadth-first search from the monster to any tile next to a hero. Returns the cells.
func _path_to_heroes(e: Dictionary) -> Array:
	var start: Vector2i = e["cell"]
	var prev := {start: start}
	var queue := [start]
	var goal := Vector2i(-1, -1)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if not _adjacent_units(c, "hero").is_empty() and c != start:
			goal = c
			break
		for d in DIRS4:
			var n: Vector2i = c + d
			if not prev.has(n) and is_open(n):
				prev[n] = c
				queue.append(n)
	if goal.x < 0:
		return []
	var path := [goal]
	while path[0] != start:
		path.push_front(prev[path[0]])
	return path


## Ranged monsters look for a tile they can shoot from, preferring ones far from heroes.
func _move_to_firing_spot(e: Dictionary) -> void:
	var reach := reachable(e, e["move"])
	var best := Vector2i(-1, -1)
	var best_score := -999
	var here: Vector2i = e["cell"]
	for c in reach:
		e["cell"] = c
		if _attackable_heroes(e).is_empty():
			continue
		var nearest := 99
		for hh in alive("hero"):
			nearest = mini(nearest, dist(hh["cell"], c))
		if nearest > best_score:
			best_score = nearest
			best = c
	e["cell"] = here
	if best.x >= 0 and best != here:
		_walk(e, best)
	elif best.x < 0:
		_move_toward_heroes(e)


## The Bone King: slams everyone next to him every other turn, calls up a skeleton every
## third turn, and otherwise stomps toward you.
func _boss_act(e: Dictionary) -> void:
	if turn % 3 == 0:
		for d in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]:
			var c: Vector2i = e["cell"] + d
			if is_open(c):
				var s := _make_unit("enemy", "skeleton", c)
				units.append(s)
				events.append({"type": "summon", "unit": s["id"], "cell": c})
				break
	var near := _adjacent_units(e["cell"], "hero")
	if near.size() >= 2 or (not near.is_empty() and turn % 2 == 0):
		events.append({"type": "slam", "unit": e["id"], "cell": e["cell"]})
		for hh in near:
			_hurt(hh, e["damage"] - 1)
		return
	if _try_attack(e):
		return
	if e["rooted"] > 0:
		e["rooted"] -= 1
		return
	_move_toward_heroes(e)
	_try_attack(e)


# ---------------------------------------------------------------- auto-play for the self-test

## A simple player for the self-test: each hero heals a badly hurt friend or attacks if it can,
## otherwise walks to a tile it can attack from, or as close to the monsters as it can get.
func auto_hero_turn() -> void:
	for u in alive("hero"):
		if result() != "":
			return
		if not _auto_attack(u):
			var reach := reachable(u, hero_move(u))
			var walk := _distance_to_enemies()
			var here: Vector2i = u["cell"]
			var best: Vector2i = here
			var best_score := -9999
			for c in reach:
				u["cell"] = c
				var score: int = -walk.get(c, 99)
				if _can_attack_somewhere(u):
					score += 100
				u["cell"] = here
				if score > best_score:
					best_score = score
					best = c
			if best != here:
				move_hero(u, best)
			_auto_attack(u)
	end_player_turn()


func _can_attack_somewhere(u: Dictionary) -> bool:
	for id in Data.HEROES[u["kind"]]["abilities"]:
		if Data.ABILITIES[id].has("damage") and focus >= Data.ABILITIES[id]["cost"] and not targets(u, id).is_empty():
			return true
	return false


## Steps from every open tile to the nearest monster, walking round walls.
func _distance_to_enemies() -> Dictionary:
	var out := {}
	var queue := []
	for e in alive("enemy"):
		out[e["cell"]] = 0
		queue.append(e["cell"])
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in DIRS4:
			var n: Vector2i = c + d
			if in_bounds(n) and not out.has(n) and grid[n.y][n.x] != WALL:
				out[n] = out[c] + 1
				queue.append(n)
	return out


func _auto_attack(u: Dictionary) -> bool:
	if u["acted"]:
		return false
	# Hardest-hitting attack first; healing only when nobody can be hit.
	var abilities: Array = Data.HEROES[u["kind"]]["abilities"].duplicate()
	var worth := func(id: String) -> int: return Data.ABILITIES[id].get("damage", -9) * 10 - Data.ABILITIES[id]["cost"]
	abilities.sort_custom(func(a, b): return worth.call(a) > worth.call(b))
	for id in abilities:
		if not can_use(u, id):
			continue
		var ts := targets(u, id)
		var ab: Dictionary = Data.ABILITIES[id]
		if ab.has("heal"):
			# Only heal someone who is down to half health or less.
			ts = ts.filter(func(c): var t := unit_at(c); return t["hp"] * 2 <= t["max_hp"])
		elif ab.has("radius"):
			# Don't fireball your own squad.
			ts = ts.filter(func(c): return units.filter(func(o): return o["hp"] > 0 and o["side"] == "hero" and dist(o["cell"], c) <= 1).is_empty() and not units.filter(func(o): return o["hp"] > 0 and o["side"] == "enemy" and dist(o["cell"], c) <= 1).is_empty())
		if ts.is_empty():
			continue
		# Go for the weakest target.
		ts.sort_custom(func(a, b): return _hp_at(a) < _hp_at(b))
		return use_ability(u, id, ts[0])
	return false


func _hp_at(c: Vector2i) -> int:
	var t := unit_at(c)
	return 999 if t.is_empty() else t["hp"]
