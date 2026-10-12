## Runs the whole game: the village, the mission map and battles, plus menus and self-tests.
## A mission costs energy, goes room by room to a boss, and banks its gold when it ends.
extends Node2D

const Data = preload("res://scripts/data.gd")
const ProfileScript = preload("res://scripts/profile.gd")
const VillageScript = preload("res://scripts/village.gd")
const Mission = preload("res://scripts/mission.gd")
const Combat = preload("res://scripts/combat.gd")
const BattleScript = preload("res://scripts/battle.gd")
const MapScript = preload("res://scripts/map.gd")

var state := "village"  # village, map, battle
var rng := RandomNumberGenerator.new()
var ui: CanvasLayer
var overlay: Control
var ui_theme: Theme
var profile: RefCounted
var village: Control
var screen: Control      # the map or the battle on show
var autotest := ""
var test_log := {"battles": 0, "rooms": 0}


func _ready() -> void:
	rng.randomize()
	ui = CanvasLayer.new()
	add_child(ui)
	ui_theme = _make_theme()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			autotest = arg.get_slice("=", 1)
	profile = ProfileScript.new()
	if autotest == "":
		profile.load_or_new()
	else:
		# Self-tests never touch the real save.
		profile.path = "user://selftest.json"
		profile.data = ProfileScript.fresh()
	match autotest:
		"village":
			_test_village()
		"battles":
			_test_battles()
		"missions":
			_test_missions()
		"play":
			get_tree().create_timer(240.0).timeout.connect(func():
				print("PLAYTEST failed: the mission took too long")
				get_tree().quit(1))
			begin_run_from_village()
		_:
			show_village()


func m() -> Dictionary:
	return profile.data["mission"]


func mission_active() -> bool:
	return not m().is_empty()


# ---------------------------------------------------------------- mission flow

## The gate in the village: pay energy and set out, or pick up a mission you left.
func begin_run_from_village() -> void:
	if mission_active():
		show_map()
		return
	if not profile.start_run(Time.get_unix_time_from_system()):
		return
	profile.data["mission"] = Mission.generate(rng, profile.data["mission_level"], profile.full_squad_hp())
	profile.save()
	show_map()


func _set_screen(c: Control) -> void:
	if screen:
		screen.queue_free()
	screen = c
	if village:
		village.hide()
	c.theme = ui_theme
	ui.add_child(c)
	ui.move_child(c, 0)


func show_map() -> void:
	state = "map"
	_clear_overlay()
	Mission.normalize(m())
	var map := Control.new()
	map.set_script(MapScript)
	_set_screen(map)
	map.setup(m(), profile)
	map.picked.connect(enter_room)
	map.retreat_pressed.connect(_ask_retreat)
	if autotest == "play":
		# The self-test bot takes a random path through the rooms.
		var opts := Mission.choices(m())
		var pick: Array = opts[rng.randi() % opts.size()]
		map.tap_room.call_deferred(pick)  # first tap picks it,
		map.tap_room.call_deferred(pick)  # second tap goes in


func enter_room(layer: int, index: int) -> void:
	var kind: String = Mission.room(m(), layer, index)["kind"]
	test_log["rooms"] += 1
	if kind in Mission.FIGHTS:
		start_battle(layer, index, kind)
		return
	_arrive(layer, index)
	var lines := []
	match kind:
		"treasure":
			var g: int = 15 + 6 * m()["level"] + rng.randi_range(0, 10)
			m()["gold"] += g
			lines = ["The chest holds %d gold." % g]
		"shrine":
			for hk in Data.HERO_ORDER:
				var top: int = profile.hero_stats(hk)["hp"]
				var hp: int = m()["hp"][hk]
				m()["hp"][hk] = top / 2 if hp <= 0 else hp + (top - hp + 1) / 2
			lines = ["Your squad heals half their wounds.", "Anyone who fell gets back up."]
		"crystal":
			m()["crystal"] += 3
			lines = ["You gather glowing crystals.", "Your next battle starts with +3 Focus."]
	profile.save()
	show_map()
	if autotest == "":
		_message(Data.ROOM_KINDS[kind]["name"], lines, "Onward", _clear_overlay)


func _arrive(layer: int, index: int) -> void:
	m()["at"] = [layer, index]
	m()["path"].append([layer, index])


func start_battle(layer: int, index: int, kind: String) -> void:
	state = "battle"
	_clear_overlay()
	var lists: Array = Data.ENCOUNTERS[kind]
	var enemies: Array = lists[rng.randi() % lists.size()]
	var heroes := []
	for hk in Data.HERO_ORDER:
		heroes.append({"kind": hk, "hp": m()["hp"][hk], "stats": profile.hero_stats(hk)})
	var c := Combat.new()
	c.setup(rng, heroes, enemies, m()["level"], profile.start_focus() + m()["crystal"])
	var b := Control.new()
	b.set_script(BattleScript)
	_set_screen(b)
	b.setup(c, Data.ROOM_KINDS[kind]["name"])
	if autotest != "":
		b.auto = true
		b.speed = 40.0
	b.finished.connect(_battle_done.bind(layer, index, kind, c))
	b.menu_pressed.connect(_battle_menu)


func _battle_done(result: String, layer: int, index: int, kind: String, c: RefCounted) -> void:
	test_log["battles"] += 1
	for u in c.units:
		if u["side"] == "hero":
			m()["hp"][u["kind"]] = u["hp"]
	m()["crystal"] = 0
	var gold: int = c.gold_found + (15 if kind == "elite" else 0)
	m()["gold"] += gold
	if result != "win":
		_end_mission(false, "Your squad has fallen")
		return
	_arrive(layer, index)
	if kind == "boss":
		_end_mission(true, "The Bone King is beaten!")
		return
	profile.save()
	show_map()
	if autotest == "":
		_message("Victory!", ["+%d gold" % gold], "Onward", _clear_overlay)


func _end_mission(won: bool, headline: String) -> void:
	var found: int = m()["gold"]
	var banked: int = profile.end_run(found, won)
	if autotest == "play":
		print("PLAYTEST result=%s rooms=%d battles=%d gold=%d" % ["win" if won else "lose", test_log["rooms"], test_log["battles"], banked])
		get_tree().quit()
		return
	var lines := ["%d gold goes to the village." % banked]
	if banked > found:
		lines.append("(Your Lucky Coin added %d.)" % (banked - found))
	if won:
		lines.append("Next mission is a little tougher, and pays more.")
	show_village()
	_message(headline, lines, "Back to the village", _clear_overlay)


func _ask_retreat() -> void:
	_message("Retreat?", ["Head home and keep the %d gold found so far. This mission ends." % m()["gold"]], "Retreat", func():
		_end_mission(false, "Back home safe"), "Keep going")


func _battle_menu() -> void:
	_message("Paused", ["Retreat to keep the %d gold found so far. This mission ends." % m()["gold"]], "Retreat", func():
		_end_mission(false, "Back home safe"), "Keep fighting")


# ---------------------------------------------------------------- menus and overlays

func show_village() -> void:
	state = "village"
	if screen:
		screen.queue_free()
		screen = null
	_clear_overlay()
	if village == null:
		village = Control.new()
		village.set_script(VillageScript)
		village.theme = ui_theme
		ui.add_child(village)
		ui.move_child(village, 0)
		village.setup(self, profile)
	else:
		village.close_panel()
	village.show()


## A short message that floats up and fades, e.g. "+5 gold".
func toast(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = 110
	ui.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "offset_top", 60.0, 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.tween_callback(l.queue_free)


## A box with a heading, a few lines and one or two buttons.
func _message(headline: String, lines: Array, ok_text: String, on_ok: Callable, cancel_text := "") -> void:
	var box := _new_overlay(true)
	_label(box, headline, 44)
	for line in lines:
		_label(box, line, 24, Color(1, 1, 1, 0.8))
	_button(box, ok_text, on_ok)
	if cancel_text != "":
		_button(box, cancel_text, _clear_overlay)


func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


func _new_overlay(dim: bool) -> VBoxContainer:
	_clear_overlay()
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = ui_theme
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	if dim:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.72)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 260
	box.offset_right = -260
	box.offset_top = 40
	box.offset_bottom = -40
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	overlay.add_child(box)
	return box


func _make_theme() -> Theme:
	var t := Theme.new()
	var states := {
		"normal": [Color(0.16, 0.16, 0.21), Color(0.3, 0.3, 0.38)],
		"hover": [Color(0.2, 0.2, 0.26), Color(0.4, 0.4, 0.5)],
		"pressed": [Color(0.16, 0.28, 0.5), Color(0.45, 0.7, 1.0)],
		"hover_pressed": [Color(0.18, 0.31, 0.55), Color(0.5, 0.75, 1.0)],
		"disabled": [Color(0.12, 0.12, 0.15), Color(0.2, 0.2, 0.24)],
		"focus": [Color(0, 0, 0, 0), Color(0, 0, 0, 0)],
	}
	for state_name in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state_name][0]
		sb.border_color = states[state_name][1]
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(10)
		t.set_stylebox(state_name, "Button", sb)
	t.set_color("font_color", "Button", Color(0.9, 0.9, 0.95))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	return t


func _label(parent: Control, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- headless self-tests

func _report(tag: String, fails: Array) -> void:
	for f in fails:
		print("%s failed: %s" % [tag, f])
	print("%s checks failures=%d" % [tag, fails.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile.path))
	get_tree().quit(1 if fails.size() > 0 else 0)


## Checks the village rules (energy, tasks, chests, Epic limit, gear, backups)
## and opens every village window to catch script errors.
func _test_village() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String):
		if not ok:
			fails.append(what)
	var p = profile
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var now := Time.get_unix_time_from_system()
	p.data["energy_time"] = now

	# Energy: start full, a mission costs 4, time refills 1 per 15 min but only up to the cap.
	check.call(is_equal_approx(p.energy(now), 12.0), "starts with 12 energy")
	check.call(p.start_run(now), "can start a mission")
	check.call(is_equal_approx(p.energy(now), 8.0), "mission costs 4")
	check.call(is_equal_approx(p.energy(now + 900.0), 9.0), "15 minutes gives 1 energy")
	check.call(is_equal_approx(p.energy(now + 900.0 * 20), 12.0), "time stops at the cap")
	p.data["energy"] = 1.0
	p.data["energy_time"] = now
	check.call(not p.start_run(now), "can't start a mission with 1 energy")

	# Tasks: steps pay a little, finishing pays energy + chest and can go over the cap.
	var t: Dictionary = p.add_task("Do the dishes", "hard", ["Wash", "Dry"])
	var id := int(t["id"])
	var g0: int = p.data["gold"]
	check.call(p.complete_step(id) == 5 and p.complete_step(id) == 5, "steps pay 5 gold each")
	check.call(p.complete_step(id) == 0, "no more steps")
	check.call(p.data["gold"] == g0 + 10, "step gold banked")
	p.data["energy"] = 11.0
	p.data["energy_time"] = Time.get_unix_time_from_system()
	var got: Dictionary = p.complete_task(id, r)
	check.call(got.get("energy", 0) == 4, "hard task gives 4 energy")
	check.call(got.get("gold", 0) >= 80, "hard chest gives at least 80 gold")
	check.call(p.data["energy"] >= 15.0 - 0.01, "tasks can push energy over 12")
	check.call(p.data["tasks"].is_empty(), "finished task leaves the board")

	# Epic limit: 2 a day unless switched off.
	var epics := []
	for i in 3:
		epics.append(int(p.add_task("Epic %d" % i, "epic", [])["id"]))
	check.call(not p.complete_task(epics[0], r).is_empty(), "first epic ok")
	check.call(not p.complete_task(epics[1], r).is_empty(), "second epic ok")
	check.call(p.complete_task(epics[2], r).is_empty(), "third epic blocked by the limit")
	p.data["epic_limit"] = false
	check.call(not p.complete_task(epics[2], r).is_empty(), "limit can be switched off")

	# Chests eventually hand out every charm, never twice.
	for i in 40:
		p.complete_task(int(p.add_task("Chest %d" % i, "epic", [])["id"]), r)
	check.call(p.data["trinkets"].size() == Data.CHARM_ORDER.size(), "all charms found")
	var unique := {}
	for tr in p.data["trinkets"]:
		unique[tr] = true
	check.call(unique.size() == p.data["trinkets"].size(), "no duplicate charms")

	# Armory: buy, equip, stats; charms move between heroes; task charms can't be bought.
	p.data["gold"] = 200
	check.call(p.buy_item("steel_sword"), "buy a steel sword")
	check.call(not p.buy_item("steel_sword"), "can't buy it twice")
	check.call(p.data["gold"] == 140, "steel sword costs 60")
	check.call(not p.buy_item("plate"), "can't afford plate")
	check.call(not p.buy_item("glass_blade"), "charms can't be bought")
	check.call(not p.equip_item("ranger", "weapon", "steel_sword"), "ranger can't use a sword")
	check.call(not p.equip_item("knight", "weapon", "war_axe"), "can't equip what you don't own")
	check.call(p.equip_item("knight", "weapon", "steel_sword"), "knight equips the steel sword")
	check.call(p.equip_item("knight", "charm", "glass_blade"), "knight wears the glass blade")
	var ks: Dictionary = p.hero_stats("knight")
	check.call(ks["damage"] == 3 and ks["hp"] == 9, "sword + glass blade: +3 damage, 9 health (got %s)" % ks)
	check.call(p.equip_item("mage", "charm", "glass_blade") and p.wearer("glass_blade") == "mage", "charm moves to the mage")
	check.call(p.data["gear"]["knight"]["charm"] == "", "and leaves the knight")
	p.equip_item("ranger", "charm", "tiny_crown")
	check.call(p.start_focus() == Data.FOCUS_START + 1, "tiny crown adds starting Focus")
	p.equip_item("knight", "charm", "feather_cloak")
	check.call(p.hero_stats("knight")["move"] == Data.HEROES["knight"]["move"] + 2, "feather cloak adds move")
	p.equip_item("mage", "charm", "lucky_coin")
	var gold_before: int = p.data["gold"]
	check.call(p.end_run(100, true) == 125 and p.data["gold"] == gold_before + 125, "lucky coin: +25% mission gold")
	check.call(p.data["mission_level"] == 2, "a win raises the mission level")

	# Old platformer saves: upgrades are refunded, gear is filled in.
	var old := ProfileScript.new()
	old.path = p.path
	old.data = ProfileScript.fresh()
	old._merge({"gold": 10, "upgrades": {"heart": 2, "sword": 1, "fire": 0}, "trinkets": ["tiny_crown"], "equipped": "tiny_crown", "tasks": []})
	check.call(old.data["gold"] == 10 + 60 + 150 + 40, "old upgrades refunded (got %d)" % old.data["gold"])
	check.call(not old.data.has("upgrades") and old.data["gear"]["mage"]["weapon"] == "oak_staff", "old save gets starting gear")

	# Backup code round trip.
	var before: int = p.data["gold"] + 123
	p.data["gold"] = before
	var code: String = p.export_code()
	p.data["gold"] = 0
	check.call(p.import_code(code) and p.data["gold"] == before, "backup restores gold")
	check.call(not p.import_code("not a code"), "bad backup code is rejected")

	# Open every window once.
	p.data["seen_intro"] = false
	show_village()
	p.add_task("Laundry", "medium", ["Wash", "Hang"])
	for open in [village.open_intro, village.open_quest_board, village.open_armory, village.open_vault]:
		open.call()
	for hk in Data.HERO_ORDER:
		village.open_hero(hk)
	village.finish_task(int(p.add_task("Email", "easy", [])["id"]))
	p.data["energy"] = 0.0
	village.open_gate()
	check.call(state == "village", "gate stays shut with no energy")
	p.data["energy"] = 12.0
	village.open_gate()
	check.call(state == "map" and mission_active(), "gate starts a mission with energy")
	var first: Array = Mission.choices(m())[0]
	enter_room(first[0], first[1])
	check.call(state == "battle", "first room is a battle")
	# Leaving and coming back keeps the mission, and costs no more energy.
	show_village()
	var e_before: float = p.energy(Time.get_unix_time_from_system())
	village.open_gate()
	check.call(state == "map" and is_equal_approx(p.energy(Time.get_unix_time_from_system()), e_before), "gate resumes a mission for free")
	_end_mission(false, "test")
	check.call(not mission_active(), "retreating ends the mission")

	_report("VILLAGETEST", fails)


## Plays thousands of battles with a simple bot and checks the rules hold up:
## battles end, nobody gets stuck, and the win rate is sensible.
func _test_battles() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String):
		if not ok:
			fails.append(what)
	var r := RandomNumberGenerator.new()
	r.seed = 11

	# Rules.
	var c := _test_combat(r, ["skeleton"], 1)
	check.call(c.alive("hero").size() == 3 and c.alive("enemy").size() == 1, "3 heroes vs 1 skeleton")
	var knight: Dictionary = c.alive("hero").filter(func(u): return u["kind"] == "knight")[0]
	var sk: Dictionary = c.alive("enemy")[0]
	var f0: int = c.focus
	var reach: Dictionary = c.reachable(knight, c.hero_move(knight) + Data.SPRINT_MOVE)
	var far: Vector2i = knight["cell"]
	for cc in reach:
		if reach[cc] > reach.get(far, 0):
			far = cc
	check.call(c.move_hero(knight, far, true) and c.focus <= f0 - 1 + Data.CRYSTAL_FOCUS * 2, "sprint moves further for 1 Focus")
	check.call(not c.move_hero(knight, knight["cell"] + Vector2i(1, 0)), "can't move twice")
	# Put the skeleton next to the knight and shield-bash it into a wall.
	_place(c, sk, knight["cell"] + Vector2i(1, 0))
	c.focus = 5
	var hp0: int = sk["hp"]
	check.call(c.use_ability(knight, "bash", sk["cell"]), "shield bash works")
	check.call(sk["hp"] < hp0, "bash hurts")
	check.call(not c.use_ability(knight, "slash", sk["cell"]), "can't act twice")
	# Armour: a hit always does at least 1.
	sk["hp"] = 5
	sk["armour"] = 10
	c._hurt(sk, 2)
	check.call(sk["hp"] == 4, "armour never blocks the last point")
	# Fireball hits friends too.
	c = _test_combat(r, ["skeleton", "skeleton"], 1)
	var mage: Dictionary = c.alive("hero").filter(func(u): return u["kind"] == "mage")[0]
	var ranger: Dictionary = c.alive("hero").filter(func(u): return u["kind"] == "ranger")[0]
	var spot := Vector2i(4, 2)
	_place(c, mage, Vector2i(2, 2))
	_place(c, ranger, spot + Vector2i(0, 1))
	_place(c, c.alive("enemy")[0], spot)
	c.grid[2][3] = Combat.FLOOR
	c.focus = 5
	var rhp: int = ranger["hp"]
	check.call(c.use_ability(mage, "fireball", spot), "fireball can be cast")
	check.call(ranger["hp"] < rhp, "fireball burns a hero standing next to the target")
	# Pinning shot roots.
	c = _test_combat(r, ["brute"], 1)
	ranger = c.alive("hero").filter(func(u): return u["kind"] == "ranger")[0]
	var brute: Dictionary = c.alive("enemy")[0]
	_place(c, ranger, Vector2i(0, 0))
	_place(c, brute, Vector2i(3, 0))
	for x in range(0, 4):
		c.grid[0][x] = Combat.FLOOR
	c.focus = 5
	check.call(c.use_ability(ranger, "pin", brute["cell"]) and brute["rooted"] == 1, "pinning shot roots")
	var bcell: Vector2i = brute["cell"]
	c.end_player_turn()
	c.enemy_act(brute)
	check.call(brute["cell"] == bcell, "a pinned monster doesn't move")

	# Many battles with the bot.
	var lines := []
	for kind in ["battle", "elite", "boss"]:
		var wins := 0
		var turns := 0
		var stuck := 0
		var games := 300
		for i in games:
			var lists: Array = Data.ENCOUNTERS[kind]
			var b := _test_combat(r, lists[r.randi() % lists.size()], 1)
			var res := _autoplay(b)
			if res == "stuck":
				stuck += 1
			if res == "win":
				wins += 1
			turns += b.turn
		# The bot is simple and can get its own heroes in each other's way now and then;
		# more than that means something in the rules is wrong.
		check.call(stuck <= games / 100, "%d %s battles never ended" % [stuck, kind])
		lines.append("%s %d%% won, %.1f turns, %d stuck" % [kind, 100 * wins / games, float(turns) / games, stuck])
	print("BATTLETEST bot results: " + ", ".join(lines))
	_report("BATTLETEST", fails)


func _test_combat(r: RandomNumberGenerator, enemies: Array, level: int) -> RefCounted:
	var heroes := []
	for hk in Data.HERO_ORDER:
		heroes.append({"kind": hk, "hp": 99, "stats": profile.hero_stats(hk)})
	var c := Combat.new()
	c.setup(r, heroes, enemies, level, Data.FOCUS_START)
	return c


func _place(c: RefCounted, u: Dictionary, cell: Vector2i) -> void:
	var other: Dictionary = c.unit_at(cell)
	if not other.is_empty() and other["id"] != u["id"]:
		other["cell"] = u["cell"]
	c.grid[cell.y][cell.x] = Combat.FLOOR
	u["cell"] = cell


## Plays a battle to the end with the bot. Returns win, lose or stuck.
func _autoplay(c: RefCounted) -> String:
	while c.result() == "" and c.turn < 60:
		c.auto_hero_turn()
		for e in c.alive("enemy"):
			c.enemy_act(e)
		c.start_player_turn()
		c.events.clear()
	return c.result() if c.result() != "" else "stuck"


## Generates many missions and checks every route works; then the bot plays some
## whole missions (with wounds carrying over) to see how often a fresh squad wins.
func _test_missions() -> void:
	var fails: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 500:
		var mm := Mission.generate(r, 1, profile.full_squad_hp())
		var err := Mission.check(mm)
		if err != "":
			fails.append("mission %d: %s" % [i, err])
		var saved = JSON.parse_string(JSON.stringify(mm))
		if Mission.check(Mission.normalize(saved)) != "" or Mission.choices(saved).size() != 2:
			fails.append("mission %d doesn't survive saving" % i)
	var wins := 0
	var games := 100
	for i in games:
		var mm := Mission.generate(r, 1, profile.full_squad_hp())
		if _automission(r, mm):
			wins += 1
	print("MISSIONTEST bot won %d of %d fresh-squad missions" % [wins, games])
	_report("MISSIONTEST", fails)


func _automission(r: RandomNumberGenerator, mm: Dictionary) -> bool:
	while true:
		var opts := Mission.choices(mm)
		if opts.is_empty():
			return true
		var c: Array = opts[r.randi() % opts.size()]
		var kind: String = Mission.room(mm, c[0], c[1])["kind"]
		mm["at"] = c
		match kind:
			"shrine":
				for hk in Data.HERO_ORDER:
					var top: int = profile.hero_stats(hk)["hp"]
					mm["hp"][hk] = top / 2 if mm["hp"][hk] <= 0 else mm["hp"][hk] + (top - mm["hp"][hk] + 1) / 2
			"crystal":
				mm["crystal"] += 3
			"battle", "elite", "boss":
				var heroes := []
				for hk in Data.HERO_ORDER:
					heroes.append({"kind": hk, "hp": mm["hp"][hk], "stats": profile.hero_stats(hk)})
				var b := Combat.new()
				var lists: Array = Data.ENCOUNTERS[kind]
				b.setup(r, heroes, lists[r.randi() % lists.size()], 1, Data.FOCUS_START + mm["crystal"])
				mm["crystal"] = 0
				if _autoplay(b) != "win":
					return false
				for u in b.units:
					if u["side"] == "hero":
						mm["hp"][u["kind"]] = u["hp"]
	return false
