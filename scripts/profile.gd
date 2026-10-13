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
		"heroes": fresh_heroes(),  # hero kind -> {level, xp}
		"loot": [],              # gear found on missions: see make_loot
		"next_loot": 1,
		"penalty": "",           # what happens when your squad falls; "" until you pick
	}


static func fresh_heroes() -> Dictionary:
	var out := {}
	for kind in Data.HERO_ORDER:
		out[kind] = {"level": 1, "xp": 0}
	return out


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
	for k in ["gold", "next_id", "mission_level", "next_loot"]:
		data[k] = int(data[k])
	for kind in Data.HERO_ORDER:
		if not (data["heroes"].get(kind) is Dictionary):
			data["heroes"][kind] = {"level": 1, "xp": 0}
		for k in ["level", "xp"]:
			data["heroes"][kind][k] = int(data["heroes"][kind].get(k, 1 if k == "level" else 0))
	for item in data["loot"]:
		for k in item["mods"]:
			if not (item["mods"][k] is String):
				item["mods"][k] = int(item["mods"][k])
		item["value"] = int(item["value"])
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
			if not (id is String) or (id != "" and item(id).is_empty()):
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


## Ends a mission and brings home what was found. fell = the whole squad went down,
## which costs what the death setting says; winning or retreating keeps everything.
## Returns {gold (banked), lucky (extra from charms), items (names brought home), lost (text, "" if nothing)}.
func end_run(run_gold: int, won: bool, bag: Array = [], fell := false) -> Dictionary:
	var penalty: String = data["penalty"] if data["penalty"] != "" else "loot"
	var lost := ""
	if fell:
		match penalty:
			"loot":
				if not bag.is_empty():
					lost = "The gear in your bag was lost."
				bag = []
			"bag":
				lost = "The gold and gear you found were lost."
				bag = []
				run_gold = 0
			"hardcore":
				wipe()
				data["mission"] = {}
				save()
				return {"gold": 0, "lucky": 0, "items": [], "lost": "Hardcore: everything starts over. Your task charms are safe."}
	var lucky := run_gold * gold_bonus() / 100
	data["gold"] += run_gold + lucky
	var names := []
	for item in bag:
		names.append(add_loot(item)["name"])
	if won:
		data["stats"]["wins"] += 1
		data["mission_level"] += 1
	data["mission"] = {}
	save()
	return {"gold": run_gold + lucky, "lucky": lucky, "items": names, "lost": lost}


## Hardcore: back to the start. Tasks, energy, stats and task charms stay.
func wipe() -> void:
	var f := fresh()
	for k in ["gold", "owned", "gear", "mission_level", "heroes", "loot", "next_loot"]:
		data[k] = f[k]


## Death settings can only get gentler once picked.
func can_pick_penalty(id: String) -> bool:
	if data["penalty"] == "":
		return true
	return Data.PENALTY_ORDER.find(id) <= Data.PENALTY_ORDER.find(data["penalty"])


func set_penalty(id: String) -> bool:
	if not Data.PENALTIES.has(id) or not can_pick_penalty(id):
		return false
	data["penalty"] = id
	save()
	return true


# ---------------------------------------------------------------- tasks

## daily: the task comes back every day instead of leaving the board, and builds a streak.
func add_task(task_name: String, tier: String, steps: Array, daily := false) -> Dictionary:
	var task := {"id": data["next_id"], "name": task_name, "tier": tier, "steps": [], "created": Time.get_unix_time_from_system()}
	if daily:
		task["daily"] = true
		task["done_on"] = ""
		task["streak"] = 0
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


static func today() -> String:
	return Time.get_date_string_from_system()


## Whole days from one "YYYY-MM-DD" date to another.
static func days_between(a: String, b: String) -> int:
	return roundi((Time.get_unix_time_from_datetime_string(b) - Time.get_unix_time_from_datetime_string(a)) / 86400.0)


func epic_done_today(day := "") -> int:
	return int(data["epic_log"].get(day if day != "" else today(), 0))


## A daily task's streak as of a day. Missing days knock it down a step each, not to zero.
static func streak_on(task: Dictionary, day: String) -> int:
	var streak := int(task.get("streak", 0))
	var last: String = task.get("done_on", "")
	if last == "":
		return 0
	var gap := days_between(last, day)
	return maxi(0, streak - maxi(0, gap - 1))


static func done_today(task: Dictionary, day := "") -> bool:
	return task.get("daily", false) and task.get("done_on", "") == (day if day != "" else today())


## Can this task be completed right now? Daily tasks once a day; Epic tasks are limited
## per day unless the limit is off.
func can_complete(task: Dictionary, day := "") -> bool:
	if done_today(task, day):
		return false
	if task["tier"] != "epic" or not data["epic_limit"]:
		return true
	return epic_done_today(day) < EPIC_PER_DAY


## Finishes the task and opens its chest. Returns what you got:
## {energy, gold, charm ("" if none), name, streak (0 for one-off tasks)}, or {} if it can't be completed.
## A daily task's streak adds to the chest: more gold and a better charm chance.
func complete_task(id: int, rng: RandomNumberGenerator, day := "") -> Dictionary:
	if day == "":
		day = today()
	var task := find_task(id)
	if task.is_empty() or not can_complete(task, day):
		return {}
	var tier: Dictionary = TIERS[task["tier"]]
	tick_energy(Time.get_unix_time_from_system())
	data["energy"] = data["energy"] + tier["energy"]
	var streak := 0
	if task.get("daily", false):
		streak = streak_on(task, day) + 1
		task["streak"] = streak
		task["done_on"] = day
	var bonus := mini(maxi(streak - 1, 0), Data.STREAK_MAX)  # days in a row after the first
	var gold: int = tier["gold"] + rng.randi_range(0, tier["gold"] / 4)
	gold += gold * bonus * Data.STREAK_GOLD / 100
	var charm := ""
	var missing := Data.CHARM_ORDER.filter(func(t): return not data["trinkets"].has(t))
	if rng.randf() < tier["charm_chance"] * (1.0 + 0.1 * bonus):
		if missing.is_empty():
			gold += tier["gold"]  # you have them all, so take it in gold
		else:
			charm = missing[rng.randi() % missing.size()]
			data["trinkets"].append(charm)
	data["gold"] += gold
	if task["tier"] == "epic":
		data["epic_log"][day] = epic_done_today(day) + 1
	data["stats"]["tasks_done"] += 1
	if task.get("daily", false):
		for st in task["steps"]:
			st["done"] = false
	else:
		data["tasks"].erase(task)
	save()
	return {"energy": tier["energy"], "gold": gold, "charm": charm, "name": task["name"], "streak": streak}


# ---------------------------------------------------------------- armory, loot and squad

## Any item by id: shop gear and charms from Data.ITEMS, or found loot ("L12").
func item(id: String) -> Dictionary:
	if Data.ITEMS.has(id):
		return Data.ITEMS[id]
	for it in data["loot"]:
		if it["uid"] == id:
			return it
	return {}


func owns(id: String) -> bool:
	return data["owned"].has(id) or data["trinkets"].has(id) or (not Data.ITEMS.has(id) and not item(id).is_empty())


func buy_item(id: String) -> bool:
	var it: Dictionary = Data.ITEMS.get(id, {})
	if it.is_empty() or it.get("task", false) or owns(id) or data["gold"] < it["cost"]:
		return false
	data["gold"] -= it["cost"]
	data["owned"].append(id)
	save()
	return true


## Puts an item on a hero. A charm can only be worn by one hero, so it moves over.
## id "" takes the charm off.
func equip_item(kind: String, slot: String, id: String) -> bool:
	if id != "":
		var it := item(id)
		if it.is_empty() or it["slot"] != slot or not owns(id) or (it["hero"] != "" and it["hero"] != kind):
			return false
	elif slot != "charm":
		return false
	if id != "" and (slot == "charm" or not Data.ITEMS.has(id)):
		# Charms and found gear are one of a kind, so take them off whoever has them.
		for other in Data.HERO_ORDER:
			if data["gear"][other][slot] == id:
				data["gear"][other][slot] = "" if slot == "charm" else Data.STARTING_GEAR[other][slot]
	data["gear"][kind][slot] = id
	save()
	return true


func wearer(id: String) -> String:
	for kind in Data.HERO_ORDER:
		for slot in data["gear"][kind]:
			if data["gear"][kind][slot] == id:
				return kind
	return ""


## Rolls a random piece of gear. Better missions find better gear more often.
static func make_loot(rng: RandomNumberGenerator, level: int) -> Dictionary:
	var weights := {"common": 60, "rare": 30 + 5 * (level - 1), "epic": 10 + 3 * (level - 1)}
	var total := 0
	for r in weights:
		total += weights[r]
	var roll := rng.randi() % total
	var rarity := "common"
	for r in Data.RARITY_ORDER:
		roll -= weights[r]
		if roll < 0:
			rarity = r
			break
	var rank := Data.RARITY_ORDER.find(rarity)
	var weapon := rng.randf() < 0.6
	var hero := ""
	var base := ""
	var pool: Array
	if weapon:
		hero = Data.HERO_ORDER[rng.randi() % Data.HERO_ORDER.size()]
		var bases: Array = Data.LOOT_WEAPONS[hero]
		base = bases[rng.randi() % bases.size()]
		pool = Data.WEAPON_ROLLS.filter(func(r): return (not r.has("range") or hero == "ranger") and (not r.has("spell") or hero == "mage"))
	else:
		base = Data.LOOT_ARMOUR[rng.randi() % Data.LOOT_ARMOUR.size()]
		pool = Data.ARMOUR_ROLLS
	var mods := {}
	for i in Data.RARITIES[rarity]["rolls"]:
		var r: Dictionary = pool[rng.randi() % pool.size()]
		for k in r:
			mods[k] = mods.get(k, 0) + r[k]
	var element := ""
	if weapon and (rarity == "epic" or (rarity == "rare" and rng.randf() < 0.4)):
		element = Data.ELEMENT_ORDER[rng.randi() % Data.ELEMENT_ORDER.size()]
		mods["element"] = element
	var prefix: String = Data.ELEMENTS[element]["name"] if element != "" else ["Old", "Fine", "Mighty"][rank]
	return {"uid": "", "name": "%s %s" % [prefix, base], "slot": "weapon" if weapon else "armour", "hero": hero,
		"mods": mods, "rarity": rarity, "value": [15, 40, 90][rank] + 5 * level}


## Brings a found item home. Returns it with its id.
func add_loot(it: Dictionary) -> Dictionary:
	var copy := it.duplicate(true)
	copy["uid"] = "L%d" % data["next_loot"]
	data["next_loot"] += 1
	data["loot"].append(copy)
	save()
	return copy


## Sells found gear for gold. Whoever wore it goes back to their starting gear.
func sell_loot(uid: String) -> int:
	var it := item(uid)
	if it.is_empty() or Data.ITEMS.has(uid):
		return 0
	for kind in Data.HERO_ORDER:
		if data["gear"][kind][it["slot"]] == uid:
			data["gear"][kind][it["slot"]] = Data.STARTING_GEAR[kind][it["slot"]]
	data["loot"].erase(it)
	data["gold"] += it["value"]
	save()
	return it["value"]


# ---------------------------------------------------------------- hero levels

static func xp_needed(level: int) -> int:
	return Data.XP_PER_LEVEL * level


func hero_level(kind: String) -> int:
	return data["heroes"][kind]["level"]


## Gives a hero XP. Returns how many levels they went up.
func add_xp(kind: String, amount: int) -> int:
	var h: Dictionary = data["heroes"][kind]
	var ups := 0
	h["xp"] += amount
	while h["level"] < Data.MAX_LEVEL and h["xp"] >= xp_needed(h["level"]):
		h["xp"] -= xp_needed(h["level"])
		h["level"] += 1
		ups += 1
	if h["level"] >= Data.MAX_LEVEL:
		h["xp"] = 0
	return ups


## A hero's numbers with their level and gear.
func hero_stats(kind: String) -> Dictionary:
	var base: Dictionary = Data.HEROES[kind]
	var lvl := hero_level(kind)
	var st := {"hp": base["hp"] + lvl - 1, "move": base["move"], "armour": base["armour"],
		"damage": Data.DAMAGE_LEVELS.filter(func(l): return l <= lvl).size(), "range": 0,
		"spell": 0, "focus": 0, "focus_start": 0, "gold": 0, "element": ""}
	for slot in data["gear"][kind]:
		var id: String = data["gear"][kind][slot]
		var it := item(id) if id != "" else {}
		if it.is_empty():
			continue
		for k in it["mods"]:
			if k == "element":
				st["element"] = it["mods"][k]
			else:
				st[k] += it["mods"][k]
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
	return data["owned"].filter(func(id): return Data.ITEMS.has(id) and Data.ITEMS[id]["cost"] > 0).size()
