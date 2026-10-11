## Tunable numbers for weapons, spells, enemies and waves.
## Change values here to rebalance combat without touching the logic.
extends RefCounted

const WEAPONS := {
	"sword": {
		"name": "Sword",
		"blurb": "Wide close-range swings. Stand your ground.",
		"cooldown": 0.45, "range": 100.0, "damage": 24.0, "arc": 2.2,
	},
	"bow": {
		"name": "Bow",
		"blurb": "Long-range arrows. Kite and keep your distance.",
		"cooldown": 0.55, "range": 560.0, "damage": 15.0, "projectile_speed": 760.0,
	},
	"flame_sword": {
		"name": "Flame Sword",
		"blurb": "Weaker swings, but each one hurls a fire bolt that burns.",
		"cooldown": 0.6, "range": 95.0, "damage": 16.0, "arc": 2.0,
		"bolt_damage": 10.0, "bolt_speed": 520.0, "burn_dps": 6.0, "burn_time": 2.5,
	},
}

const SPELLS := {
	"fireball": {
		"name": "Fireball", "blurb": "Explodes and sets enemies alight.",
		"cooldown": 4.0, "damage": 40.0, "radius": 95.0, "speed": 620.0,
		"burn_dps": 8.0, "burn_time": 3.0, "color": Color(1.0, 0.45, 0.1),
	},
	"frost_nova": {
		"name": "Frost Nova", "blurb": "Chills everything around you.",
		"cooldown": 7.0, "damage": 15.0, "radius": 180.0,
		"slow": 0.45, "slow_time": 3.0, "color": Color(0.55, 0.85, 1.0),
	},
	"blink": {
		"name": "Blink", "blurb": "Teleport a short way, briefly untouchable.",
		"cooldown": 5.0, "distance": 230.0, "invuln": 0.4, "color": Color(0.8, 0.6, 1.0),
	},
}

const ENEMIES := {
	"slime": {"hp": 40.0, "speed": 115.0, "radius": 18.0, "touch": 10.0, "color": Color(0.4, 0.85, 0.4)},
	"archer": {"hp": 30.0, "speed": 95.0, "radius": 16.0, "touch": 6.0, "color": Color(0.9, 0.8, 0.35),
		"keep_away": 300.0, "shot_every": 2.0, "shot_damage": 8.0, "shot_speed": 330.0},
	"brute": {"hp": 130.0, "speed": 60.0, "radius": 28.0, "touch": 20.0, "color": Color(0.85, 0.35, 0.3),
		"charge_every": 4.0, "charge_speed": 460.0},
	"boss": {"hp": 650.0, "speed": 55.0, "radius": 48.0, "touch": 22.0, "color": Color(0.65, 0.3, 0.85),
		"charge_every": 5.0, "charge_speed": 420.0, "ring_every": 3.5, "ring_count": 12,
		"shot_damage": 10.0, "shot_speed": 260.0},
}

## Each wave lists how many of each enemy appear. The last wave is the boss.
const WAVES := [
	{"slime": 5},
	{"slime": 4, "archer": 2},
	{"slime": 3, "archer": 2, "brute": 1},
	{"boss": 1, "slime": 2},
]

## Small boosts offered between waves. They last for this run only.
const BOONS := [
	{"id": "damage", "text": "+20% damage"},
	{"id": "vigor", "text": "+25 max HP and heal 25"},
	{"id": "haste", "text": "Spells recharge 20% faster"},
	{"id": "swift", "text": "+12% move speed"},
	{"id": "fury", "text": "Attack 15% faster"},
	{"id": "pierce", "text": "Arrows and fire bolts pierce one more enemy"},
	{"id": "chill", "text": "Your attacks chill enemies, slowing them"},
	{"id": "leech", "text": "Heal 3 HP for every kill"},
]
