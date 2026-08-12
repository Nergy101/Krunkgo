# BLOCKSHOT

A single-player voxel arena FPS in Godot 4.7, built to match the feel of
[Krunker.io](https://krunker.io/). Seven AI opponents, free-for-all, on a
walled sand-stone village called Burg.

No multiplayer, no asset files, no external dependencies. Every texture and
every sound is synthesised at boot, and every scene except a one-line entry
point is constructed in code.

```sh
make run
```

---

## Requirements

Godot **4.7** (the Mono build is what this was developed against; plain Godot
works too — GDScript only, no C#). Point the Makefile anywhere:

```sh
make run GODOT=/path/to/Godot
```

## Running

| Command | What it does |
|---|---|
| `make run` | Play from source with the debugger attached. This is the normal way to run it. |
| `make release` | Export a real native binary to `build/` and run that. |
| `make templates` | Report whether the export templates a release build needs are installed. |
| `make templates-install` | Download and unpack them (~1.3 GB). |
| `make check` | Fail on any GDScript parse error. |
| `make help` | List every target. |

There is no build step for a debug run — Godot interprets the GDScript
directly, so `make run` is the whole loop. `make release` is a genuine compiled
export and therefore needs the matching export templates; without them it stops
with instructions rather than pretending to succeed.

## Controls

```
WASD                    move — holding two keys gives the 1.2x diagonal strafe bonus
Space                   jump; hold it, auto-bhop is on
Shift                   slide
Shift + Space           slide-hop. Chains to 16.5 m/s from a base of 7.5
Space into a wall       wall-jump, two charges, restored on landing
LMB / RMB               fire / aim. Standing still and aimed gives a pinpoint first shot
R                       reload
V                       melee
1 2 3 / Q               weapon slots / cycle
Tab                     scoreboard
F5                      restart the match
Esc                     pause and release the mouse
```

The number under the crosshair is your speed. Watch it climb from 75 to 165
while slide-hopping — that readout is where Krunker puts it too.

## How it plays

Movement is the skill expression, as it is in Krunker. Walking is 7.5 m/s;
chaining jump into slide into jump compounds to the 16.5 m/s ceiling over about
five hops, and holding two direction keys is worth exactly 1.2x, which is the
documented Krunker default. There is no sprint key.

Those numbers are deliberately a third slower than the first tuning pass. At
11 m/s base and a 26 m/s peak you crossed the whole 64 m arena in about two and
a half seconds, which read as frantic rather than fast and left no room to aim.
The shape survived the cut: slide-hopping still roughly doubles your speed and
covers 1.7x the ground of walking over the same three seconds.

Five weapons, with damage and cadence taken from sourced Krunker numbers rather
than invented: assault rifle, sniper, shotgun, SMG, pistol. Headshot multipliers
live per weapon, so the SMG correctly has none. Hits resolve against four zones
derived from the same constants the visible character model is built from.

The bots run the identical `Motor` and `Weapon` as you do. They slide, they
bhop, they miss, they reload, they break line of sight when they are losing, and
their preferred engagement range depends on the gun they spawned with — a
shotgun bot closes, a sniper bot holds a lane.

## Layout

The arena has named lanes, because a map without them is a diagram:

- **LONG** — the sniper corridor along the north wall, crossable under fire
  thanks to staggered cover at three heights
- **MID** — the raised plaza that overlooks LONG and both sites; holding it is
  the whole game
- **A-SITE** — a three-storey guardhouse with the only roof that sees the map
- **B-SITE** — a warehouse with two entrances and a fightable interior
- **WEST TERRACE** — three houses with 3-wide alleys between them
- **TUNNEL** — a covered flank that lets you leave LONG without crossing open
  ground

## Project structure

```
project.godot        autoloads: Tuning, Game, Audio, Harness. 120 Hz physics
scenes/main.tscn     the only .tscn on disk; everything else is built in code
scripts/
  tuning.gd          every feel constant, split into blocks by owning concern
  game.gd            match state and the signal bus all feedback flows through
  harness.gd         bench / screenshot / probe CLI modes
  motor.gd           quake-lineage movement shared by the player and the bots
  actor.gd           shared base: capsule, hitboxes, health, death, respawn
  player.gd          input, camera, recoil-aware aim, feedback, autopilot
  bot.gd             AI actor; bot_brain.gd is its decision layer
  weapon.gd          hitscan, spread, recoil, reload, zone damage
  weapon_defs.gd     weapon table anchored to sourced Krunker numbers
  map_data.gd        the arena as pure box data; map_builder.gd merges it
  palette.gd         colours plus ten procedurally synthesised textures
  world_env.gd       sky, sun, fog, ambient shading
  viewmodel.gd       the gun, rendered through its own SubViewport
  fx.gd              pooled tracers, casings, muzzle flash, damage numbers
  audio.gd           every sound synthesised at boot
ui/hud.gd            crosshair, health, ammo, killfeed, scoreboard
tools/round.sh       one command for a full evidence round
reference/           sourced Krunker research and real gameplay screenshots
```

### Why scenes are built in code

Only `scenes/main.tscn` exists, and it is three lines. Everything else —
arena, actors, HUD, effects — is constructed at runtime. This project was built
by many agents editing in parallel, and GDScript merges cleanly while `.tscn`
files do not.

## Measuring it

Feel is not judgeable from a screenshot, so the things that matter have probes
that print one line of JSON:

```sh
make movetest    # slide-hop gain, strafe bonus, jump apex, wall-jump
make bottest     # per-bot idle, engagement, retreat, cover, slide
make hittest     # shots-to-kill vs the sourced table, falloff, first-shot accuracy
make bench       # frame timings with vsync off
make round       # all of the above plus every screenshot
```

`make hittest` checks itself against `reference/krunker-weapons.md`: assault 5
shots to kill, pistol 3, SMG 6, sniper 1, all matching the source.

Current performance is roughly **116–128 fps** at 1600x900 on an Apple M2, p50
around 8 ms.

## Where the numbers come from

`reference/` holds three sourced research documents with a citation on every
value, plus 15 verified real Krunker gameplay screenshots used as the visual
bar. Where the written research and a screenshot disagreed, the screenshot won —
that is how the HUD layout was corrected.

`PROGRESS.md` tracks the build as a gauntlet loop: each piece is judged by a
separate harsh critic against the real thing, and the gaps drive the next round.
It also records the bugs worth remembering, including the one where every
hand-built face in the map was wound backwards and you could see through walls.
