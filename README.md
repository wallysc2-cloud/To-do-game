# To-do Game

A roguelite RPG for your phone where finishing real to-do tasks powers you up.
The full design lives in the [design doc](https://claude.ai/code/artifact/b888370d-f0da-46ac-9b27-dd10b820127d).

## What's here now: the platformer prototype

A 2D platformer roguelite in the spirit of Spelunky and Celeste. Hold your phone sideways.

- Each run is 3 caves deep. Every cave is stitched together from random rooms, so no two runs match.
- Find the glowing door to go deeper. Between caves, **pick 1 of 3 boosts** that last for this run.
- Movement is Celeste-style: coyote time, buffered jumps, wall slides, wall jumps and an 8-way dash.
- **Stomp** monsters, slash them with the **Sword**, or throw **Fire**, which also blasts holes in the rock.
- Grab gold on the way. Spikes and monsters cost a heart; lose all 4 and the run is over.

Controls:

- **Phone:** drag on the left half to move. Jump, Dash, Sword and Fire buttons sit on the right.
- **Keyboard:** arrows or WASD to move, Space or Z to jump, X or Shift to dash, C or J for Sword, V or K for Fire.

## Tuning

Every number (jump height, gravity, dash speed, enemy health, boosts) is in `scripts/data.gd`.
Room layouts are the text templates at the top of `scripts/level_gen.gd`.

## How it's built

- Godot 4.4, 2D, drawn with simple shapes until we add a pixel-art pack.
- `scripts/game.gd` runs the run, the camera, menus and input.
- `scripts/level_gen.gd` builds a cave from room templates; `scripts/level.gd` draws it and handles tile collision.
- `scripts/player.gd`, `enemy.gd`, `fireball.gd`, `fx.gd` and `hud.gd` are the pieces it uses.
- Every push and pull request generates 300 caves and checks the door can be reached in each,
  then a bot plays a run in headless Godot. The build fails on any script error.
- Pushes to `main` export the game for the web and publish it with GitHub Pages.

## Run it on a computer

Open the folder in Godot 4.4 and press Play.

Headless tests:

```sh
godot --headless --import --path .
godot --headless --path . -- --autotest=levels
godot --headless --fixed-fps 60 --path . -- --autotest=play
```
