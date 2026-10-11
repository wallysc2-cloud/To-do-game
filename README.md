# To-do Game

A roguelite RPG for your phone where finishing real to-do tasks powers you up.
The full design lives in the [design doc](https://claude.ai/code/artifact/b888370d-f0da-46ac-9b27-dd10b820127d).

## What's here now: the combat prototype

One arena, three waves and a boss, played Archero-style:

- **Drag anywhere** in the arena to move. A stick appears under your finger.
- **Stand still** and your hero attacks the nearest enemy on their own.
- **Tap the two round buttons** to cast your spells.
- After each wave, **pick 1 of 3 boosts**. They last for this run only.

Before a run you choose a weapon (Sword, Bow or Flame Sword) and 2 of 3 spells
(Fireball, Frost Nova, Blink).

## Tuning

Every number (damage, speed, cooldowns, enemy health, what each wave contains,
the boosts on offer) is in `scripts/data.gd`. Change a value there and the game
picks it up; no other code needs touching.

## How it's built

- Godot 4.4, 2D, drawn with simple shapes until we add a pixel-art pack.
- `scripts/game.gd` runs the arena, waves, menus and touch input.
- `scripts/player.gd`, `enemy.gd`, `projectile.gd`, `effect.gd`, `hud.gd` are the pieces it uses.
- Every push and pull request runs a smoke test: a bot plays one run with each weapon in
  headless Godot and the build fails on any script error.
- Pushes to `main` export the game for the web and publish it with GitHub Pages
  (Pages must be turned on for the repository, with "GitHub Actions" as the source).

## Run it on a computer

Open the folder in Godot 4.4 and press Play. The mouse acts as your finger.

Headless smoke test:

```sh
godot --headless --import --path .
godot --headless --fixed-fps 60 --path . -- --autotest=bow
```
