## Everything that lasts between missions: banked gold, energy, the to-do list, your squad's
## gear, task charms and a mission in progress. Saved as JSON in the browser's storage (user://).
## Pure logic, no UI, so the self-test can check every number.
extends RefCounted

const Data = preload("res://scripts/data.gd")

const SAVE_PATH := "user://save.json"
const VERSION := 2

# ---------------------------------------------------------------- tuning
const ENERGY_CAP := 12.0          # time only refills you up to this; tasks can push past it
const ENERGY_PER_RUN := 4.0
const ENERGY_REFILL_SECONDS := 900.0  # 1 energy every 15 minutes
const EPIC_PER_DAY := 2
const STEP_GOLD := 5              # every finished step pays a little, however many steps

## Easy / Medium / Hard / Epic.
const TIERS := {
	"easy": {"name": "Easy", "energy": 1, "gold": 15, "charm_chance": 0.05, "color": Color(0.45, 0.85, 0.5)},
	"medium": {"name": "Medium", "energy": 2, "gold": 35, "charm_chance": 0.15, "color": Color(0.4, 0.7, 1.0)},
	"hard": {"name": "Hard", "energy": 4, "gold": 80, "charm_chance": 0.35, "color": Color(1.0, 0.6, 0.25)},
	"epic": {"name": "Epic", "energy": 8, "gold": 180, "charm_chance": 0.75, "color": Color(0.85, 0.45, 1.0)},
}
const TIER_ORDER := ["easy", "medium", "hard", "epic"]

## What the old Blacksmith upgrades cost, so saves from the platformer days get that gold back.
const OLD_UPGRADE_COSTS := {"heart": [60, 150], "sword": [40, 100, 200], "fire": [50, 120, 220]}

var data := {}
var path := SAVE_PATH


static func fresh() -> Dictionary:
	return {
		"version": VERSION,
		"gold": 0,
		"energy": ENERGY_CAP,
		"energy_time": Time.get_unix_time_from_system(),
		"tasks": [],
		"next_id": 1,
		"epic_log": {},          # date -> how many Epic tasks were finished that day
		"epic_limit": true,
		"owned": starter_items(),
		"gear": Data.STARTING_GEAR.duplicate(true),
		"trinkets": [],          # task charms found; the key name is from older saves
		"mission_level": 1,
		"mission": {},           # the mission in progress, if any
		"stats": {"runs": 0, "wins": 0, "tasks_done": 0},
		"seen_intro": false,
	}


static func starter_items() -> Array:
	return Data.ITEMS.keys().filter(func(id): return Data.ITEMS[id].get("cost", -1) == 0)


func load_or_new() -> void:
	data = fresh()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_merge(parsed)


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## Keeps any keys a newer version added, so old saves keep working.
func _merge(loaded: Dictionary) -> void:
	for k in loaded:
		data[k] = loaded[k]
	for k in ["gold", "next_id", "mission_level"]:
		data[k] = int(data[k])
	# Older saves: refund the platformer upgrades and drop the single worn trinket.
	if data.has("upgrades"):
		for k in data["upgrades"]:
			var costs: Array = OLD_UPGRADE_COSTS.get(k, [])
			for i in mini(int(data["upgrades"][k]), costs.size()):
				data["gold"] += costs[i]
		data.erase("upgrades")
	data.erase("equipped")
	data["trinkets"] = data["trinkets"].filter(func(id): return Data.ITEMS.has(id))
	for id in starter_items():
		if not data["owned"].has(id):
			data["owned"].append(id)
	for kind in Data.HERO_ORDER:
		if not (data["gear"].get(kind) is Dictionary):
			data["gear"][kind] = Data.STARTING_GEAR[kind].duplicate()
		for slot in Data.STARTING_GEAR[kind]:
			var id = data["gear"][kind].get(slot, "")
			if not (id is String) or (id != "" and not Data.ITEMS.has(id)):
				data["gear"][kind][slot] = Data.STARTING_GEAR[kind][slot]
	if not (data["mission"] is Dictionary):
		data["mission"] = {}


## A copy-pasteable code holding the whole save, for moving it to another phone or keeping a backup.
func export_code() -> String:
	return Marshalls.utf8_to_base64(JSON.stringify(data))


func import_code(code: String) -> bool:
	code = code.strip_edges()
	# Check it looks like a backup code first, so junk doesn't reach the decoder.
	var b64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")
	if code.length() % 4 != 0 or b64.search(code) == null:
		return false
	var json := JSON.new()
	if json.parse(Marshalls.base64_to_utf8(code)) != OK:
		return false
	var parsed = json.data
	if not (parsed is Dictionary) or not parsed.has("tasks") or not parsed.has("gold"):
		return false
	data = fresh()
	_merge(parsed)
	save()
	return true


# ---------------------------------------------------------------- energy

## Brings energy up to date: +1 per 15 minutes, but only while under the cap.
func tick_energy(now: float) -> void:
	var e: float = data["energy"]
	var elapsed: float = maxf(now - float(data["energy_time"]), 0.0)
	if e < ENERGY_CAP:
		e = minf(ENERGY_CAP, e + elapsed / ENERGY_REFILL_SECONDS)
	data["energy"] = e
	data["energy_time"] = now


func energy(now: float) -> float:
	tick_energy(now)
	return data["energy"]


## Seconds until the next whole point of energy, or -1 when time won't add any.
func seconds_to_next_energy(now: float) -> float:
	var e := energy(now)
	if e >= ENERGY_CAP:
		return -1.0
	return (floorf(e) + 1.0 - e) * ENERGY_REFILL_SECONDS


func can_start_run(now: float) -> bool:
	return energy(now) >= ENERGY_PER_RUN - 0.0001


func start_run(now: float) -> bool:
	if not can_start_run(now):
		return false
	data["energy"] = data["energy"] - ENERGY_PER_RUN
	data["stats"]["runs"] += 1
	save()
	return true


## Banks the mission's gold (plus any Lucky Coin bonus). A win makes the next mission tougher.
## Returns the gold banked.
func end_run(run_gold: int, won: bool) -> int:
	var banked := run_gold + run_gold * gold_bonus() / 100
	data["gold"] += banked
	if won:
		data["stats"]["wins"] += 1
		data["mission_level"] += 1
	data["mission"] = {}
	save()
	return banked


# ---------------------------------------------------------------- tasks

func add_task(task_name: String, tier: String, steps: Array) -> Dictionary:
	var task := {"id": data["next_id"], "name": task_name, "tier": tier, "steps": [], "created": Time.get_unix_time_from_system()}
	for s in steps:
		task["steps"].append({"name": s, "done": false})
	data["next_id"] += 1
	data["tasks"].append(task)
	save()
	return task


func find_task(id: int) -> Dictionary:
	for t in data["tasks"]:
		if int(t["id"]) == id:
			return t
	return {}


func delete_task(id: int) -> void:
	data["tasks"] = data["tasks"].filter(func(t): return int(t["id"]) != id)
	save()


func steps_left(task: Dictionary) -> int:
	return task["steps"].filter(func(s): return not s["done"]).size()


## Ticks off the next unfinished step. Returns the gold it paid, or 0 if none was left.
func complete_step(id: int) -> int:
	var task := find_task(id)
	if task.is_empty():
		return 0
	for s in task["steps"]:
		if not s["done"]:
			s["done"] = true
			data["gold"] += STEP_GOLD
			save()
			return STEP_GOLD
	return 0


func epic_done_today() -> int:
	return int(data["epic_log"].get(Time.get_date_string_from_system(), 0))


## Can this task be completed right now? Epic tasks are limited per day unless the limit is off.
func can_complete(task: Dictionary) -> bool:
	if task["tier"] != "epic" or not data["epic_limit"]:
		return true
	return epic_done_today() < EPIC_PER_DAY


## Finishes the task and opens its chest. Returns what you got:
## {energy, gold, charm ("" if none), name}, or {} if it can't be completed.
func complete_task(id: int, rng: RandomNumberGenerator) -> Dictionary:
	var task := find_task(id)
	if task.is_empty() or not can_complete(task):
		return {}
	var tier: Dictionary = TIERS[task["tier"]]
	tick_energy(Time.get_unix_time_from_system())
	data["energy"] = data["energy"] + tier["energy"]
	var gold: int = tier["gold"] + rng.randi_range(0, tier["gold"] / 4)
	var charm := ""
	var missing := Data.CHARM_ORDER.filter(func(t): return not data["trinkets"].has(t))
	if rng.randf() < tier["charm_chance"]:
		if missing.is_empty():
			gold += tier["gold"]  # you have them all, so take it in gold
		else:
			charm = missing[rng.randi() % missing.size()]
			data["trinkets"].append(charm)
	data["gold"] += gold
	if task["tier"] == "epic":
		var day := Time.get_date_string_from_system()
		data["epic_log"][day] = epic_done_today() + 1
	data["stats"]["tasks_done"] += 1
	data["tasks"].erase(task)
	save()
	return {"energy": tier["energy"], "gold": gold, "charm": charm, "name": task["name"]}


# ---------------------------------------------------------------- armory and squad

func owns(id: String) -> bool:
	return data["owned"].has(id) or data["trinkets"].has(id)


func buy_item(id: String) -> bool:
	var item: Dictionary = Data.ITEMS.get(id, {})
	if item.is_empty() or item.get("task", false) or owns(id) or data["gold"] < item["cost"]:
		return false
	data["gold"] -= item["cost"]
	data["owned"].append(id)
	save()
	return true


## Puts an item on a hero. A charm can only be worn by one hero, so it moves over.
## id "" takes the charm off.
func equip_item(kind: String, slot: String, id: String) -> bool:
	if id != "":
		var item: Dictionary = Data.ITEMS.get(id, {})
		if item.is_empty() or item["slot"] != slot or not owns(id) or (item["hero"] != "" and item["hero"] != kind):
			return false
	elif slot != "charm":
		return false
	if slot == "charm" and id != "":
		for other in Data.HERO_ORDER:
			if data["gear"][other]["charm"] == id:
				data["gear"][other]["charm"] = ""
	data["gear"][kind][slot] = id
	save()
	return true


func wearer(charm: String) -> String:
	for kind in Data.HERO_ORDER:
		if data["gear"][kind]["charm"] == charm:
			return kind
	return ""


## A hero's numbers with their gear on.
func hero_stats(kind: String) -> Dictionary:
	var base: Dictionary = Data.HEROES[kind]
	var st := {"hp": base["hp"], "move": base["move"], "armour": base["armour"], "damage": 0, "range": 0,
		"spell": 0, "focus": 0, "focus_start": 0, "gold": 0}
	for slot in data["gear"][kind]:
		var id: String = data["gear"][kind][slot]
		if id != "" and Data.ITEMS.has(id):
			var mods: Dictionary = Data.ITEMS[id]["mods"]
			for k in mods:
				st[k] += mods[k]
	st["hp"] = maxi(3, st["hp"])
	st["move"] = maxi(1, st["move"])
	st["armour"] = maxi(0, st["armour"])
	return st


## Focus the squad starts each battle with.
func start_focus() -> int:
	var f := Data.FOCUS_START
	for kind in Data.HERO_ORDER:
		f += hero_stats(kind)["focus_start"]
	return f


## Extra mission gold in percent, from charms.
func gold_bonus() -> int:
	var g := 0
	for kind in Data.HERO_ORDER:
		g += hero_stats(kind)["gold"]
	return g


## Full health for everyone, for the start of a mission.
func full_squad_hp() -> Dictionary:
	var hp := {}
	for kind in Data.HERO_ORDER:
		hp[kind] = hero_stats(kind)["hp"]
	return hp


## How kitted out the squad is: counts bought gear, for the Armory's look.
func gear_bought() -> int:
	return data["owned"].filter(func(id): return Data.ITEMS[id]["cost"] > 0).size()
