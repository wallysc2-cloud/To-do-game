## Runs one combat room: loadout menu, waves, boons between waves, boss, win or lose.
extends Node2D

const Data = preload("res://scripts/data.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const EffectScript = preload("res://scripts/effect.gd")
const HudScript = preload("res://scripts/hud.gd")

const ARENA := Rect2(30, 140, 660, 880)
const SPELL_AREA_TOP := 1040.0
const SPELL_BUTTON_R := 72.0
const JOY_RADIUS := 90.0

var state := "menu"  # menu, playing, boon, paused, over
var world: Node2D
var hud: Node2D
var ui: CanvasLayer
var overlay: Control
var pause_button: Button
var player: Node2D
var enemies: Array = []

var chosen_weapon := "sword"
var chosen_spells: Array = ["fireball", "frost_nova"]
var spell_cd: Array = [0.0, 0.0]
var spell_haste := 1.0

var wave := 0
var between_waves := true
var next_wave_in := 1.0
var run_time := 0.0
var shake := 0.0

var joy_index := -1
var joy_origin := Vector2.ZERO

var autotest_weapon := ""
var ui_theme: Theme
var autotest_log := {"casts": 0, "kills": 0}


func _ready() -> void:
	randomize()
	world = Node2D.new()
	add_child(world)
	hud = Node2D.new()
	hud.set_script(HudScript)
	hud.game = self
	hud.z_index = 50
	add_child(hud)
	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	ui_theme = _make_theme()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			autotest_weapon = arg.get_slice("=", 1)
	if autotest_weapon != "":
		chosen_weapon = autotest_weapon
		start_run()
	else:
		show_menu()


# ---------------------------------------------------------------- run flow

func start_run() -> void:
	_clear_overlay()
	for child in world.get_children():
		child.queue_free()
	enemies.clear()
	player = Node2D.new()
	player.set_script(PlayerScript)
	player.setup(self, chosen_weapon)
	player.position = ARENA.get_center() + Vector2(0, 250)
	world.add_child(player)

	spell_cd = [0.0, 0.0]
	spell_haste = 1.0
	wave = 0
	between_waves = true
	next_wave_in = 1.0
	run_time = 0.0
	joy_index = -1
	state = "playing"
	get_tree().paused = false
	_make_pause_button()


func _process(delta: float) -> void:
	queue_redraw()
	if state != "playing":
		return
	run_time += delta
	for i in spell_cd.size():
		spell_cd[i] = max(spell_cd[i] - delta, 0.0)

	if between_waves:
		next_wave_in -= delta
		if next_wave_in <= 0.0:
			_spawn_wave()
	elif enemies.is_empty():
		_on_wave_cleared()

	if shake > 0.0:
		shake = max(shake - delta * 30.0, 0.0)
		world.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		world.position = Vector2.ZERO

	if autotest_weapon != "":
		_autotest_step()


func _spawn_wave() -> void:
	wave += 1
	between_waves = false
	var spec: Dictionary = Data.WAVES[wave - 1]
	for kind in spec:
		for n in spec[kind]:
			var enemy := Node2D.new()
			enemy.set_script(EnemyScript)
			enemy.setup(self, kind)
			enemy.position = _spawn_point(kind == "boss")
			world.add_child(enemy)
			enemies.append(enemy)


func _spawn_point(is_boss: bool) -> Vector2:
	if is_boss:
		return Vector2(ARENA.get_center().x, ARENA.position.y + 140)
	var best := ARENA.get_center()
	for attempt in 25:
		var p := Vector2(randf_range(ARENA.position.x + 40, ARENA.end.x - 40), randf_range(ARENA.position.y + 40, ARENA.end.y - 40))
		best = p
		if p.distance_to(player.position) > 280.0:
			break
	return best


func _on_wave_cleared() -> void:
	between_waves = true
	if wave >= Data.WAVES.size():
		_end_run(true)
		return
	_show_boons()


func on_enemy_died(enemy: Node) -> void:
	enemies.erase(enemy)
	autotest_log["kills"] += 1
	if player and player.leech > 0.0:
		player.heal(player.leech)
	spawn_effect({"kind": "ring", "pos": enemy.position, "radius": enemy.radius * 2.0, "color": enemy.stats["color"]})
	if enemy.kind == "boss":
		shake = 14.0
	enemy.queue_free()


func on_player_hurt(_amount: float) -> void:
	shake = 8.0


func on_player_died() -> void:
	_end_run(false)


func _end_run(won: bool) -> void:
	state = "over"
	joy_index = -1
	player.move_input = Vector2.ZERO
	if autotest_weapon != "":
		print("AUTOTEST weapon=%s result=%s wave=%d time=%.1f hp=%.0f kills=%d casts=%d" % [
			autotest_weapon, "win" if won else "loss", wave, run_time, player.hp, autotest_log["kills"], autotest_log["casts"]])
		get_tree().quit()
		return
	get_tree().paused = true
	_show_end_screen(won)


# ---------------------------------------------------------------- helpers used by entities

func clamp_to_arena(pos: Vector2, r: float) -> Vector2:
	return Vector2(clamp(pos.x, ARENA.position.x + r, ARENA.end.x - r), clamp(pos.y, ARENA.position.y + r, ARENA.end.y - r))


func nearest_enemy(from: Vector2, max_range: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_range
	for enemy in enemies:
		if enemy.spawn_fade > 0.0:
			continue
		var d: float = from.distance_to(enemy.position) - enemy.radius
		if d < best_d:
			best_d = d
			best = enemy
	return best


func spawn_projectile(p: Dictionary) -> void:
	var proj := Node2D.new()
	proj.set_script(ProjectileScript)
	proj.setup(self, p)
	world.add_child(proj)


func spawn_effect(p: Dictionary) -> void:
	var fx := Node2D.new()
	fx.set_script(EffectScript)
	fx.setup(p)
	world.add_child(fx)


func explode(pos: Vector2, radius: float, damage: float, color: Color, burn_dps: float, burn_time: float) -> void:
	spawn_effect({"kind": "ring", "pos": pos, "radius": radius, "color": color})
	shake = max(shake, 6.0)
	for enemy in enemies.duplicate():
		if pos.distance_to(enemy.position) < radius + enemy.radius:
			enemy.take_damage(damage)
			if burn_time > 0.0 and is_instance_valid(enemy) and enemy.hp > 0.0:
				enemy.apply_burn(burn_dps, burn_time)


# ---------------------------------------------------------------- spells

func spell_button_center(i: int) -> Vector2:
	return Vector2(200.0 + 320.0 * i, 1150.0)


func spell_cooldown(i: int) -> float:
	return Data.SPELLS[chosen_spells[i]]["cooldown"] / spell_haste


func cast_spell(i: int) -> void:
	if state != "playing" or spell_cd[i] > 0.0:
		return
	var id: String = chosen_spells[i]
	var s: Dictionary = Data.SPELLS[id]
	spell_cd[i] = spell_cooldown(i)
	autotest_log["casts"] += 1
	match id:
		"fireball":
			var target := nearest_enemy(player.position, 2000.0)
			var dir: Vector2 = (target.position - player.position).normalized() if target else player.facing
			spawn_projectile({
				"pos": player.position + dir * 24.0, "vel": dir * s["speed"],
				"damage": s["damage"] * player.damage_mult, "radius": 14.0, "color": s["color"],
				"from_player": true, "max_dist": 700.0, "explode_radius": s["radius"],
				"burn_dps": s["burn_dps"], "burn_time": s["burn_time"],
			})
		"frost_nova":
			spawn_effect({"kind": "ring", "pos": player.position, "radius": s["radius"], "color": s["color"]})
			for enemy in enemies.duplicate():
				if player.position.distance_to(enemy.position) < s["radius"] + enemy.radius:
					enemy.take_damage(s["damage"] * player.damage_mult)
					if is_instance_valid(enemy) and enemy.hp > 0.0:
						enemy.apply_slow(s["slow"], s["slow_time"])
		"blink":
			var dir: Vector2 = player.move_input.normalized() if player.is_moving() else player.facing
			spawn_effect({"kind": "ring", "pos": player.position, "radius": 40.0, "color": s["color"]})
			player.position = clamp_to_arena(player.position + dir * s["distance"], player.radius)
			player.invuln = max(player.invuln, s["invuln"])
			spawn_effect({"kind": "ring", "pos": player.position, "radius": 40.0, "color": s["color"]})


# ---------------------------------------------------------------- touch input

func _input(event: InputEvent) -> void:
	if state != "playing":
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var local := make_input_local(event)
	var pos: Vector2 = local.position

	if event is InputEventScreenTouch:
		if event.pressed:
			for i in chosen_spells.size():
				if pos.distance_to(spell_button_center(i)) <= SPELL_BUTTON_R + 12.0:
					cast_spell(i)
					get_viewport().set_input_as_handled()
					return
			if joy_index == -1 and pos.y < SPELL_AREA_TOP and pos.y > 120.0:
				joy_index = event.index
				joy_origin = pos
				player.move_input = Vector2.ZERO
		elif event.index == joy_index:
			joy_index = -1
			player.move_input = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == joy_index:
		player.move_input = ((pos - joy_origin) / JOY_RADIUS).limit_length(1.0)


# ---------------------------------------------------------------- drawing the arena

func _draw() -> void:
	if state == "menu":
		return
	draw_rect(ARENA.grow(6.0), Color(0.22, 0.2, 0.26))
	draw_rect(ARENA, Color(0.13, 0.13, 0.17))
	var tile := 60.0
	var x := ARENA.position.x
	while x < ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), Color(1, 1, 1, 0.03), 1.0)
		x += tile
	var y := ARENA.position.y
	while y < ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(1, 1, 1, 0.03), 1.0)
		y += tile


# ---------------------------------------------------------------- menus and overlays

func _clear_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null


func _new_overlay(dim: bool) -> VBoxContainer:
	_clear_overlay()
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.theme = ui_theme
	ui.add_child(overlay)
	if dim:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.7)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 50
	box.offset_right = -50
	box.offset_top = 80
	box.offset_bottom = -60
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	overlay.add_child(box)
	return box


func _make_theme() -> Theme:
	var t := Theme.new()
	var states := {
		"normal": [Color(0.16, 0.16, 0.21), Color(0.3, 0.3, 0.38)],
		"hover": [Color(0.2, 0.2, 0.26), Color(0.4, 0.4, 0.5)],
		"pressed": [Color(0.16, 0.28, 0.5), Color(0.45, 0.7, 1.0)],
		"hover_pressed": [Color(0.18, 0.31, 0.55), Color(0.5, 0.75, 1.0)],
		"focus": [Color(0, 0, 0, 0), Color(0, 0, 0, 0)],
	}
	for state_name in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state_name][0]
		sb.border_color = states[state_name][1]
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(12)
		t.set_stylebox(state_name, "Button", sb)
	t.set_color("font_color", "Button", Color(0.9, 0.9, 0.95))
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
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


func _button(parent: Control, text: String, on_press: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(0, 88)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func show_menu() -> void:
	state = "menu"
	get_tree().paused = false
	if pause_button:
		pause_button.queue_free()
		pause_button = null
	for child in world.get_children():
		child.queue_free()
	enemies.clear()
	player = null
	var box := _new_overlay(false)
	_label(box, "To-do Game", 56)
	_label(box, "Combat prototype", 26, Color(1, 1, 1, 0.6))
	_label(box, "Choose your weapon", 30)
	var weapon_group := ButtonGroup.new()
	for id in Data.WEAPONS:
		var w: Dictionary = Data.WEAPONS[id]
		var b := _button(box, "%s\n%s" % [w["name"], w["blurb"]], func(): chosen_weapon = id, true)
		b.add_theme_font_size_override("font_size", 22)
		b.custom_minimum_size = Vector2(0, 100)
		b.button_group = weapon_group
		b.button_pressed = id == chosen_weapon
	_label(box, "Choose 2 spells", 30)
	var spell_buttons := {}
	for id in Data.SPELLS:
		var s: Dictionary = Data.SPELLS[id]
		var b := _button(box, "%s: %s" % [s["name"], s["blurb"]], func(): _toggle_spell(id, spell_buttons), true)
		b.add_theme_font_size_override("font_size", 22)
		b.button_pressed = id in chosen_spells
		spell_buttons[id] = b
	var start := _button(box, "Start run", start_run)
	start.add_theme_font_size_override("font_size", 34)


func _toggle_spell(id: String, buttons: Dictionary) -> void:
	# Always keep exactly two spells: picking a new one drops the oldest pick.
	if id in chosen_spells:
		buttons[id].set_pressed_no_signal(true)
		return
	chosen_spells.pop_front()
	chosen_spells.append(id)
	for sid in buttons:
		buttons[sid].set_pressed_no_signal(sid in chosen_spells)


func _make_pause_button() -> void:
	if pause_button:
		pause_button.queue_free()
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.theme = ui_theme
	pause_button.add_theme_font_size_override("font_size", 30)
	pause_button.position = Vector2(600, 30)
	pause_button.size = Vector2(90, 70)
	pause_button.pressed.connect(_pause)
	ui.add_child(pause_button)


func _pause() -> void:
	if state != "playing":
		return
	state = "paused"
	joy_index = -1
	player.move_input = Vector2.ZERO
	get_tree().paused = true
	var box := _new_overlay(true)
	_label(box, "Paused", 48)
	_button(box, "Resume", _resume)
	_button(box, "Quit run", show_menu)


func _resume() -> void:
	_clear_overlay()
	state = "playing"
	get_tree().paused = false


func _show_boons() -> void:
	var options := Data.BOONS.filter(func(boon): return not (boon["id"] == "pierce" and chosen_weapon == "sword"))
	options.shuffle()
	options = options.slice(0, 3)
	if autotest_weapon != "":
		_apply_boon(options[0]["id"])
		return
	state = "boon"
	joy_index = -1
	player.move_input = Vector2.ZERO
	get_tree().paused = true
	var box := _new_overlay(true)
	_label(box, "Wave cleared!", 44)
	_label(box, "Pick a boost for this run", 26, Color(1, 1, 1, 0.7))
	for boon in options:
		_button(box, boon["text"], func(): _apply_boon(boon["id"]))


func _apply_boon(id: String) -> void:
	match id:
		"damage":
			player.damage_mult *= 1.2
		"vigor":
			player.max_hp += 25.0
			player.heal(25.0)
		"haste":
			spell_haste *= 1.25
		"swift":
			player.speed_mult *= 1.12
		"fury":
			player.attack_speed_mult *= 1.15
		"pierce":
			player.pierce += 1
		"chill":
			player.chill = true
		"leech":
			player.leech += 3.0
	_clear_overlay()
	state = "playing"
	get_tree().paused = false
	next_wave_in = 1.0


func _show_end_screen(won: bool) -> void:
	var box := _new_overlay(true)
	_label(box, "Victory!" if won else "You fell", 56)
	var reached := "Beat the boss" if won else ("Reached the boss" if wave == Data.WAVES.size() else "Reached wave %d" % wave)
	_label(box, "%s in %d:%02d" % [reached, int(run_time) / 60, int(run_time) % 60], 26, Color(1, 1, 1, 0.75))
	_button(box, "Try again", start_run)
	_button(box, "Change loadout", show_menu)


# ---------------------------------------------------------------- headless smoke test

func _autotest_step() -> void:
	# Simple bot: casts spells when ready, kites with the bow, stands and fights with swords.
	for i in chosen_spells.size():
		if spell_cd[i] <= 0.0 and not enemies.is_empty():
			cast_spell(i)
	var near := nearest_enemy(player.position, 9999.0)
	player.move_input = Vector2.ZERO
	if near and chosen_weapon == "bow" and player.position.distance_to(near.position) < 160.0:
		player.move_input = (player.position - near.position).normalized()
	if run_time > 300.0:
		_end_run(false)
