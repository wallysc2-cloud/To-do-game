## The home village: the screen between missions. Tap a building to use it.
##   Quest Board: your to-do list. Finishing tasks gives energy, gold and a chest.
##   Armory: buy and equip weapons, armour and charms for your three heroes.
##   Vault: the charms you've found in task chests, your record, and save backups.
##   Gate: set out on a mission for 4 energy.
extends Control

const Profile = preload("res://scripts/profile.gd")
const Data = preload("res://scripts/data.gd")

var game: Node
var profile: RefCounted
var panel: Control  # the open window, if any
var rng := RandomNumberGenerator.new()
var buildings := {}  # id -> Rect2 where it's drawn (and tapped)
var tick := 0.0
var top_label: Label
var energy_label: Label
var draft := {}  # the task being written: {name, tier, steps}


func setup(game_node: Node, p: RefCounted) -> void:
	game = game_node
	profile = p
	rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	top_label = _label(self, "", 28, Color(1, 0.85, 0.35))
	top_label.position = Vector2(24, 16)
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	energy_label = _label(self, "", 24, Color(0.6, 0.9, 1.0))
	energy_label.position = Vector2(24, 56)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	energy_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	resized.connect(_layout)
	_layout()
	_refresh()
	if not profile.data["seen_intro"]:
		open_intro()
	elif profile.data["penalty"] == "":
		open_penalty()


func _layout() -> void:
	var w := size.x if size.x > 0.0 else 1280.0
	var ground := 560.0
	buildings = {
		"quests": Rect2(w * 0.13 - 90, ground - 170, 180, 170),
		"smith": Rect2(w * 0.37 - 115, ground - 200, 230, 200),
		"vault": Rect2(w * 0.61 - 95, ground - 175, 190, 175),
		"cave": Rect2(w * 0.85 - 110, ground - 210, 220, 210),
	}
	queue_redraw()


func _process(delta: float) -> void:
	tick += delta
	if tick > 0.5:
		tick = 0.0
		_refresh()
	queue_redraw()


func _refresh() -> void:
	var now := Time.get_unix_time_from_system()
	var e: float = profile.energy(now)
	top_label.text = "Gold %d" % profile.data["gold"]
	var line := "Energy %d / %d" % [floori(e), int(Profile.ENERGY_CAP)]
	var wait: float = profile.seconds_to_next_energy(now)
	if wait >= 0.0:
		line += "   +1 in %d:%02d" % [int(wait) / 60, int(wait) % 60]
	energy_label.text = line


func _gui_input(event: InputEvent) -> void:
	if panel:
		return
	var tapped := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
		pos = event.position
	if not tapped:
		return
	for id in buildings:
		if buildings[id].grow(10.0).has_point(pos):
			accept_event()
			match id:
				"quests":
					open_quest_board()
				"smith":
					open_armory()
				"vault":
					open_vault()
				"cave":
					open_gate()
			return


# ---------------------------------------------------------------- drawing the village

func _draw() -> void:
	var w := size.x
	var h := size.y
	var t := Time.get_ticks_msec() / 1000.0
	# Dusk sky, distant hills and the ground.
	draw_rect(Rect2(0, 0, w, h), Color(0.16, 0.18, 0.32))
	draw_rect(Rect2(0, h * 0.45, w, h * 0.35), Color(0.22, 0.22, 0.38))
	for i in 7:
		var cx := w * (i / 6.0)
		draw_circle(Vector2(cx, 470), 140.0 + 30.0 * sin(i * 1.7), Color(0.2, 0.26, 0.3))
	draw_rect(Rect2(0, 560, w, h - 560), Color(0.25, 0.36, 0.22))
	draw_rect(Rect2(0, 560, w, 8), Color(0.35, 0.5, 0.28))
	for i in 12:
		draw_circle(Vector2(w * (i + 0.5) / 12.0, 30 + 18 * sin(i * 2.3)), 2.0, Color(1, 1, 0.9, 0.5 + 0.3 * sin(t * 2.0 + i)))

	var font := ThemeDB.fallback_font
	var q: Rect2 = buildings["quests"]
	# Quest Board: a notice board with one note per open task.
	draw_rect(Rect2(q.position.x + 20, q.position.y + 40, 10, q.size.y - 40), Color(0.4, 0.28, 0.16))
	draw_rect(Rect2(q.end.x - 30, q.position.y + 40, 10, q.size.y - 40), Color(0.4, 0.28, 0.16))
	var board := Rect2(q.position.x, q.position.y + 10, q.size.x, 110)
	draw_rect(board, Color(0.55, 0.38, 0.2))
	draw_rect(board.grow(-6), Color(0.66, 0.48, 0.28))
	var tasks: Array = profile.data["tasks"]
	for i in mini(tasks.size(), 8):
		var col: Color = Profile.TIERS[tasks[i]["tier"]]["color"]
		var note := Rect2(board.position.x + 14 + (i % 4) * 40, board.position.y + 14 + (i / 4) * 46, 30, 36)
		draw_rect(note, Color(0.95, 0.92, 0.82))
		draw_rect(Rect2(note.position, Vector2(note.size.x, 6)), col)
	_building_label(q, "Quest Board", "%d task%s" % [tasks.size(), "" if tasks.size() == 1 else "s"])

	# Armory: grows a bigger chimney and a banner for each piece of gear bought.
	var s: Rect2 = buildings["smith"]
	var lvl: int = mini(profile.gear_bought(), 8)
	var house := Rect2(s.position.x + 10, s.position.y + 80, s.size.x - 20, s.size.y - 80)
	draw_rect(house, Color(0.45, 0.35, 0.3))
	draw_colored_polygon(PackedVector2Array([Vector2(s.position.x, house.position.y), Vector2(s.get_center().x, s.position.y + 20), Vector2(s.end.x, house.position.y)]), Color(0.55, 0.22, 0.18))
	var chimney := Rect2(s.end.x - 60, s.position.y + 10 - lvl * 4, 24, 60 + lvl * 4)
	draw_rect(chimney, Color(0.35, 0.3, 0.3))
	for i in 3:
		var age := fmod(t * 0.6 + i / 3.0, 1.0)
		draw_circle(Vector2(chimney.get_center().x + sin(t + i) * 6.0, chimney.position.y - age * 50.0), 6.0 + age * 8.0, Color(0.7, 0.7, 0.75, 0.4 * (1.0 - age)))
	var glow := 0.6 + 0.4 * sin(t * 4.0)
	draw_rect(Rect2(house.position.x + 20, house.position.y + 30, 60, house.size.y - 30), Color(1.0, 0.5, 0.15, glow))
	draw_rect(Rect2(house.end.x - 80, house.end.y - 40, 50, 14), Color(0.25, 0.25, 0.28))  # anvil
	draw_rect(Rect2(house.end.x - 70, house.end.y - 26, 30, 26), Color(0.2, 0.2, 0.22))
	for i in lvl:
		var bx := s.position.x + 18 + i * 26
		draw_line(Vector2(bx, house.position.y), Vector2(bx, house.position.y - 40), Color(0.3, 0.2, 0.1), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(bx, house.position.y - 40), Vector2(bx + 18, house.position.y - 33), Vector2(bx, house.position.y - 26)]), Color(1.0, 0.8, 0.3))
	_building_label(s, "Armory", "Gear for your squad")

	# Vault: stone strongroom; shows how many charms you've found.
	var v: Rect2 = buildings["vault"]
	var vb := Rect2(v.position.x, v.position.y + 50, v.size.x, v.size.y - 50)
	draw_rect(vb, Color(0.5, 0.52, 0.58))
	for row in 4:
		draw_line(Vector2(vb.position.x, vb.position.y + 30 * row + 20), Vector2(vb.end.x, vb.position.y + 30 * row + 20), Color(0.4, 0.42, 0.48), 2.0)
	draw_rect(Rect2(v.position.x - 8, v.position.y + 36, v.size.x + 16, 18), Color(0.42, 0.44, 0.5))
	var door := Rect2(v.get_center().x - 30, vb.end.y - 80, 60, 80)
	draw_rect(door, Color(0.3, 0.25, 0.2))
	draw_circle(door.get_center(), 10.0, Color(0.85, 0.7, 0.3))
	var found: int = profile.data["trinkets"].size()
	for i in found:
		draw_circle(Vector2(v.position.x + 20 + i * 36, v.position.y + 20), 9.0, Color(1.0, 0.8, 0.3, 0.7 + 0.3 * sin(t * 3.0 + i)))
	_building_label(v, "Vault", "%d / %d charms" % [found, Data.CHARM_ORDER.size()])

	# The crypt gate: where missions start.
	var c: Rect2 = buildings["cave"]
	draw_circle(Vector2(c.get_center().x, c.end.y), c.size.x * 0.62, Color(0.3, 0.26, 0.24))
	draw_circle(Vector2(c.get_center().x, c.end.y + 10), c.size.x * 0.3, Color(0.06, 0.05, 0.08))
	var torch := 0.7 + 0.3 * sin(t * 9.0)
	for side in [-1.0, 1.0]:
		var tp := Vector2(c.get_center().x + side * 80, c.end.y - 70)
		draw_rect(Rect2(tp.x - 3, tp.y, 6, 30), Color(0.4, 0.28, 0.16))
		draw_circle(tp, 9.0 * torch, Color(1.0, 0.6, 0.2, 0.9))
	if game.mission_active():
		_building_label(c, "Continue mission", "Mission %d" % profile.data["mission"]["level"], Color(0.6, 0.9, 1.0))
	else:
		var ok: bool = profile.can_start_run(Time.get_unix_time_from_system())
		_building_label(c, "Set out", "Mission %d   %d energy" % [profile.data["mission_level"], int(Profile.ENERGY_PER_RUN)], Color(0.6, 0.9, 1.0) if ok else Color(1, 0.5, 0.45))
	draw_string(font, Vector2(24, size.y - 24), "Tap a building", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.45))


func _building_label(r: Rect2, title: String, sub: String, sub_col := Color(1, 1, 1, 0.75)) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(r.position.x - 40, r.end.y + 40), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 80, 26, Color.WHITE)
	draw_string(font, Vector2(r.position.x - 40, r.end.y + 70), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 80, 20, sub_col)


# ---------------------------------------------------------------- windows

func open_intro() -> void:
	var box := _open_panel("Welcome to the village")
	_label(box, "Your real to-do list powers your squad.", 24)
	_label(box, "Add tasks at the Quest Board. Finishing one gives energy, gold and a treasure chest. Chests can hold charms you can't get any other way.", 20, Color(1, 1, 1, 0.8))
	_label(box, "Each mission costs %d energy. Energy also comes back slowly by itself, 1 every 15 minutes, up to %d." % [int(Profile.ENERGY_PER_RUN), int(Profile.ENERGY_CAP)], 20, Color(1, 1, 1, 0.8))
	_label(box, "On a mission you pick a route of rooms to the boss. Battles are turn by turn: tap a hero, tap a blue tile to move, then attack or use an ability. Abilities cost Focus, which the squad shares. Grab the glowing crystals for more.", 20, Color(1, 1, 1, 0.8))
	_label(box, "Winning battles levels up your heroes, and you might find gear to bring home. Spend gold at the Armory.", 20, Color(1, 1, 1, 0.8))
	_button(box, "Let's go", func():
		profile.data["seen_intro"] = true
		profile.save()
		if profile.data["penalty"] == "":
			open_penalty()
		else:
			close_panel())


func open_quest_board() -> void:
	var box := _open_panel("Quest Board")
	_label(box, "Finish a task for energy, gold and a chest. Each finished step pays %d gold." % Profile.STEP_GOLD, 20, Color(1, 1, 1, 0.7))
	_button(box, "+ New task", start_new_task)
	var tasks: Array = profile.data["tasks"]
	if tasks.is_empty():
		_label(box, "No tasks yet. Add something you need to do today.", 22, Color(1, 1, 1, 0.55))
	for task in tasks:
		box.add_child(_task_row(task))
	var limit := CheckButton.new()
	limit.text = "Limit Epic tasks to %d a day" % Profile.EPIC_PER_DAY
	limit.add_theme_font_size_override("font_size", 20)
	limit.button_pressed = profile.data["epic_limit"]
	limit.toggled.connect(func(on: bool):
		profile.data["epic_limit"] = on
		profile.save())
	box.add_child(limit)


func _task_row(task: Dictionary) -> Control:
	var tier: Dictionary = Profile.TIERS[task["tier"]]
	var row := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	var badge := Label.new()
	badge.text = tier["name"]
	badge.custom_minimum_size = Vector2(90, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", tier["color"])
	badge.add_theme_font_size_override("font_size", 20)
	hb.add_child(badge)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	var title := Label.new()
	title.text = task["name"]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 22)
	info.add_child(title)
	if task.get("daily", false):
		var dl := Label.new()
		var streak: int = Profile.streak_on(task, Profile.today())
		dl.text = "Every day" + ("   %d-day streak" % streak if streak > 0 else "") + ("   Done today" if Profile.done_today(task) else "")
		dl.add_theme_font_size_override("font_size", 18)
		dl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		info.add_child(dl)
	var steps: Array = task["steps"]
	var left: int = profile.steps_left(task)
	if not steps.is_empty():
		var next := ""
		for s in steps:
			if not s["done"]:
				next = "  Next: " + s["name"]
				break
		var sl := Label.new()
		sl.text = "Steps %d / %d%s" % [steps.size() - left, steps.size(), next]
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.add_theme_font_size_override("font_size", 18)
		sl.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		info.add_child(sl)
	var id := int(task["id"])
	if left > 0 and not Profile.done_today(task):
		_small_button(hb, "Step done", func():
			var g: int = profile.complete_step(id)
			if g > 0:
				game.toast("+%d gold" % g)
			open_quest_board())
	var done := _small_button(hb, "Done!", func(): finish_task(id))
	if Profile.done_today(task):
		done.disabled = true
		done.text = "See you tomorrow"
	elif not profile.can_complete(task):
		done.disabled = true
		done.text = "Epic limit"
	var del := Button.new()
	del.text = "X"
	del.custom_minimum_size = Vector2(56, 56)
	del.add_theme_font_size_override("font_size", 20)
	hb.add_child(del)
	del.pressed.connect(func():
		# Two taps to delete, so a stray tap doesn't lose a task.
		if del.text == "Sure?":
			profile.delete_task(id)
			open_quest_board()
		else:
			del.text = "Sure?")
	return row


func start_new_task() -> void:
	draft = {"name": "", "tier": "", "steps": [], "daily": false}
	_ask_text("What do you need to do?", func(text: String):
		if text.strip_edges() == "":
			open_quest_board()
			return
		draft["name"] = text.strip_edges()
		_pick_tier())


func _pick_tier() -> void:
	var box := _open_panel("How hard is it?")
	_label(box, draft["name"], 24)
	_label(box, "Be honest: hard or boring tasks are worth more.", 20, Color(1, 1, 1, 0.65))
	for id in Profile.TIER_ORDER:
		var tier: Dictionary = Profile.TIERS[id]
		var b := _button(box, "%s   +%d energy, %s chest" % [tier["name"], tier["energy"], tier["name"].to_lower()], func():
			draft["tier"] = id
			_edit_steps())
		b.add_theme_color_override("font_color", tier["color"])


func _edit_steps() -> void:
	var box := _open_panel("Break it into steps?")
	_label(box, "Optional. Each step pays %d gold when you tick it off; the chest comes when the whole task is done." % Profile.STEP_GOLD, 20, Color(1, 1, 1, 0.65))
	for i in draft["steps"].size():
		_label(box, "%d. %s" % [i + 1, draft["steps"][i]], 22)
	_button(box, "+ Add a step", func():
		_ask_text("Step %d" % (draft["steps"].size() + 1), func(text: String):
			if text.strip_edges() != "":
				draft["steps"].append(text.strip_edges())
			_edit_steps()))
	_button(box, "Repeats every day: %s" % ("Yes" if draft["daily"] else "No"), func():
		draft["daily"] = not draft["daily"]
		_edit_steps())
	_button(box, "Save task", func():
		profile.add_task(draft["name"], draft["tier"], draft["steps"], draft["daily"])
		open_quest_board())


func finish_task(id: int) -> void:
	var got: Dictionary = profile.complete_task(id, rng)
	if got.is_empty():
		return
	var box := _open_panel("Task complete!")
	_label(box, got["name"], 24)
	_label(box, "+%d energy" % got["energy"], 30, Color(0.6, 0.9, 1.0))
	_label(box, "The chest holds %d gold" % got["gold"], 30, Color(1, 0.85, 0.35))
	if got["streak"] > 1:
		_label(box, "%d days in a row! +%d%% gold and a better charm chance." % [got["streak"], mini(got["streak"] - 1, Data.STREAK_MAX) * Data.STREAK_GOLD], 22, Color(0.6, 0.9, 1.0))
	elif got["streak"] == 1:
		_label(box, "Come back tomorrow to start a streak for a bigger chest.", 20, Color(0.6, 0.9, 1.0))
	if got["charm"] != "":
		var item: Dictionary = Data.ITEMS[got["charm"]]
		_label(box, "...and a charm: %s!" % item["name"], 30, Color(0.9, 0.6, 1.0))
		_label(box, "%s. Only tasks give these. Put it on a hero at the Armory." % item["text"], 20, Color(1, 1, 1, 0.75))
	_button(box, "Nice!", open_quest_board)


func open_armory() -> void:
	var box := _open_panel("Armory")
	_label(box, "You have %d gold. Gear you buy is yours for good, and gear found on missions shows up here too. Tap a hero to kit them out." % profile.data["gold"], 22, Color(1, 0.85, 0.35))
	for kind in Data.HERO_ORDER:
		var hero: Dictionary = Data.HEROES[kind]
		var st: Dictionary = profile.hero_stats(kind)
		var gear: Dictionary = profile.data["gear"][kind]
		var worn := []
		for slot in ["weapon", "armour", "charm"]:
			if gear[slot] != "":
				worn.append(profile.item(gear[slot]).get("name", "?"))
		var b := _button(box, "%s the %s, level %d\n%s" % [hero["name"], hero["role"], profile.hero_level(kind), ", ".join(worn)], func(): open_hero(kind))
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", hero["color"])
		b.tooltip_text = _stats_text(st)


func open_hero(kind: String) -> void:
	var hero: Dictionary = Data.HEROES[kind]
	var box := _open_panel("%s the %s" % [hero["name"], hero["role"]])
	var lvl: int = profile.hero_level(kind)
	var lvl_text := "Level %d" % lvl
	if lvl < Data.MAX_LEVEL:
		lvl_text += "   %d / %d XP to the next level" % [profile.data["heroes"][kind]["xp"], Profile.xp_needed(lvl)]
	_label(box, lvl_text, 21, Color(0.6, 0.9, 1.0))
	_label(box, _stats_text(profile.hero_stats(kind)), 21, Color(1, 1, 1, 0.85))
	_label(box, "You have %d gold." % profile.data["gold"], 20, Color(1, 0.85, 0.35))
	var abilities := []
	for id in hero["abilities"]:
		abilities.append("%s: %s" % [Data.ABILITIES[id]["name"], Data.ABILITIES[id]["text"]])
	_label(box, "\n".join(abilities), 18, Color(1, 1, 1, 0.6))
	for slot in ["weapon", "armour", "charm"]:
		_label(box, {"weapon": "Weapon", "armour": "Armour", "charm": "Charm (from task chests)"}[slot], 24, Color(0.75, 0.85, 1.0))
		var any := false
		for id in Data.ITEMS:
			var item: Dictionary = Data.ITEMS[id]
			if item["slot"] != slot or (item["hero"] != "" and item["hero"] != kind):
				continue
			if item.get("task", false) and not profile.owns(id):
				continue
			any = true
			box.add_child(_item_row(kind, id))
		for it in profile.data["loot"]:
			if it["slot"] == slot and (it["hero"] == "" or it["hero"] == kind):
				any = true
				box.add_child(_item_row(kind, it["uid"]))
		if not any:
			_label(box, "None found yet. Finish tasks to open chests.", 19, Color(1, 1, 1, 0.5))
	_button(box, "Back to the Armory", open_armory)


func _item_row(kind: String, id: String) -> Control:
	var item: Dictionary = profile.item(id)
	var found := not Data.ITEMS.has(id)
	var row := PanelContainer.new()
	var hb := HBoxContainer.new()
	row.add_child(hb)
	var l := Label.new()
	var effect: String = item.get("text", _mods_text(item["mods"]))
	l.text = "%s\n%s" % [item["name"], effect]
	if found:
		l.text = "%s  (%s)\n%s" % [item["name"], Data.RARITIES[item["rarity"]]["name"].to_lower(), effect]
		l.add_theme_color_override("font_color", Data.RARITIES[item["rarity"]]["color"])
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 20)
	hb.add_child(l)
	var slot: String = item["slot"]
	var on: bool = profile.data["gear"][kind][slot] == id
	if on:
		if slot == "charm":
			_small_button(hb, "Take off", func():
				profile.equip_item(kind, "charm", "")
				open_hero(kind))
		else:
			_small_button(hb, "Equipped", func(): pass).disabled = true
	elif profile.owns(id):
		var who: String = profile.wearer(id) if slot == "charm" or found else ""
		var label := "Equip" if who == "" else "Take from %s" % Data.HEROES[who]["name"]
		_small_button(hb, label, func():
			profile.equip_item(kind, slot, id)
			open_hero(kind))
	else:
		var b := _small_button(hb, "Buy: %d gold" % item["cost"], func():
			if profile.buy_item(id):
				profile.equip_item(kind, slot, id)
				game.toast("%s bought!" % item["name"])
			open_hero(kind))
		b.disabled = profile.data["gold"] < item["cost"]
	if found:
		var sell := _small_button(hb, "Sell: %d" % item["value"], func(): pass)
		sell.pressed.connect(func():
			# Two taps, so a stray tap doesn't sell something good.
			if sell.text == "Sure?":
				game.toast("+%d gold" % profile.sell_loot(id))
				open_hero(kind)
			else:
				sell.text = "Sure?")
	return row


func _stats_text(st: Dictionary) -> String:
	var parts := ["Health %d" % st["hp"], "Move %d" % st["move"], "Armour %d" % st["armour"]]
	for k in ["damage", "range", "spell"]:
		if st[k] != 0:
			parts.append("%s %+d" % [{"damage": "Damage", "range": "Range", "spell": "Spells"}[k], st[k]])
	if st["focus"] > 0:
		parts.append("+%d Focus a turn" % st["focus"])
	if st["focus_start"] > 0:
		parts.append("+%d starting Focus" % st["focus_start"])
	if st["gold"] > 0:
		parts.append("+%d%% gold" % st["gold"])
	return "   ".join(parts)


func _mods_text(mods: Dictionary) -> String:
	if mods.is_empty():
		return "Standard issue"
	var names := {"damage": "damage", "hp": "health", "armour": "armour", "move": "move", "range": "range",
		"spell": "spell power", "focus": "Focus each turn", "focus_start": "starting Focus", "gold": "% gold"}
	var parts := []
	for k in mods:
		if k == "element":
			parts.append(Data.ELEMENTS[mods[k]]["text"])
		else:
			parts.append("%+d %s" % [mods[k], names.get(k, k)])
	return ", ".join(parts)


func open_vault() -> void:
	var box := _open_panel("Vault")
	_label(box, "Charms only come from task chests and are never lost. Put them on heroes at the Armory.", 20, Color(1, 1, 1, 0.7))
	for id in Data.CHARM_ORDER:
		var owned: bool = profile.data["trinkets"].has(id)
		var item: Dictionary = Data.ITEMS[id]
		var who: String = profile.wearer(id)
		var l := _label(box, ("%s: %s%s" % [item["name"], item["text"], ("   (worn by %s)" % Data.HEROES[who]["name"]) if who != "" else ""]) if owned else "???  Find it in a task chest", 20, Color.WHITE if owned else Color(1, 1, 1, 0.4))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var st: Dictionary = profile.data["stats"]
	_label(box, "Missions %d   Bone King beaten %d   Tasks done %d" % [st["runs"], st["wins"], st["tasks_done"]], 20, Color(1, 1, 1, 0.6))
	var pen: String = profile.data["penalty"]
	_button(box, "If your squad falls: %s" % (Data.PENALTIES[pen]["name"] if pen != "" else "not picked"), open_penalty)
	_button(box, "Back up my save", func():
		_show_text("Copy this code somewhere safe", profile.export_code()))
	_button(box, "Restore a backup", func():
		_ask_text("Paste your backup code", func(text: String):
			if text.strip_edges() == "":
				open_vault()
			elif profile.import_code(text):
				game.toast("Save restored")
				open_vault()
			else:
				game.toast("That code didn't work")
				open_vault()))


## What happens when your whole squad falls on a mission. Can be made gentler later, never harsher.
func open_penalty() -> void:
	var box := _open_panel("If your squad falls")
	var first: bool = profile.data["penalty"] == ""
	_label(box, "Pick how harsh losing a mission is. Retreating is always safe. You can make this gentler later, but never harsher." if first else "You can make this gentler, but never harsher.", 20, Color(1, 1, 1, 0.75))
	for id in Data.PENALTY_ORDER:
		var pen: Dictionary = Data.PENALTIES[id]
		var current: bool = profile.data["penalty"] == id
		var b := _button(box, "%s%s: %s" % [pen["name"], "  (now)" if current else "", pen["text"]], func():
			profile.set_penalty(id)
			game.toast("%s it is" % pen["name"])
			close_panel())
		b.add_theme_font_size_override("font_size", 20)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = current or not profile.can_pick_penalty(id)


func open_gate() -> void:
	var now := Time.get_unix_time_from_system()
	if game.mission_active() or profile.can_start_run(now):
		close_panel()
		game.begin_run_from_village()
		return
	var box := _open_panel("Too tired to set out")
	var e: float = profile.energy(now)
	_label(box, "A mission costs %d energy and you have %d." % [int(Profile.ENERGY_PER_RUN), floori(e)], 24)
	var wait: float = profile.seconds_to_next_energy(now)
	if wait >= 0.0:
		_label(box, "+1 energy in %d:%02d." % [int(wait) / 60, int(wait) % 60], 22, Color(0.6, 0.9, 1.0))
	_label(box, "Or finish a task: Easy +1, Medium +2, Hard +4, Epic +8.", 22, Color(1, 1, 1, 0.75))
	_button(box, "Open the Quest Board", open_quest_board)


# ---------------------------------------------------------------- helpers

func _open_panel(title: String) -> VBoxContainer:
	close_panel()
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var side := maxf((size.x - 900.0) / 2.0, 30.0)
	frame.offset_left = side
	frame.offset_right = -side
	frame.offset_top = 24
	frame.offset_bottom = -24
	panel.add_child(frame)
	var outer := VBoxContainer.new()
	frame.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var t := _label(head, title, 34)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_small_button(head, "Close", close_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	return box


func close_panel() -> void:
	if panel:
		panel.queue_free()
		panel = null
	_refresh()


## Asks for a line of text. In the browser this uses the phone's own text box,
## which is the most reliable way to get the keyboard up on an iPhone.
func _ask_text(question: String, done: Callable) -> void:
	if OS.has_feature("web"):
		var result = JavaScriptBridge.eval("window.prompt(%s, '')" % JSON.stringify(question), true)
		done.call(result if result is String else "")
		return
	var box := _open_panel(question)
	var edit := LineEdit.new()
	edit.add_theme_font_size_override("font_size", 26)
	edit.custom_minimum_size = Vector2(0, 60)
	box.add_child(edit)
	_button(box, "OK", func(): done.call(edit.text))
	edit.text_submitted.connect(func(text: String): done.call(text))
	edit.grab_focus()


func _show_text(title: String, text: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.prompt(%s, %s)" % [JSON.stringify(title), JSON.stringify(text)], true)
		return
	var box := _open_panel(title)
	var edit := TextEdit.new()
	edit.text = text
	edit.custom_minimum_size = Vector2(0, 200)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(edit)


func _label(parent: Control, text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 68)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _small_button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
