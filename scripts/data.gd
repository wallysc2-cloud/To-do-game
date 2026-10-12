## Tunable numbers. Change values here to adjust how the game feels.
extends RefCounted

const TILE := 32

# ---------------------------------------------------------------- hero movement
const RUN_SPEED := 250.0
const GROUND_ACCEL := 2600.0
const AIR_ACCEL := 1700.0
const GRAVITY := 2100.0
const FALL_GRAVITY_MULT := 1.25     # fall a bit faster than you rise, feels snappier
const SHORT_HOP_GRAVITY_MULT := 2.4  # extra gravity when you let go of jump early
const MAX_FALL := 720.0
const JUMP_SPEED := 690.0            # about 3.5 tiles high
const COYOTE_TIME := 0.1             # you can still jump this long after running off a ledge
const JUMP_BUFFER := 0.12            # a jump pressed this long before landing still counts
const WALL_SLIDE_SPEED := 130.0
const WALL_JUMP_X := 300.0
const WALL_JUMP_Y := 620.0
const WALL_JUMP_LOCK := 0.14         # brief time your steering is reduced after a wall jump
const DASH_SPEED := 560.0
const DASH_TIME := 0.15
const DASH_COUNT := 1                # dashes before you need to touch the ground

# ---------------------------------------------------------------- hero combat
const MAX_HEARTS := 4
const HURT_INVULN := 1.0
const STOMP_BOUNCE := 520.0
const SWORD_REACH := 40.0
const SWORD_COOLDOWN := 0.28
const FIREBALL_COOLDOWN := 5.0
const FIREBALL_SPEED := 460.0
const FIREBALL_RADIUS := 52.0        # explosion size; it also blasts away blocks

# ---------------------------------------------------------------- enemies
const ENEMIES := {
	"slime": {"hp": 2, "speed": 60.0, "size": Vector2(24, 18), "color": Color(0.45, 0.85, 0.45)},
	"bat": {"hp": 1, "speed": 115.0, "size": Vector2(22, 14), "color": Color(0.6, 0.45, 0.8), "wake_range": 210.0},
	"brute": {"hp": 4, "speed": 45.0, "size": Vector2(28, 30), "color": Color(0.85, 0.4, 0.35)},
	# Frogs hop toward you when you're in range.
	"frog": {"hp": 2, "speed": 170.0, "size": Vector2(22, 18), "color": Color(0.3, 0.75, 0.7), "hop": 540.0, "range": 300.0},
	# Spitters sit still and lob globs at you.
	"spitter": {"hp": 2, "speed": 0.0, "size": Vector2(24, 22), "color": Color(0.85, 0.75, 0.3), "range": 330.0, "cooldown": 2.2},
}

## The Cave King, waiting at the bottom of the last cave. Below half health it gets faster and meaner.
const BOSS := {
	"hp": 30, "size": Vector2(60, 52), "color": Color(0.5, 0.42, 0.6),
	"speed": 90.0, "charge_speed": 430.0, "leap_speed": 820.0, "wave_speed": 330.0,
}

const CRUMBLE_TIME := 0.45           # how long a crumbling block holds you before it falls

# ---------------------------------------------------------------- run structure
const CAVES := 3                     # random caves per run, each one deeper and meaner
const DEPTHS := CAVES + 1            # ...then the boss's lair
const ROOMS_X := 4
const ROOMS_Y := 4

## Small boosts offered between levels. They last for this run only.
## "unique" ones are only offered until you take them.
const BOONS := [
	{"id": "double_jump", "text": "Double jump"},
	{"id": "extra_dash", "text": "One extra dash in the air"},
	{"id": "heart", "text": "+1 max heart, and heal 1"},
	{"id": "long_sword", "text": "Longer sword reach"},
	{"id": "fire_haste", "text": "Fireball recharges 40% faster"},
	{"id": "stomp_heal", "text": "Stomping an enemy has a chance to heal", "unique": true},
	{"id": "dash_strike", "text": "Dashing through enemies hurts them", "unique": true},
	{"id": "triple_fire", "text": "Fire throws three fireballs in a spread", "unique": true},
	{"id": "big_boom", "text": "Bigger explosions", "unique": true},
	{"id": "sharp_sword", "text": "Sword hits twice as hard", "unique": true},
	{"id": "spike_boots", "text": "Spike-proof boots", "unique": true},
	{"id": "gold_magnet", "text": "Gold flies to you", "unique": true},
]
