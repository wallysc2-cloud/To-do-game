# To-do Game

A roguelite RPG for your phone where finishing real to-do tasks powers you up.
The full design lives in the [design doc](https://claude.ai/code/artifact/b888370d-f0da-46ac-9b27-dd10b820127d).

## What's here now

### The village

Between runs you're in your home village. Tap a building:

- **Quest Board:** your to-do list. Add a task, rate it Easy, Medium, Hard or Epic, and optionally split it into steps.
  Each step pays 5 gold. Finishing the task gives energy (1, 2, 4 or 8) and a chest of gold that may hold a trinket.
  Epic tasks are limited to 2 a day unless you switch the limit off.
- **Blacksmith:** spend gold on permanent upgrades (more hearts, a sharper sword, faster Fire). The forge grows as you upgrade.
- **Vault:** trinkets only come from task chests and are never lost. Wear one at a time; each changes how you play.
  You can also back up your save as a code and restore it.
- **The cave:** a run costs 4 energy. Energy refills by 1 every 15 minutes up to 12, and tasks can push it past 12.
  Gold found in the cave is kept even if you fall.

Progress is saved in the browser on your phone.

### The cave: the platformer

A 2D platformer roguelite in the spirit of Spelunky and Celeste. Hold your phone sideways.

- Each run is 3 caves deep, then the **Cave King's lair**. Every cave is stitched together from random rooms, so no two runs match.
- Find the glowing door to go deeper. Between caves, **pick 1 of 3 boosts** that last for this run.
- Caves have wooden ledges (jump up through them, or hold down and jump to drop), crumbling blocks, spikes and gold.
- Monsters: slimes and brutes patrol, bats swoop, frogs hop at you, spitters lob globs.
- The Cave King leaps and sends shockwaves along the floor, throws rocks and charges. Charging into a wall dazes it, and hits on a dazed king count double.
- Movement is Celeste-style: coyote time, buffered jumps, wall slides, wall jumps and an 8-way dash.
- **Stomp** monsters, slash them with the **Sword**, or throw **Fire**, which also blasts holes in the rock.
- Grab gold on the way. Spikes and monsters cost a heart; lose all 4 and the run is over.

Controls:

- **Phone:** drag on the left half to move. On the right half, tap to jump (hold for a higher jump) and swipe to dash that way, in 8 directions, even in the air. Sword and Fire are two small buttons on the right.
- **Keyboard:** arrows or WASD to move, Space or Z to jump, X or Shift to dash, C or J for Sword, V or K for Fire.

## Tuning

Every number (jump height, gravity, dash speed, enemy health, boosts) is in `scripts/data.gd`.
Room layouts are the text templates at the top of `scripts/level_gen.gd`.

## How it's built

- Godot 4.4, 2D, drawn with simple shapes until we add a pixel-art pack.
- `scripts/game.gd` runs the run, the camera, menus and input.
- `scripts/profile.gd` is the save: gold, energy, tasks, upgrades and trinkets, with all their numbers.
  `scripts/village.gd` draws the village and its windows.
- `scripts/level_gen.gd` builds a cave from room templates; `scripts/level.gd` draws it and handles tile collision.
- `scripts/player.gd`, `enemy.gd`, `boss.gd`, `shot.gd`, `fireball.gd`, `fx.gd` and `hud.gd` are the pieces it uses.
- Every push and pull request generates 300 caves and checks the door can be reached in each,
  checks the village rules (energy, tasks, chests, upgrades, backups) and the touch controls,
  then a bot plays a run and fights the boss in headless Godot. The build fails on any script error.
- Pushes to `main` export the game for the web and publish it with GitHub Pages.

## Run it on a computer

Open the folder in Godot 4.4 and press Play.

Headless tests:

```sh
godot --headless --import --path .
godot --headless --path . -- --autotest=levels
godot --headless --path . -- --autotest=village
godot --headless --path . -- --autotest=controls
godot --headless --fixed-fps 60 --path . -- --autotest=play
godot --headless --fixed-fps 60 --path . -- --autotest=boss
```
