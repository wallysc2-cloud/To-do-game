## A mission: a route of rooms, left to right, that branches so you pick your way to the boss.
## Kept as a plain Dictionary so it can sit in the save and survive closing the app.
##   {level, layers: [[{kind, links: [index in next layer]}]], at: [layer, index],
##    hp: {hero kind: health}, gold, crystal (bonus Focus for the next battle), path: rooms done,
##    boons: blessings picked, bag: gear found}
## Pure logic, no UI, so the self-test can check the routes.
extends RefCounted

const Data = preload("res://scripts/data.gd")

## How likely each room is in the middle of the route.
const ROOM_WEIGHTS := {"battle": 46, "elite": 16, "treasure": 13, "shrine": 12, "crystal": 13}
const FIGHTS := ["battle", "elite", "boss"]


static func generate(rng: RandomNumberGenerator, level: int, squad_hp: Dictionary) -> Dictionary:
	var layers := []
	for i in Data.MISSION_LAYERS:
		var size := 2 if i == 0 else rng.randi_range(2, 3)
		var layer := []
		for j in size:
			layer.append({"kind": "battle" if i == 0 else _pick_kind(rng), "links": []})
		# Every step of the way has at least one fight on offer.
		if layer.filter(func(n): return n["kind"] in FIGHTS).is_empty():
			layer[rng.randi() % size]["kind"] = "battle"
		layers.append(layer)
	# A rest stop is always on offer just before the boss.
	var last: Array = layers[layers.size() - 1]
	if last.filter(func(n): return n["kind"] == "shrine").is_empty():
		last[rng.randi() % last.size()]["kind"] = "shrine"
		if last.filter(func(n): return n["kind"] in FIGHTS).is_empty():
			last.append({"kind": "battle", "links": []})
	layers.append([{"kind": "boss", "links": []}])
	_link(rng, layers)
	return {"level": level, "layers": layers, "at": [-1, 0], "hp": squad_hp.duplicate(), "gold": 0, "crystal": 0, "path": [], "boons": [], "bag": []}


static func _pick_kind(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in ROOM_WEIGHTS:
		total += ROOM_WEIGHTS[k]
	var roll := rng.randi() % total
	for k in ROOM_WEIGHTS:
		roll -= ROOM_WEIGHTS[k]
		if roll < 0:
			return k
	return "battle"


## Joins each room to the rooms roughly ahead of it, sometimes branching, so paths
## rarely cross and every room can be reached.
static func _link(rng: RandomNumberGenerator, layers: Array) -> void:
	for i in layers.size() - 1:
		var here: Array = layers[i]
		var ahead: Array = layers[i + 1]
		var a := here.size()
		var b := ahead.size()
		for j in a:
			var t := 0.5 if a == 1 else float(j) / (a - 1)
			var k := roundi(t * (b - 1))
			var links: Array = [k]
			# Branch to a neighbour now and then.
			var side := k + (1 if rng.randf() < 0.5 else -1)
			if side >= 0 and side < b and rng.randf() < 0.55:
				links.append(side)
			links.sort()
			here[j]["links"] = links
		for k in b:
			var linked := false
			for n in here:
				if n["links"].has(k):
					linked = true
			if not linked:
				var j := roundi(float(k) / maxf(b - 1, 1) * (a - 1))
				here[j]["links"].append(k)
				here[j]["links"].sort()


## Rooms you can walk into next, as [layer, index] pairs.
static func choices(m: Dictionary) -> Array:
	var at: Array = m["at"]
	var layer := int(at[0])
	var out := []
	if layer < 0:
		for j in m["layers"][0].size():
			out.append([0, j])
		return out
	if layer + 1 >= m["layers"].size():
		return out
	for k in m["layers"][layer][int(at[1])]["links"]:
		out.append([layer + 1, int(k)])
	return out


static func room(m: Dictionary, layer: int, index: int) -> Dictionary:
	return m["layers"][layer][index]


static func is_boss(m: Dictionary, layer: int) -> bool:
	return layer == m["layers"].size() - 1


## Heroes still standing.
static func standing(m: Dictionary) -> Array:
	return Data.HERO_ORDER.filter(func(k): return int(m["hp"].get(k, 0)) > 0)


## A mission read back from the save has every number as a decimal; turn them back into whole numbers.
static func normalize(m: Dictionary) -> Dictionary:
	for k in ["level", "gold", "crystal"]:
		m[k] = int(m.get(k, 0))
	m["at"] = [int(m["at"][0]), int(m["at"][1])]
	m["path"] = m.get("path", []).map(func(c): return [int(c[0]), int(c[1])])
	for layer in m["layers"]:
		for n in layer:
			n["links"] = n["links"].map(func(k): return int(k))
	for kind in m["hp"]:
		m["hp"][kind] = int(m["hp"][kind])
	if not m.has("boons"):
		m["boons"] = []
	if not m.has("bag"):
		m["bag"] = []
	for it in m["bag"]:
		it["value"] = int(it["value"])
		for k in it["mods"]:
			if not (it["mods"][k] is String):
				it["mods"][k] = int(it["mods"][k])
	return m


## Is this a sound mission? Every room can be reached from camp and leads on to the boss.
static func check(m: Dictionary) -> String:
	var layers: Array = m["layers"]
	if layers.size() != Data.MISSION_LAYERS + 1 or layers[layers.size() - 1].size() != 1 or layers[layers.size() - 1][0]["kind"] != "boss":
		return "boss is not the last room"
	for i in layers.size() - 1:
		if layers[i].filter(func(n): return n["kind"] in FIGHTS).is_empty():
			return "layer %d has no fight" % i
		for j in layers[i].size():
			if layers[i][j]["links"].is_empty():
				return "room %d,%d is a dead end" % [i, j]
		for k in layers[i + 1].size():
			if layers[i].filter(func(n): return n["links"].has(k)).is_empty():
				return "room %d,%d can't be reached" % [i + 1, k]
	if layers[layers.size() - 2].filter(func(n): return n["kind"] == "shrine").is_empty():
		return "no shrine before the boss"
	return ""
