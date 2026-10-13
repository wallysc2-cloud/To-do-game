# To-do Game

A turn-based tactics game for your phone where finishing real to-do tasks powers up your squad.
The full design lives in the [design doc](https://claude.ai/code/artifact/b888370d-f0da-46ac-9b27-dd10b820127d).

## What's here now

### The village

Between missions you're in your home village. Tap a building:

- **Quest Board:** your to-do list. Add a task, rate it Easy, Medium, Hard or Epic, and optionally split it into steps.
  Each step pays 5 gold. Finishing the task gives energy (1, 2, 4 or 8) and a chest of gold that may hold a charm.
  Epic tasks are limited to 2 a day unless you switch the limit off.
- **Armory:** buy weapons and armour for your three heroes with gold, and put charms on them. Gear is yours for good.
- **Vault:** charms only come from task chests and are never lost. Each one changes a hero, usually with a trade-off.
  You can also back up your save as a code and restore it.
- **The gate:** a mission costs 4 energy. Energy refills by 1 every 15 minutes up to 12, and tasks can push it past 12.
  A mission in progress is saved, so you can close the game and carry on later for free.

Progress is saved in the browser on your phone.

### Missions: turn-based tactics

A light take on Warhammer 40K: Mechanicus. Hold your phone sideways; everything is a tap.

- **Your squad:** Bram the Knight (tough, shield bash knocks monsters back), Wren the Ranger (long-range shots, pinning)
  and Ivo the Mage (spells, healing, a fireball that burns friends too).
- **The map:** a mission is a branching route of rooms from your camp to the Bone King. Pick your way through battles,
  elite battles, treasure, shrines (heal, and fallen heroes get back up) and crystal caves (+3 Focus next battle).
  Wounds carry over from room to room.
- **Battles:** a grid with walls. Each turn every hero can move once and act once. Tap a hero, tap a blue tile to move,
  then tap a monster to attack or pick an ability. Abilities and sprints cost **Focus**, which the whole squad shares;
  you get 1 more each turn, and stepping on a glowing crystal gives 2.
- **Monsters:** skeletons, bone archers, ghoul brutes and grave shamans who heal the others. The Bone King slams
  everyone next to him and calls up more skeletons.
- Gold you find is banked even if your squad falls or you retreat. Beating the Bone King makes the next mission tougher.

## Tuning

Every number (heroes, monsters, abilities, gear, Focus, the rooms on a mission) is in `scripts/data.gd`.
Energy, task rewards and chest chances are at the top of `scripts/profile.gd`.

## How it's built

- Godot 4.4, 2D, drawn with simple shapes until we add a pixel-art pack.
- `scripts/game.gd` runs the flow between the village, the mission map and battles, plus the self-tests.
- `scripts/combat.gd` holds the battle rules and the monsters' moves; `scripts/battle.gd` draws a battle and turns taps into orders.
- `scripts/mission.gd` builds a mission's route; `scripts/map.gd` draws it.
- `scripts/profile.gd` is the save: gold, energy, tasks, gear, charms and the mission in progress.
  `scripts/village.gd` draws the village and its windows.
- Every push and pull request checks the battle rules, has a bot play 900 battles and 100 missions,
  checks 500 mission routes and the village rules, then plays whole missions on screen in headless Godot.
  The build fails on any script error.
- Pushes to `main` export the game for the web and publish it with GitHub Pages.

## Run it on a computer

Open the folder in Godot 4.4 and press Play.

Headless tests:

```sh
godot --headless --import --path .
godot --headless --path . -- --autotest=battles
godot --headless --path . -- --autotest=missions
godot --headless --path . -- --autotest=village
godot --headless --fixed-fps 60 --path . -- --autotest=play
```
