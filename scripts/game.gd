## Runs the game: title screen, generating levels, the physics step, combat,
## boosts between levels, death and victory. Also hosts the headless self-tests.
extends Node2D

const Data = preload("res://scripts/data.gd")
const Gen = preload("res://scripts/level_gen.gd")
const LevelScript = preload("res://scripts/level.gd")
const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const FireballScript = preload("res://scripts/fireball.gd")
const FxScript = preload("res://scripts/fx.gd")
const HudScript = preload("res://scripts/hud.gd")

var state := "title"  # title, playing, boon, paused, over
var rng := RandomNumberGenerator.new()
var world: Node2D
var camera: Camera2D
var hud: Node2D
var ui: CanvasLayer
var overlay: Control
var pause_button: Button
var ui_theme: Theme

var level: Node2D
var player: Node2D
var enemies: Array = []
var fireballs: Array = []
var depth := 1
var gold := 0
var kills := 0
var run_time := 0.0
var shake := 0.0
var show_hint := true

# Keyboard state for playing on a computer.
var key_prev := {}

var autotest := ""
var bot_time := 0.0
var bot_dir := 1
var bot_last_x := 0.0
var bot_stuck := 0.0
var stats := {"levels": 0, "blasted": 0, "jumps": 0}


func _ready() -> void:
	rng.randomize()
	world = Node2D.new()
	add_child(world)
	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	add_child(camera)
	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	hud = Node2D.new()
	hud.set_script(HudScript)
	hud.game = self
	ui.add_child(hud)
	ui_theme = _make_theme()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			autotest = arg.get_slice("=", 1)
	match autotest:
		"levels":
			_test_levels()
		"play":
			start_run()
		_:
			show_title()


# ---------------------------------------------------------------- run flow

func start_run() -> void:
	depth = 1
	gold = 0
	kills = 0
	run_time = 0.0
	player = null
	_build_level(true)
	_make_pause_button()


func _build_level(new_hero: bool) -> void:
	_clear_overlay()
	for child in world.get_children():
		child.queue_free()
	enemies.clear()
	fireballs.clear()

	var info := Gen.generate(rng, depth)
	level = Node2D.new()
	level.set_script(LevelScript)
	level.setup(info, depth)
	world.add_child(level)

	var old_player = player
	player = Node2D.new()
	player.set_script(PlayerScript)
	player.game = self
	player.level = level
	if not new_hero and old_player:
		# Carry this run's boosts and health into the next level.
		for prop in ["hearts", "max_hearts", "air_jumps", "max_dashes", "sword_reach", "fire_cooldown", "stomp_heal", "dash_strike"]:
			player.set(prop, old_player.get(prop))
	var spawn: Vector2i = info["spawn"]
	player.position = Vector2(spawn.x * Data.TILE + (Data.TILE - player.SIZE.x) / 2.0, (spawn.y + 1) * Data.TILE - player.SIZE.y)
	world.add_child(player)

	for e in info["enemies"]:
		var enemy := Node2D.new()
		enemy.set_script(EnemyScript)
		enemy.setup(self, level, e["kind"], e["cell"])
		world.add_child(enemy)
		enemies.append(enemy)

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(level.size_px().x)
	camera.limit_bottom = int(level.size_px().y)
	camera.position = player.center()
	camera.reset_smoothing()
	hud.release_all()
	state = "playing"
	get_tree().paused = false


func _physics_process(delta: float) -> void:
	if state != "playing":
		return
	run_time += delta
	if run_time > 8.0:
		show_hint = false
	var inp := _gather_input(delta)
	player.step(delta, inp)
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.step(delta)
	_step_fireballs(delta)
	_resolve_contacts()
	_collect_gold()
	_update_camera(delta)
	if state == "playing" and player.rect().intersects(level.exit_rect()):
		_level_done()


func _gather_input(delta: float) -> Dictionary:
	var stick: Vector2 = hud.stick_vector()
	var touch: Dictionary = hud.take_pressed()
	var x := 0.0
	var y := 0.0
	if absf(stick.x) > 0.3:
		x = signf(stick.x)
	if absf(stick.y) > 0.55:
		y = signf(stick.y)
	var keys := {
		"left": Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A),
		"right": Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D),
		"up": Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W),
		"down": Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S),
		"jump": Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_Z),
		"dash": Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_SHIFT),
		"attack": Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_J),
		"spell": Input.is_physical_key_pressed(KEY_V) or Input.is_physical_key_pressed(KEY_K),
	}
	if keys["left"]: x = -1.0
	if keys["right"]: x = 1.0
	if keys["up"]: y = -1.0
	if keys["down"]: y = 1.0
	var inp := {
		"x": x, "y": y,
		"jump_pressed": touch["jump"] or (keys["jump"] and not key_prev.get("jump", false)),
		"jump_held": hud.held["jump"] or keys["jump"],
		"dash_pressed": touch["dash"] or (keys["dash"] and not key_prev.get("dash", false)),
		"attack_pressed": touch["attack"] or (keys["attack"] and not key_prev.get("attack", false)),
		"spell_pressed": touch["spell"] or (keys["spell"] and not key_prev.get("spell", false)),
	}
	key_prev = keys
	if autotest == "play":
		inp = _bot_input(delta)
	return inp


func _resolve_contacts() -> void:
	# Spikes: hurt and bounce you out.
	var feet := Rect2(player.position + Vector2(3, player.SIZE.y - 8), Vector2(player.SIZE.x - 6, 8))
	if player.vel.y >= 0.0 and level.box_touches(feet.position, feet.size, Gen.SPIKES):
		player.hurt(player.center() + Vector2(0, 30))
		player.vel.y = -420.0
	# Enemies: stomp them from above, otherwise they hurt you.
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy) or enemy.hp <= 0:
			continue
		if not player.rect().intersects(enemy.rect()):
			continue
		var feet_y: float = player.position.y + player.SIZE.y
		if player.vel.y > 50.0 and feet_y - enemy.position.y < 12.0:
			enemy.hit(2)
			player.bounce()
			shake = max(shake, 4.0)
			_burst(enemy.center(), enemy.stats["color"], 8)
			if player.stomp_heal and rng.randf() < 0.25 and player.hearts < player.max_hearts:
				player.hearts += 1
				_float_text(player.center() + Vector2(0, -20), "+1 heart", Color(1, 0.4, 0.45))
		elif player.is_dashing() and player.dash_strike:
			enemy.hit(2)
			_burst(enemy.center(), enemy.stats["color"], 6)
		else:
			player.hurt(enemy.center())


func _collect_gold() -> void:
	var c: Vector2 = player.center()
	for g in level.gold.duplicate():
		if c.distance_to(g["pos"]) < 22.0:
			level.gold.erase(g)
			gold += g["value"]
			_float_text(g["pos"], "+%d" % g["value"], Color(1, 0.85, 0.35))
			_burst(g["pos"], Color(1, 0.9, 0.4), 5)


func _update_camera(delta: float) -> void:
	var target: Vector2 = player.center() + Vector2(player.facing * 50.0, -20.0)
	camera.position = camera.position.lerp(target, min(delta * 6.0, 1.0))
	if shake > 0.0:
		camera.offset = Vector2(rng.randf_range(-shake, shake), rng.randf_range(-shake, shake))
		shake = max(shake - delta * 25.0, 0.0)
	else:
		camera.offset = Vector2.ZERO


func _level_done() -> void:
	stats["levels"] += 1
	if depth >= Data.DEPTHS:
		_end_run(true)
		return
	depth += 1
	_show_boons()


func _end_run(won: bool) -> void:
	state = "over"
	hud.release_all()
	if autotest == "play":
		_finish_play_test("won" if won else "died")
		return
	get_tree().paused = true
	var box := _new_overlay(true)
	_label(box, "You escaped!" if won else "You fell", 56)
	var where := "all %d depths" % Data.DEPTHS if won else "depth %d" % depth
	_label(box, "Made it through %s with %d gold in %d:%02d" % [where, gold, int(run_time) / 60, int(run_time) % 60], 24, Color(1, 1, 1, 0.75))
	_button(box, "Try again", start_run)
	_button(box, "Title screen", show_title)


# ---------------------------------------------------------------- events from the hero and enemies

func on_dash(p: Node2D) -> void:
	shake = max(shake, 2.0)
	_burst(p.center(), Color(0.6, 0.85, 1.0), 6)


func on_sword(p: Node2D, r: Rect2) -> void:
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and enemy.hp > 0 and r.intersects(enemy.rect()):
			enemy.hit(1)
			enemy.vel.x = p.facing * 160.0
			_burst(enemy.center(), Color.WHITE, 4)
			shake = max(shake, 2.5)


func on_fireball(p: Node2D) -> void:
	var fb := Node2D.new()
	fb.set_script(FireballScript)
	fb.position = p.center() + Vector2(p.facing * 14.0, 0)
	fb.vel = Vector2(p.facing * Data.FIREBALL_SPEED, 0)
	world.add_child(fb)
	fireballs.append(fb)


func _step_fireballs(delta: float) -> void:
	for fb in fireballs.duplicate():
		fb.age += delta
		fb.position += fb.vel * delta
		var boom: bool = fb.age > 2.0 or level.solid_at(fb.position)
		if not boom:
			for enemy in enemies:
				if enemy.hp > 0 and enemy.rect().grow(6.0).has_point(fb.position):
					boom = true
					break
		if boom:
			_explode(fb.position)
			fireballs.erase(fb)
			fb.queue_free()


func _explode(at: Vector2) -> void:
	var broken: int = level.blast(at, Data.FIREBALL_RADIUS)
	stats["blasted"] += broken
	shake = max(shake, 8.0)
	_spawn_fx({"kind": "ring", "pos": at, "size": Data.FIREBALL_RADIUS + 10.0, "color": Color(1.0, 0.55, 0.2), "life": 0.35})
	_burst(at, Color(1.0, 0.6, 0.2), 10)
	for i in broken * 2:
		_spawn_fx({"pos": at + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)),
			"vel": Vector2(rng.randf_range(-160, 160), rng.randf_range(-320, -60)), "gravity": 900.0,
			"life": 0.6, "color": Color(0.45, 0.35, 0.28), "size": 6.0})
	for enemy in enemies.duplicate():
		if is_instance_valid(enemy) and enemy.hp > 0 and enemy.center().distance_to(at) < Data.FIREBALL_RADIUS + 16.0:
			enemy.hit(3)


func on_enemy_killed(enemy: Node2D) -> void:
	kills += 1
	enemies.erase(enemy)
	_burst(enemy.center(), enemy.stats["color"], 10)
	enemy.queue_free()


func on_player_hurt() -> void:
	shake = max(shake, 7.0)
	_burst(player.center(), Color(1, 0.35, 0.35), 8)
	if autotest == "play":
		player.hearts = player.max_hearts  # the test bot is immortal
		return
	if player.hearts <= 0:
		_end_run(false)


func spawn_dust(at: Vector2, count: int) -> void:
	for i in count:
		_spawn_fx({"pos": at, "vel": Vector2(rng.randf_range(-90, 90), rng.randf_range(-60, -10)),
			"life": 0.3, "color": Color(0.85, 0.8, 0.75, 0.7), "size": 4.0})


func _burst(at: Vector2, col: Color, count: int) -> void:
	for i in count:
		var a := rng.randf() * TAU
		_spawn_fx({"pos": at, "vel": Vector2.RIGHT.rotated(a) * rng.randf_range(60, 200), "gravity": 400.0,
			"life": 0.45, "color": col, "size": 4.0})


func _float_text(at: Vector2, text: String, col: Color) -> void:
	_spawn_fx({"kind": "text", "pos": at, "vel": Vector2(0, -40), "life": 0.8, "color": col, "text": text})


func _spawn_fx(p: Dictionary) -> void:
	var fx := Node2D.new()
	fx.set_script(FxScript)
	fx.setup(p)
	world.add_child(fx)


# ---------------------------------------------------------------- menus and overlays

func show_title() -> void:
	state = "title"
	get_tree().paused = false
	if pause_button:
		pause_button.queue_free()
		pause_button = null
	for child in world.get_children():
		child.queue_free()
	enemies.clear()
	fireballs.clear()
	player = null
	var box := _new_overlay(false)
	_label(box, "To-do Game", 64)
	_label(box, "Platformer prototype", 26, Color(1, 1, 1, 0.6))
	_label(box, "Reach the glowing door at the bottom of each cave. Stomp or slash monsters, grab gold, blast walls with Fire.", 22, Color(1, 1, 1, 0.75))
	_label(box, "Phone: drag on the left to move. Buttons on the right.\nKeyboard: arrows to move, Space jump, X dash, C sword, V fire.", 20, Color(1, 1, 1, 0.55))
	var play := _button(box, "Play", start_run)
	play.add_theme_font_size_override("font_size", 36)


func _show_boons() -> void:
	var options := Data.BOONS.duplicate()
	options.shuffle()
	options = options.slice(0, 3)
	if autotest == "play":
		_apply_boon(options[0]["id"])
		return
	state = "boon"
	hud.release_all()
	get_tree().paused = true
	var box := _new_overlay(true)
	_label(box, "Depth %d cleared!" % (depth - 1), 44)
	_label(box, "Pick a boost for the rest of this run", 24, Color(1, 1, 1, 0.7))
	for boon in options:
		_button(box, boon["text"], func(): _apply_boon(boon["id"]))


func _apply_boon(id: String) -> void:
	match id:
		"double_jump":
			player.air_jumps += 1
		"extra_dash":
			player.max_dashes += 1
		"heart":
			player.max_hearts += 1
			player.hearts = min(player.hearts + 1, player.max_hearts)
		"long_sword":
			player.sword_reach *= 1.5
		"fire_haste":
			player.fire_cooldown *= 0.6
		"stomp_heal":
			player.stomp_heal = true
		"dash_strike":
			player.dash_strike = true
	_build_level(false)


func _make_pause_button() -> void:
	if pause_button:
		pause_button.queue_free()
	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.theme = ui_theme
	pause_button.add_theme_font_size_override("font_size", 28)
	pause_button.pressed.connect(_pause)
	ui.add_child(pause_button)
	# Pinned to the top-right corner, whatever the phone's width.
	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.offset_left = -100
	pause_button.offset_right = -20
	pause_button.offset_top = 20
	pause_button.offset_bottom = 84


func _pause() -> void:
	if state != "playing":
		return
	state = "paused"
	hud.release_all()
	get_tree().paused = true
	var box := _new_overlay(true)
	_label(box, "Paused", 48)
	_button(box, "Resume", _resume)
	_button(box, "Quit run", show_title)


func _resume() -> void:
	_clear_overlay()
	state = "playing"
	get_tree().paused = false


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
		bg.color = Color(0, 0, 0, 0.72)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
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

## Generates many levels and checks the exit can always be reached from the spawn.
func _test_levels() -> void:
	var failures := 0
	var total := 300
	for i in total:
		var r := RandomNumberGenerator.new()
		r.seed = i
		var info := Gen.generate(r, 1 + i % Data.DEPTHS)
		if not _reachable(info):
			failures += 1
			print("LEVELTEST unreachable seed=%d" % i)
	print("LEVELTEST levels=%d failures=%d" % [total, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _reachable(info: Dictionary) -> bool:
	var grid: Array = info["grid"]
	var start: Vector2i = info["spawn"]
	var goal: Vector2i = info["exit"]
	if grid[start.y][start.x] != Gen.AIR or grid[goal.y][goal.x] != Gen.AIR:
		return false
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == goal:
			return true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= info["w"] or n.y >= info["h"] or seen.has(n):
				continue
			var t: int = grid[n.y][n.x]
			if t == Gen.AIR or t == Gen.SPIKES:
				seen[n] = true
				queue.append(n)
	return false


## A simple immortal bot runs, jumps, dashes and fights for a while to catch crashes.
func _bot_input(delta: float) -> Dictionary:
	bot_time += delta
	if absf(player.position.x - bot_last_x) < 0.5:
		bot_stuck += delta
	else:
		bot_stuck = 0.0
	bot_last_x = player.position.x
	if bot_stuck > 1.2:
		bot_dir = -bot_dir
		bot_stuck = 0.0
	var phase := fmod(bot_time, 0.9)
	var jump_now := phase < delta
	if jump_now:
		stats["jumps"] += 1
	if bot_time > 60.0:
		_finish_play_test("timeout")
	return {
		"x": float(bot_dir), "y": -1.0 if fmod(bot_time, 4.0) < 0.5 else 0.0,
		"jump_pressed": jump_now, "jump_held": phase < 0.35,
		"dash_pressed": fmod(bot_time, 2.1) < delta,
		"attack_pressed": fmod(bot_time, 0.5) < delta,
		"spell_pressed": fmod(bot_time, 3.0) < delta,
	}


func _finish_play_test(result: String) -> void:
	print("PLAYTEST result=%s depth=%d levels=%d time=%.1f kills=%d gold=%d blasted=%d jumps=%d" % [
		result, depth, stats["levels"], run_time, kills, gold, stats["blasted"], stats["jumps"]])
	get_tree().quit()
	set_physics_process(false)
	state = "over"
