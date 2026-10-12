## The battle screen. Draws a battle and turns taps into moves and abilities:
## tap a hero, tap a blue tile to move there, tap an ability, then tap a red tile to use it.
## Tapping a monster in reach uses the hero's free basic attack straight away.
extends Control

const Data = preload("res://scripts/data.gd")
const Combat = preload("res://scripts/combat.gd")

signal finished(result: String)
signal menu_pressed

const PANEL_W := 330.0

var combat: RefCounted
var title := ""
var cell := 96.0
var origin := Vector2(20, 80)
var selected := -1        # id of the hero you're giving orders to
var aiming := ""          # ability waiting for a target
var sprint := false
var phase := "player"     # player, enemy, over
var anim: Array = []      # battle events still to be shown
var wait := 0.0
var enemy_queue: Array = []
var disp := {}            # unit id -> {pos, goal, hp, alpha, flash, lunge}
var effects: Array = []   # short-lived drawings: shots, slams, floating numbers
var banner := ""
var banner_t := 0.0
var speed := 1.0          # self-tests run the animations fast
var auto := false         # self-test: the squad plays itself

var panel: VBoxContainer
var name_label: Label
var info: Label
var ability_buttons: Array = []
var sprint_button: Button
var end_button: Button
var menu_button: Button
var font: Font = ThemeDB.fallback_font


func setup(c: RefCounted, battle_title: String) -> void:
	combat = c
	title = battle_title
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for u in combat.units:
		_add_disp(u)

	menu_button = Button.new()
	menu_button.text = "Menu"
	menu_button.add_theme_font_size_override("font_size", 20)
	menu_button.position = Vector2(14, 10)
	menu_button.custom_minimum_size = Vector2(90, 52)
	menu_button.pressed.connect(func(): menu_pressed.emit())
	add_child(menu_button)

	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 58)  # room for the Focus gems, drawn in _draw
	panel.add_child(spacer)
	name_label = _panel_label(24, Color.WHITE)
	for i in 3:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 60)
		b.add_theme_font_size_override("font_size", 21)
		b.pressed.connect(_on_ability.bind(i))
		panel.add_child(b)
		ability_buttons.append(b)
	sprint_button = Button.new()
	sprint_button.toggle_mode = true
	sprint_button.custom_minimum_size = Vector2(0, 52)
	sprint_button.add_theme_font_size_override("font_size", 19)
	sprint_button.pressed.connect(_on_sprint)
	panel.add_child(sprint_button)
	info = _panel_label(19, Color(1, 1, 1, 0.75))
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	end_button = Button.new()
	end_button.text = "End turn"
	end_button.custom_minimum_size = Vector2(0, 70)
	end_button.add_theme_font_size_override("font_size", 26)
	end_button.pressed.connect(end_turn)
	panel.add_child(end_button)

	resized.connect(_layout)
	_layout()
	_show_banner("Your turn")
	_select_next()
	_refresh()


func _panel_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	panel.add_child(l)
	return l


func _add_disp(u: Dictionary) -> void:
	var p := _center(u["cell"])
	disp[u["id"]] = {"pos": p, "goal": p, "hp": u["hp"], "alpha": 1.0 if u["hp"] > 0 else 0.0, "flash": 0.0, "lunge": Vector2.ZERO}


func _layout() -> void:
	var w := size.x if size.x > 0.0 else 1280.0
	var h := size.y if size.y > 0.0 else 720.0
	cell = floorf(minf((w - PANEL_W - 40.0) / combat.w, (h - 96.0) / combat.h))
	var grid_size := Vector2(cell * combat.w, cell * combat.h)
	origin = Vector2(maxf(20.0, (w - PANEL_W - grid_size.x) / 2.0), 76.0 + maxf(0.0, (h - 86.0 - grid_size.y) / 2.0))
	panel.position = Vector2(w - PANEL_W, 14)
	panel.size = Vector2(PANEL_W - 16, h - 28)
	for id in disp:
		var u := _unit(id)
		if not u.is_empty():
			disp[id]["pos"] = _center(u["cell"])
			disp[id]["goal"] = disp[id]["pos"]
	queue_redraw()


func _center(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * cell


func _unit(id: int) -> Dictionary:
	for u in combat.units:
		if u["id"] == id:
			return u
	return {}


func _hero() -> Dictionary:
	var u := _unit(selected)
	return u if not u.is_empty() and u["hp"] > 0 else {}


func busy() -> bool:
	return wait > 0.0 or not anim.is_empty() or phase != "player"


# ---------------------------------------------------------------- taps

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i(((event.position - origin) / cell).floor())
		if combat.in_bounds(c):
			accept_event()
			tap_cell(c)


func tap_cell(c: Vector2i) -> void:
	if busy():
		return
	var u: Dictionary = combat.unit_at(c)
	var hero := _hero()
	if aiming != "" and not hero.is_empty():
		var id := aiming
		aiming = ""
		if combat.targets(hero, id).has(c):
			combat.use_ability(hero, id, c)
			_after_action()
			return
	if not u.is_empty() and u["side"] == "hero":
		selected = u["id"]
		sprint = false
		_refresh()
		return
	if not hero.is_empty() and not hero["moved"]:
		if _reach(hero).has(c) and c != hero["cell"]:
			combat.move_hero(hero, c, sprint)
			sprint = false
			_after_action()
			return
	if not u.is_empty() and u["side"] == "enemy":
		if not hero.is_empty():
			var basic: String = Data.HEROES[hero["kind"]]["abilities"][0]
			if combat.can_use(hero, basic) and combat.targets(hero, basic).has(c):
				combat.use_ability(hero, basic, c)
				_after_action()
				return
		var st: Dictionary = Data.ENEMIES[u["kind"]]
		var reach_text := "right next to it" if u["range"] <= 1 else "%d tiles away" % u["range"]
		info.text = "%s: %d / %d health, hits for %d up to %s." % [u["name"], u["hp"], u["max_hp"], u["damage"], reach_text]
		if st["ai"] == "healer":
			info.text += " Heals other monsters."
		if u["kind"] == "boss":
			info.text += " Slams everyone next to him and calls up skeletons."
		queue_redraw()
		return
	_refresh()


func _reach(hero: Dictionary) -> Dictionary:
	var steps: int = combat.hero_move(hero) + (Data.SPRINT_MOVE if sprint else 0)
	return combat.reachable(hero, steps)


func _on_ability(i: int) -> void:
	var hero := _hero()
	if hero.is_empty() or busy():
		_refresh()
		return
	var id: String = Data.HEROES[hero["kind"]]["abilities"][i]
	aiming = "" if aiming == id else id
	# Abilities that hit everything around you go off straight away.
	if aiming != "" and Data.ABILITIES[id].get("around", false):
		aiming = ""
		combat.use_ability(hero, id, hero["cell"])
		_after_action()
		return
	_refresh()


func _on_sprint() -> void:
	sprint = not sprint
	aiming = ""
	_refresh()


func end_turn() -> void:
	if busy():
		return
	aiming = ""
	sprint = false
	combat.end_player_turn()
	phase = "enemy"
	enemy_queue = combat.alive("enemy").map(func(e): return e["id"])
	_show_banner("Monsters' turn")
	_refresh()


func _after_action() -> void:
	_take_events()
	var hero := _hero()
	if hero.is_empty() or (hero["moved"] and hero["acted"]):
		_select_next()
	_refresh()


## Picks the next hero who still has something to do.
func _select_next() -> void:
	for u in combat.alive("hero"):
		if not (u["moved"] and u["acted"]):
			selected = u["id"]
			return
	if _hero().is_empty():
		var left: Array = combat.alive("hero")
		selected = left[0]["id"] if not left.is_empty() else -1


func _take_events() -> void:
	anim.append_array(combat.events)
	combat.events.clear()


# ---------------------------------------------------------------- the side panel

func _refresh() -> void:
	var hero := _hero()
	var mine := phase == "player" and not hero.is_empty()
	if hero.is_empty():
		name_label.text = ""
	else:
		var st: Dictionary = Data.HEROES[hero["kind"]]
		var todo := []
		if not hero["moved"]:
			todo.append("move")
		if not hero["acted"]:
			todo.append("act")
		name_label.text = "%s the %s   %d/%d\n%s" % [hero["name"], st["role"], hero["hp"], hero["max_hp"], ("Can still " + " and ".join(todo)) if not todo.is_empty() else "Done for this turn"]
	for i in 3:
		var b: Button = ability_buttons[i]
		if not mine:
			b.text = ""
			b.disabled = true
			b.set_pressed_no_signal(false)
			continue
		var id: String = Data.HEROES[hero["kind"]]["abilities"][i]
		var ab: Dictionary = Data.ABILITIES[id]
		b.text = ab["name"] + ("   free" if ab["cost"] == 0 else "   %d Focus" % ab["cost"])
		b.disabled = not combat.can_use(hero, id)
		b.set_pressed_no_signal(aiming == id)
	sprint_button.text = "Sprint: +%d move, 1 Focus" % Data.SPRINT_MOVE
	sprint_button.disabled = not mine or hero["moved"] or combat.focus < 1
	sprint_button.set_pressed_no_signal(sprint and not sprint_button.disabled)
	end_button.disabled = phase != "player"
	var all_done: bool = combat.alive("hero").filter(func(u): return not (u["moved"] and u["acted"])).is_empty()
	end_button.modulate = Color(1.3, 1.2, 0.6) if all_done and phase == "player" else Color.WHITE
	if phase == "enemy":
		info.text = "The monsters are moving..."
	elif hero.is_empty():
		info.text = "Tap one of your heroes."
	elif aiming != "":
		var ab: Dictionary = Data.ABILITIES[aiming]
		info.text = "%s. Tap a red tile to use it, or tap the button again to cancel." % ab["text"]
	elif not hero["moved"]:
		info.text = "Tap a blue tile to move. Tap a monster in reach to attack it, or pick an ability."
	elif not hero["acted"]:
		info.text = "Pick an ability, or tap a monster in reach to attack it."
	else:
		info.text = "Tap another hero, or End turn."
	queue_redraw()


# ---------------------------------------------------------------- playing out what happened

func _process(delta: float) -> void:
	var d := delta * speed
	for id in disp:
		var dd: Dictionary = disp[id]
		dd["pos"] = dd["pos"].move_toward(dd["goal"], cell * 7.0 * d)
		dd["flash"] = maxf(0.0, dd["flash"] - d)
		dd["lunge"] = dd["lunge"].move_toward(Vector2.ZERO, cell * 2.0 * d)
		if dd["hp"] <= 0:
			dd["alpha"] = maxf(0.0, dd["alpha"] - d * 2.5)
	for e in effects:
		e["t"] += d
	effects = effects.filter(func(e): return e["t"] < e["life"])
	banner_t = maxf(0.0, banner_t - d)
	queue_redraw()

	if wait > 0.0:
		wait -= d
		return
	if not anim.is_empty():
		_play(anim.pop_front())
		return
	if phase == "over":
		return
	if combat.result() != "":
		phase = "over"
		_show_banner("Victory!" if combat.result() == "win" else "Your squad has fallen")
		wait = 1.2
		anim.append({"type": "done"})
		return
	if phase == "enemy":
		if enemy_queue.is_empty():
			combat.start_player_turn()
			phase = "player"
			_show_banner("Your turn")
			_select_next()
			_refresh()
			return
		var e := _unit(enemy_queue.pop_front())
		if not e.is_empty() and e["hp"] > 0:
			combat.enemy_act(e)
			_take_events()
			wait = 0.15
		return
	if auto and phase == "player":
		combat.auto_hero_turn()
		_take_events()
		end_turn()


func _play(ev: Dictionary) -> void:
	match ev["type"]:
		"move":
			var dd: Dictionary = disp[ev["unit"]]
			dd["goal"] = _center(ev["to"])
			wait = dd["pos"].distance_to(dd["goal"]) / (cell * 7.0) + 0.05
		"focus":
			_float(_center(ev["cell"]), "+%d Focus" % ev["amount"], Color(0.5, 0.85, 1.0))
			wait = 0.3
		"ability", "attack":
			var u := _unit(ev["unit"])
			var from: Vector2 = disp[ev["unit"]]["pos"]
			var to := _center(ev["at"])
			var ranged: bool = Combat.dist(u["cell"], ev["at"]) > 1 or ev.get("ability", "") in Combat.SPELLS
			if ev.get("ability", "") == "cleave":
				effects.append({"kind": "ring", "a": from, "t": 0.0, "life": 0.35, "color": Color(1, 0.9, 0.6), "r": cell * 1.4})
			elif ranged:
				var col := Color(1, 0.6, 0.2) if ev.get("ability", "") == "fireball" else (Color(0.8, 0.6, 1.0) if ev.get("ability", "") in Combat.SPELLS else Color(0.95, 0.9, 0.7))
				if ev.get("ability", "") == "mend":
					col = Color(0.5, 1.0, 0.6)
				effects.append({"kind": "shot", "a": from, "b": to, "t": 0.0, "life": 0.25, "color": col})
				if ev.get("ability", "") == "fireball":
					effects.append({"kind": "ring", "a": to, "t": 0.0, "life": 0.45, "color": col, "r": cell * 1.5})
			else:
				disp[ev["unit"]]["lunge"] = (to - from).normalized() * cell * 0.3
			if ev.has("ability") and Data.ABILITIES[ev["ability"]]["cost"] > 0:
				_float(from + Vector2(0, -cell * 0.45), Data.ABILITIES[ev["ability"]]["name"], Color(1, 1, 1))
			wait = 0.25
		"hit":
			var dd: Dictionary = disp[ev["unit"]]
			dd["hp"] -= ev["amount"]
			dd["flash"] = 0.3
			_float(dd["pos"], "-%d" % ev["amount"], Color(1, 0.35, 0.3))
			wait = 0.25
		"heal":
			var dd: Dictionary = disp[ev["unit"]]
			dd["hp"] += ev["amount"]
			_float(dd["pos"], "+%d" % ev["amount"], Color(0.45, 1.0, 0.5))
			wait = 0.3
		"die":
			wait = 0.3
		"text":
			_float(_center(ev["cell"]), ev["text"], Color(1, 0.95, 0.7))
			wait = 0.25
		"summon":
			_add_disp(_unit(ev["unit"]))
			disp[ev["unit"]]["alpha"] = 1.0
			_float(_center(ev["cell"]), "Rise!", Color(0.85, 0.83, 0.75))
			wait = 0.35
		"slam":
			effects.append({"kind": "ring", "a": _center(ev["cell"]), "t": 0.0, "life": 0.4, "color": Color(1, 0.8, 0.3), "r": cell * 1.6})
			_float(_center(ev["cell"]) + Vector2(0, -cell * 0.5), "SLAM", Color(1, 0.8, 0.3))
			wait = 0.3
		"done":
			finished.emit(combat.result())
	_refresh()


func _float(at: Vector2, text: String, col: Color) -> void:
	effects.append({"kind": "text", "a": at, "t": 0.0, "life": 0.9, "color": col, "text": text})


func _show_banner(text: String) -> void:
	banner = text
	banner_t = 1.1


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.09, 0.13))
	draw_rect(Rect2(size.x - PANEL_W - 6, 0, PANEL_W + 6, size.y), Color(0.12, 0.12, 0.17))
	draw_string(font, Vector2(120, 46), "%s   Turn %d" % [title, combat.turn], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.9))
	_draw_focus()

	var t := Time.get_ticks_msec() / 1000.0
	for y in combat.h:
		for x in combat.w:
			var r := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			var tile: int = combat.grid[y][x]
			var shade := 0.2 if (x + y) % 2 == 0 else 0.23
			draw_rect(r.grow(-1), Color(shade, shade, shade + 0.06))
			if tile == Combat.WALL:
				draw_rect(r.grow(-2), Color(0.33, 0.3, 0.38))
				draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(cell - 4, cell * 0.25)), Color(0.42, 0.39, 0.48))
				draw_line(r.position + Vector2(cell * 0.3, cell * 0.45), r.position + Vector2(cell * 0.3, cell * 0.95), Color(0.26, 0.24, 0.3), 2)
				draw_line(r.position + Vector2(cell * 0.7, cell * 0.27), r.position + Vector2(cell * 0.7, cell * 0.65), Color(0.26, 0.24, 0.3), 2)
			elif tile == Combat.CRYSTAL:
				var c := r.get_center()
				var s := cell * (0.2 + 0.02 * sin(t * 3.0 + x))
				draw_circle(c, cell * 0.32, Color(0.4, 0.75, 1.0, 0.12))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.4), c + Vector2(s, 0), c + Vector2(0, s * 1.4), c + Vector2(-s, 0)]), Color(0.45, 0.8, 1.0))

	var hero := _hero()
	if phase == "player" and not hero.is_empty() and anim.is_empty():
		var pulse := 0.5 + 0.2 * sin(t * 5.0)
		if aiming != "":
			var heal: bool = Data.ABILITIES[aiming].has("heal")
			for c in combat.targets(hero, aiming):
				_tint(c, Color(0.3, 1.0, 0.4, 0.3 * pulse * 2) if heal else Color(1.0, 0.25, 0.2, 0.3 * pulse * 2))
		else:
			if not hero["moved"]:
				for c in _reach(hero):
					if c != hero["cell"]:
						_tint(c, Color(0.3, 0.6, 1.0, 0.28))
			var basic: String = Data.HEROES[hero["kind"]]["abilities"][0]
			if combat.can_use(hero, basic):
				for c in combat.targets(hero, basic):
					_outline(c, Color(1.0, 0.35, 0.3, pulse + 0.2))
		_outline(hero["cell"], Color(1, 0.9, 0.3), 4.0)

	var ids := disp.keys()
	ids.sort_custom(func(a, b): return disp[a]["pos"].y < disp[b]["pos"].y)
	for id in ids:
		if disp[id]["alpha"] > 0.0:
			_draw_unit(_unit(id), disp[id])

	for e in effects:
		var k: float = e["t"] / e["life"]
		match e["kind"]:
			"shot":
				var head: Vector2 = e["a"].lerp(e["b"], minf(1.0, k * 1.6))
				var tail: Vector2 = e["a"].lerp(e["b"], maxf(0.0, k * 1.6 - 0.35))
				draw_line(tail, head, e["color"], 5.0)
				draw_circle(head, 6.0, e["color"])
			"ring":
				draw_arc(e["a"], e["r"] * (0.3 + 0.7 * k), 0, TAU, 32, Color(e["color"], 1.0 - k), 6.0)
			"text":
				var p: Vector2 = e["a"] + Vector2(0, -30.0 - 40.0 * k)
				var col: Color = e["color"]
				draw_string_outline(font, p - Vector2(100, 0), e["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, 28, 6, Color(0, 0, 0, 1.0 - k))
				draw_string(font, p - Vector2(100, 0), e["text"], HORIZONTAL_ALIGNMENT_CENTER, 200, 28, Color(col, 1.0 - k * k))

	if banner_t > 0.0:
		var a := minf(1.0, banner_t * 3.0)
		var mid := origin + Vector2(cell * combat.w / 2.0, cell * combat.h / 2.0)
		draw_rect(Rect2(mid.x - 260, mid.y - 46, 520, 80), Color(0, 0, 0, 0.6 * a))
		draw_string(font, Vector2(mid.x - 260, mid.y + 12), banner, HORIZONTAL_ALIGNMENT_CENTER, 520, 40, Color(1, 0.95, 0.75, a))


func _draw_focus() -> void:
	var p := panel.position
	draw_string(font, p + Vector2(0, 26), "Focus %d" % combat.focus, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.55, 0.85, 1.0))
	for i in Data.FOCUS_MAX:
		var c := p + Vector2(118 + i * 23, 18)
		var lit: bool = i < combat.focus
		var s := 8.0
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 1.3), c + Vector2(s, 0), c + Vector2(0, s * 1.3), c + Vector2(-s, 0)]), Color(0.45, 0.8, 1.0) if lit else Color(0.25, 0.28, 0.35))
	draw_string(font, p + Vector2(0, 52), "Spent on abilities. +%d each turn." % (Data.FOCUS_PER_TURN + combat.focus_bonus), HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 16, 15, Color(1, 1, 1, 0.5))


func _tint(c: Vector2i, col: Color) -> void:
	draw_rect(Rect2(origin + Vector2(c) * cell, Vector2(cell, cell)).grow(-3), col)


func _outline(c: Vector2i, col: Color, width := 3.0) -> void:
	draw_rect(Rect2(origin + Vector2(c) * cell, Vector2(cell, cell)).grow(-4), col, false, width)


func _draw_unit(u: Dictionary, dd: Dictionary) -> void:
	var p: Vector2 = dd["pos"] + dd["lunge"]
	var a: float = dd["alpha"]
	var big := {"boss": 0.42, "brute": 0.37}
	var r: float = cell * big.get(u["kind"], 0.31)
	var col: Color = u["color"].lerp(Color.WHITE, dd["flash"] * 2.0)
	var done: bool = u["side"] == "hero" and u["moved"] and u["acted"] and phase == "player"
	if done:
		col = col.darkened(0.4)
	col.a = a
	var dark := Color(0, 0, 0, 0.55 * a)
	draw_circle(p + Vector2(0, r * 0.85), r * 0.8, Color(0, 0, 0, 0.25 * a))
	draw_circle(p, r + 3, dark)
	draw_circle(p, r, col)
	var eye := Color(0.08, 0.08, 0.1, a)
	match u["kind"]:
		"knight":
			draw_rect(Rect2(p + Vector2(-r * 1.1, -r * 0.2), Vector2(r * 0.6, r * 0.85)), Color(0.75, 0.78, 0.85, a))
			draw_line(p + Vector2(r * 0.7, r * 0.5), p + Vector2(r * 1.2, -r * 0.9), Color(0.9, 0.9, 0.95, a), 4)
		"ranger":
			draw_arc(p + Vector2(r * 0.8, 0), r * 0.75, -PI / 2.2, PI / 2.2, 12, Color(0.6, 0.4, 0.2, a), 4)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-r, -r * 0.4), p + Vector2(0, -r * 1.35), p + Vector2(r, -r * 0.4)]), Color(0.3, 0.55, 0.3, a))
		"mage":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.95, -r * 0.45), p + Vector2(r * 0.2, -r * 1.7), p + Vector2(r * 0.95, -r * 0.45)]), Color(0.45, 0.3, 0.75, a))
			draw_circle(p + Vector2(r * 1.05, -r * 0.2), r * 0.18, Color(1, 0.8, 0.4, a))
		"skeleton":
			eye = Color(0.15, 0.1, 0.1, a)
			draw_line(p + Vector2(-r * 0.4, r * 0.45), p + Vector2(r * 0.4, r * 0.45), eye, 2)
		"archer":
			draw_arc(p + Vector2(-r * 0.8, 0), r * 0.75, PI - PI / 2.2, PI + PI / 2.2, 12, Color(0.4, 0.3, 0.2, a), 4)
		"brute":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.8, -r * 0.6), p + Vector2(-r * 1.1, -r * 1.2), p + Vector2(-r * 0.4, -r * 0.85)]), Color(0.9, 0.88, 0.8, a))
			draw_colored_polygon(PackedVector2Array([p + Vector2(r * 0.8, -r * 0.6), p + Vector2(r * 1.1, -r * 1.2), p + Vector2(r * 0.4, -r * 0.85)]), Color(0.9, 0.88, 0.8, a))
		"shaman":
			draw_line(p + Vector2(r * 1.0, r * 0.9), p + Vector2(r * 1.0, -r * 1.1), Color(0.45, 0.32, 0.2, a), 4)
			draw_circle(p + Vector2(r * 1.0, -r * 1.2), r * 0.22, Color(0.5, 1.0, 0.6, a))
		"boss":
			var cr := PackedVector2Array([p + Vector2(-r * 0.7, -r * 0.7), p + Vector2(-r * 0.7, -r * 1.3), p + Vector2(-r * 0.35, -r * 0.95), p + Vector2(0, -r * 1.4), p + Vector2(r * 0.35, -r * 0.95), p + Vector2(r * 0.7, -r * 1.3), p + Vector2(r * 0.7, -r * 0.7)])
			draw_colored_polygon(cr, Color(1, 0.85, 0.2, a))
			eye = Color(0.9, 0.2, 0.1, a)
	draw_circle(p + Vector2(-r * 0.32, -r * 0.1), r * 0.14, eye)
	draw_circle(p + Vector2(r * 0.32, -r * 0.1), r * 0.14, eye)
	if u["rooted"] > 0:
		draw_arc(p + Vector2(0, r * 0.7), r * 0.8, 0, TAU, 20, Color(0.75, 0.55, 0.3, a), 3)

	# Health bar with the number beside it, and for heroes two dots: blue = can move, orange = can act.
	var hp: int = maxi(0, dd["hp"])
	var bw := cell * 0.56
	var bar := Rect2(p + Vector2(-cell * 0.4, r + 5), Vector2(bw, 9))
	draw_rect(bar.grow(2), Color(0, 0, 0, 0.7 * a))
	draw_rect(Rect2(bar.position, Vector2(bw * clampf(float(hp) / u["max_hp"], 0, 1), 9)), Color(0.35, 0.85, 0.4, a) if u["side"] == "hero" else Color(0.9, 0.3, 0.25, a))
	var num := bar.position + Vector2(bw + 4, 11)
	draw_string_outline(font, num, str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, a))
	draw_string(font, num, str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, a))
	if u["side"] == "hero" and phase == "player":
		if not u["moved"]:
			draw_circle(p + Vector2(-r * 0.45, -r - 10), 6, Color(0.4, 0.7, 1.0, a))
		if not u["acted"]:
			draw_circle(p + Vector2(r * 0.45, -r - 10), 6, Color(1.0, 0.6, 0.25, a))
