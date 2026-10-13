## Tunable numbers and content: heroes, monsters, abilities, gear and missions.
## Change values here to adjust the game; no other code needs touching.
extends RefCounted

# ---------------------------------------------------------------- battles
const GRID_W := 9
const GRID_H := 6
const FOCUS_START := 2      # shared Focus the squad starts each battle with
const FOCUS_PER_TURN := 1   # gained at the start of each of your turns
const FOCUS_MAX := 8
const CRYSTAL_FOCUS := 2    # stepping on a glowing crystal gives this much Focus
const SPRINT_MOVE := 2      # spending 1 Focus lets a hero move this much further

## Abilities. "range" 1 means next to the target (including diagonals).
## cost is in Focus; 0 means it's the hero's free basic attack.
const ABILITIES := {
	"slash": {"name": "Slash", "range": 1, "damage": 3, "cost": 0, "text": "Hit an enemy next to you"},
	"bash": {"name": "Shield Bash", "range": 1, "damage": 2, "cost": 1, "push": 2, "text": "Hit and knock back 2 tiles. Slamming into something hurts +2"},
	"cleave": {"name": "Cleave", "range": 1, "damage": 2, "cost": 2, "around": true, "text": "Hit every enemy around you"},
	"shoot": {"name": "Shoot", "range": 5, "damage": 2, "cost": 0, "text": "Fire an arrow"},
	"aimed": {"name": "Aimed Shot", "range": 7, "damage": 5, "cost": 2, "text": "A heavy, long-range shot"},
	"pin": {"name": "Pinning Shot", "range": 5, "damage": 1, "cost": 1, "root": true, "text": "The target can't move next turn"},
	"spark": {"name": "Spark", "range": 4, "damage": 2, "cost": 0, "text": "A small bolt of magic"},
	"fireball": {"name": "Fireball", "range": 4, "damage": 3, "cost": 2, "radius": 1, "text": "Burns everything around the target tile, friends too"},
	"mend": {"name": "Mend", "range": 3, "heal": 4, "cost": 1, "ally": true, "text": "Heal a hero (or yourself)"},
}

const HEROES := {
	"knight": {"name": "Bram", "role": "Knight", "hp": 12, "move": 3, "armour": 1, "abilities": ["slash", "bash", "cleave"], "color": Color(0.55, 0.7, 0.95)},
	"ranger": {"name": "Wren", "role": "Ranger", "hp": 8, "move": 4, "armour": 0, "abilities": ["shoot", "pin", "aimed"], "color": Color(0.5, 0.85, 0.5)},
	"mage": {"name": "Ivo", "role": "Mage", "hp": 7, "move": 3, "armour": 0, "abilities": ["spark", "mend", "fireball"], "color": Color(0.85, 0.55, 1.0)},
}
const HERO_ORDER := ["knight", "ranger", "mage"]

## Monsters. ai: "melee" walks up and hits, "ranged" keeps shooting from range,
## "healer" patches up its friends, "boss" has its own pattern.
const ENEMIES := {
	"skeleton": {"name": "Skeleton", "hp": 5, "move": 3, "armour": 0, "damage": 2, "range": 1, "ai": "melee", "gold": 4, "color": Color(0.85, 0.83, 0.75)},
	"archer": {"name": "Bone Archer", "hp": 4, "move": 2, "armour": 0, "damage": 2, "range": 4, "ai": "ranged", "gold": 5, "color": Color(0.75, 0.7, 0.55)},
	"brute": {"name": "Ghoul Brute", "hp": 12, "move": 2, "armour": 0, "damage": 4, "range": 1, "ai": "melee", "gold": 8, "color": Color(0.6, 0.75, 0.45)},
	"shaman": {"name": "Grave Shaman", "hp": 6, "move": 2, "armour": 0, "damage": 2, "range": 3, "heal": 2, "ai": "healer", "gold": 7, "color": Color(0.55, 0.45, 0.8)},
	"boss": {"name": "The Bone King", "hp": 24, "move": 2, "armour": 0, "damage": 3, "range": 1, "ai": "boss", "gold": 40, "color": Color(0.95, 0.8, 0.35)},
}

## Which monsters a battle can have. Each mission level adds a little strength.
const ENCOUNTERS := {
	"battle": [["skeleton", "skeleton", "archer"], ["skeleton", "skeleton", "skeleton"], ["skeleton", "archer", "archer"], ["brute", "skeleton"], ["skeleton", "shaman", "skeleton"]],
	"elite": [["brute", "brute", "archer"], ["brute", "shaman", "skeleton", "skeleton"], ["archer", "archer", "archer", "shaman"]],
	"boss": [["boss", "skeleton"], ["boss", "archer"]],
}

# ---------------------------------------------------------------- missions
const MISSION_LAYERS := 5   # rooms you pass through before the boss
const ROOM_KINDS := {
	"battle": {"name": "Battle", "text": "Monsters. Win to move on."},
	"elite": {"name": "Elite battle", "text": "Tougher monsters, more gold."},
	"treasure": {"name": "Treasure", "text": "A chest of gold."},
	"shrine": {"name": "Shrine", "text": "Your squad heals half their wounds."},
	"crystal": {"name": "Crystal cave", "text": "Start the next battle with +3 Focus."},
	"boss": {"name": "The Bone King", "text": "Beat him to finish the mission."},
}

# ---------------------------------------------------------------- gear
## Bought at the Armory with gold, or found only in task chests ("task": true).
## Stat changes: damage (all attacks), hp, armour (blocks damage), move, range (ranged attacks),
## focus (extra Focus each turn), spell (extra damage and healing for spells).
const ITEMS := {
	# Weapons, one line per hero. The first of each is what they start with.
	"iron_sword": {"name": "Iron Sword", "slot": "weapon", "hero": "knight", "cost": 0, "mods": {}},
	"steel_sword": {"name": "Steel Sword", "slot": "weapon", "hero": "knight", "cost": 60, "mods": {"damage": 1}},
	"war_axe": {"name": "War Axe", "slot": "weapon", "hero": "knight", "cost": 160, "mods": {"damage": 2, "move": -1}},
	"short_bow": {"name": "Short Bow", "slot": "weapon", "hero": "ranger", "cost": 0, "mods": {}},
	"long_bow": {"name": "Long Bow", "slot": "weapon", "hero": "ranger", "cost": 60, "mods": {"range": 1, "damage": 1}},
	"crossbow": {"name": "Heavy Crossbow", "slot": "weapon", "hero": "ranger", "cost": 160, "mods": {"damage": 2, "move": -1}},
	"oak_staff": {"name": "Oak Staff", "slot": "weapon", "hero": "mage", "cost": 0, "mods": {}},
	"ember_staff": {"name": "Ember Staff", "slot": "weapon", "hero": "mage", "cost": 80, "mods": {"spell": 1}},
	"crystal_staff": {"name": "Crystal Staff", "slot": "weapon", "hero": "mage", "cost": 180, "mods": {"spell": 1, "focus": 1}},
	# Armour, anyone can wear it.
	"cloth": {"name": "Traveller's Cloth", "slot": "armour", "hero": "", "cost": 0, "mods": {}},
	"leather": {"name": "Leather Coat", "slot": "armour", "hero": "", "cost": 50, "mods": {"hp": 3}},
	"chainmail": {"name": "Chainmail", "slot": "armour", "hero": "", "cost": 120, "mods": {"armour": 1, "hp": 2}},
	"plate": {"name": "Plate Armour", "slot": "armour", "hero": "", "cost": 220, "mods": {"armour": 2, "move": -1}},
	# Charms: only from task chests, never lost. Sidegrades, not straight upgrades.
	"lucky_coin": {"name": "Lucky Coin", "slot": "charm", "hero": "", "task": true, "mods": {"gold": 25}, "text": "+25% gold from missions"},
	"feather_cloak": {"name": "Feather Cloak", "slot": "charm", "hero": "", "task": true, "mods": {"move": 2, "hp": -2}, "text": "+2 move, -2 health"},
	"ember_ring": {"name": "Ember Ring", "slot": "charm", "hero": "", "task": true, "mods": {"spell": 2, "armour": -1}, "text": "Spells +2, but -1 armour"},
	"glass_blade": {"name": "Glass Blade", "slot": "charm", "hero": "", "task": true, "mods": {"damage": 2, "hp": -3}, "text": "+2 damage, -3 health"},
	"tiny_crown": {"name": "Tiny Crown", "slot": "charm", "hero": "", "task": true, "mods": {"focus_start": 1}, "text": "Start battles with +1 Focus. And it looks great"},
}
const CHARM_ORDER := ["lucky_coin", "feather_cloak", "ember_ring", "glass_blade", "tiny_crown"]
const STARTING_GEAR := {
	"knight": {"weapon": "iron_sword", "armour": "cloth", "charm": ""},
	"ranger": {"weapon": "short_bow", "armour": "cloth", "charm": ""},
	"mage": {"weapon": "oak_staff", "armour": "cloth", "charm": ""},
}

# ---------------------------------------------------------------- hero levels
## XP each hero gets for winning a room's battle (heroes who fell in it get half).
const XP := {"battle": 10, "elite": 20, "boss": 40}
const XP_PER_LEVEL := 30    # reaching level n + 1 takes 30 x n XP
const MAX_LEVEL := 10
## Every level gives +1 health; these levels also give +1 damage.
const DAMAGE_LEVELS := [3, 6, 9]

# ---------------------------------------------------------------- loot
## Gear found on missions. It goes in the mission's bag and comes home when the mission ends.
const LOOT_CHANCE := {"battle": 0.15, "elite": 0.6, "treasure": 0.5, "boss": 1.0}
const RARITIES := {
	"common": {"name": "Common", "weight": 60, "rolls": 1, "color": Color(0.85, 0.85, 0.85)},
	"rare": {"name": "Rare", "weight": 30, "rolls": 2, "color": Color(0.45, 0.7, 1.0)},
	"epic": {"name": "Epic", "weight": 10, "rolls": 3, "color": Color(0.8, 0.5, 1.0)},
}
const RARITY_ORDER := ["common", "rare", "epic"]
const LOOT_WEAPONS := {"knight": ["Sword", "Axe", "Mace"], "ranger": ["Bow", "Longbow", "Sling"], "mage": ["Staff", "Wand", "Orb"]}
const LOOT_ARMOUR := ["Coat", "Mail", "Robe", "Vest"]
## What a roll can add. Weapons and armour each pick from their own list.
const WEAPON_ROLLS := [{"damage": 1}, {"damage": 1}, {"range": 1}, {"spell": 1}, {"move": 1}, {"hp": 2}]
const ARMOUR_ROLLS := [{"hp": 2}, {"hp": 3}, {"armour": 1}, {"move": 1}, {"focus_start": 1}]
## Weapons can carry an element (rare ones sometimes, epic ones always). It changes how they hit.
const ELEMENTS := {
	"fire": {"name": "Flaming", "text": "Hits set monsters on fire: 2 more damage when their turn starts"},
	"frost": {"name": "Frozen", "text": "Hits chill monsters: they can only move 1 tile next turn"},
	"storm": {"name": "Storm", "text": "Hits spark 1 damage onto every other monster next to the target"},
	"holy": {"name": "Holy", "text": "Heals this hero 1 for every hit"},
}
const ELEMENT_ORDER := ["fire", "frost", "storm", "holy"]

# ---------------------------------------------------------------- blessings
## After each battle you pick 1 of 3. They last for the rest of the mission.
const BOONS := {
	"tough": {"name": "Iron Skin", "text": "Everyone +2 max health (and heals 2)"},
	"sharp": {"name": "Whetstone", "text": "Everyone deals +1 damage"},
	"swift": {"name": "Light Boots", "text": "Everyone moves +1 tile"},
	"flow": {"name": "Deep Breath", "text": "+1 Focus every turn"},
	"ready": {"name": "War Cry", "text": "Start every battle with +2 Focus"},
	"mend": {"name": "Field Dressing", "text": "Heal everyone 6 right now", "repeat": true},
	"warded": {"name": "Ward Stone", "text": "Everyone +1 armour"},
}

# ---------------------------------------------------------------- when your squad falls
## Picked when you start. You can make it gentler later, never harsher. Retreating is always safe.
const PENALTIES := {
	"nothing": {"name": "Relaxed", "text": "Keep the gold and gear you found."},
	"loot": {"name": "Normal", "text": "Keep the gold, but lose the gear in the mission's bag."},
	"bag": {"name": "Tough", "text": "Lose the gold and the gear you found on that mission."},
	"hardcore": {"name": "Hardcore", "text": "Start over: gold, gear, levels and progress are wiped. Task charms are always kept."},
}
const PENALTY_ORDER := ["nothing", "loot", "bag", "hardcore"]

# ---------------------------------------------------------------- daily tasks
const STREAK_MAX := 5          # bonus stops growing after 5 days in a row
const STREAK_GOLD := 10        # +10% chest gold per streak day
