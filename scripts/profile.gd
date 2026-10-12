## Everything that lasts between runs: banked gold, energy, the to-do list, Blacksmith
## upgrades and task trinkets. Saved as JSON in the browser's storage (user://).
## Pure logic, no UI, so the self-test can check every number.
extends RefCounted

const SAVE_PATH := "user://save.json"
const VERSION := 1

# ---------------------------------------------------------------- tuning
const ENERGY_CAP := 12.0          # time only refills you up to this; tasks can push past it
const ENERGY_PER_RUN := 4.0
const ENERGY_REFILL_SECONDS := 900.0  # 1 energy every 15 minutes
const EPIC_PER_DAY := 2
const STEP_GOLD := 5              # every finished step pays a little, however many steps

## Easy / Medium / Hard / Epic.
const TIERS := {
	"easy": {"name": "Easy", "energy": 1, "gold": 15, "trinket_chance": 0.05, "color": Color(0.45, 0.85, 0.5)},
	"medium": {"name": "Medium", "energy": 2, "gold": 35, "trinket_chance": 0.15, "color": Color(0.4, 0.7, 1.0)},
	"hard": {"name": "Hard", "energy": 4, "gold": 80, "trinket_chance": 0.35, "color": Color(1.0, 0.6, 0.25)},
	"epic": {"name": "Epic", "energy": 8, "gold": 180, "trinket_chance": 0.75, "color": Color(0.85, 0.45, 1.0)},
}
const TIER_ORDER := ["easy", "medium", "hard", "epic"]

## Blacksmith upgrades: permanent, bought with gold. cost[i] buys level i + 1.
const UPGRADES := {
	"heart": {"name": "Tough Heart", "text": "+1 max heart", "cost": [60, 150]},
	"sword": {"name": "Sharper Sword", "text": "Longer reach; at level 3 it hits twice as hard", "cost": [40, 100, 200]},
	"fire": {"name": "Quick Flame", "text": "Fire recharges 12% faster", "cost": [50, 120, 220]},
}
const UPGRADE_ORDER := ["heart", "sword", "fire"]

## Trinkets only come from task chests and are never lost. They change how you play
## rather than making you strictly stronger. Equip one at the Vault.
const TRINKETS := {
	"lucky_coin": {"name": "Lucky Coin", "text": "Gold pickups sometimes count double"},
	"feather_cloak": {"name": "Feather Cloak", "text": "Jump higher and fall slower, but run a little slower"},
	"ember_ring": {"name": "Ember Ring", "text": "Bigger explosions, but Fire recharges slower"},
	"glass_blade": {"name": "Glass Blade", "text": "Sword hits twice as hard, but 1 less heart"},
	"tiny_crown": {"name": "Tiny Crown", "text": "Just looks great. Wear it with pride"},
}
const TRINKET_ORDER := ["lucky_coin", "feather_cloak", "ember_ring", "glass_blade", "tiny_crown"]

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
		"upgrades": {"heart": 0, "sword": 0, "fire": 0},
		"trinkets": [],
		"equipped": "",
		"stats": {"runs": 0, "wins": 0, "tasks_done": 0},
		"seen_intro": false,
	}


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
	for k in ["gold", "next_id"]:
		data[k] = int(data[k])
	for k in data["upgrades"]:
		data["upgrades"][k] = int(data["upgrades"][k])


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


func end_run(run_gold: int, won: bool) -> void:
	data["gold"] += run_gold
	if won:
		data["stats"]["wins"] += 1
	save()


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
## {energy, gold, trinket ("" if none)}, or {} if it can't be completed.
func complete_task(id: int, rng: RandomNumberGenerator) -> Dictionary:
	var task := find_task(id)
	if task.is_empty() or not can_complete(task):
		return {}
	var tier: Dictionary = TIERS[task["tier"]]
	tick_energy(Time.get_unix_time_from_system())
	data["energy"] = data["energy"] + tier["energy"]
	var gold: int = tier["gold"] + rng.randi_range(0, tier["gold"] / 4)
	var trinket := ""
	var missing := TRINKET_ORDER.filter(func(t): return not data["trinkets"].has(t))
	if rng.randf() < tier["trinket_chance"]:
		if missing.is_empty():
			gold += tier["gold"]  # you have them all, so take it in gold
		else:
			trinket = missing[rng.randi() % missing.size()]
			data["trinkets"].append(trinket)
	data["gold"] += gold
	if task["tier"] == "epic":
		var day := Time.get_date_string_from_system()
		data["epic_log"][day] = epic_done_today() + 1
	data["stats"]["tasks_done"] += 1
	data["tasks"].erase(task)
	save()
	return {"energy": tier["energy"], "gold": gold, "trinket": trinket, "name": task["name"]}


# ---------------------------------------------------------------- blacksmith and vault

func upgrade_level(id: String) -> int:
	return int(data["upgrades"].get(id, 0))


## Cost of the next level, or -1 when maxed out.
func upgrade_cost(id: String) -> int:
	var costs: Array = UPGRADES[id]["cost"]
	var lvl := upgrade_level(id)
	return costs[lvl] if lvl < costs.size() else -1


func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or data["gold"] < cost:
		return false
	data["gold"] -= cost
	data["upgrades"][id] = upgrade_level(id) + 1
	save()
	return true


func total_upgrades() -> int:
	var n := 0
	for id in UPGRADE_ORDER:
		n += upgrade_level(id)
	return n


func equip(trinket: String) -> void:
	if trinket == "" or data["trinkets"].has(trinket):
		data["equipped"] = trinket
		save()


## Sets the hero's starting stats from upgrades and the equipped trinket.
func apply_to_player(p: Object) -> void:
	p.max_hearts += upgrade_level("heart")
	p.sword_reach *= 1.0 + 0.2 * upgrade_level("sword")
	if upgrade_level("sword") >= 3:
		p.sword_damage = 2
	p.fire_cooldown *= pow(0.88, upgrade_level("fire"))
	match data["equipped"]:
		"lucky_coin":
			p.lucky = true
		"feather_cloak":
			p.jump_mult = 1.08
			p.fall_mult = 0.82
			p.run_mult = 0.9
		"ember_ring":
			p.blast_radius *= 1.25
			p.fire_cooldown *= 1.2
		"glass_blade":
			p.sword_damage *= 2
			p.max_hearts -= 1
		"tiny_crown":
			p.crown = true
	p.hearts = p.max_hearts
