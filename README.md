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
Space                   jump; hold it, auto-bhop is on. Single-block steps and
                        stairs are walked over, no jump needed
Shift                   slide
Shift + Space           slide-hop. Chains to 16.5 m/s from a base of 7.5
Space into a wall       wall-jump, two charges, restored on landing
LMB / RMB               fire / aim. Aiming hides the crosshair and puts the weapon's
                        own sight exactly on the impact point. Standing still and
                        aimed gives a pinpoint first shot
R                       reload
V                       melee
1 / 2 / Q               primary, pistol, cycle. The sniper has a real optic:
                        a hollow scope you see through, a 2x-over-irons zoom
                        and its own hairline reticle
1-4 or click            pick a class, at match start and on every respawn
Space                   keep the class you had, and spawn the moment you can
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

You pick a class before spawning. A class is only a primary weapon — everyone
carries the pistol as a secondary, so no pick can leave you with no answer at
close range. Triggerman takes the assault rifle, Run N Gun the SMG, Marksman
the sniper, Spray N Pray the shotgun. Space keeps the class you already had,
which is what you want on almost every respawn, so it is the fastest key on the
screen.

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
make classtest   # class-select state machine, incl. handing control back to gameplay
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

## What the fps numbers mean

`make bench` at 1600x900 reports exactly 120.0 fps on this machine, and it
reports that whether you run 0 bots or 7, at 640x360 or 1600x900, with the
physics tick at 60, 120 or 240 Hz. A number invariant to every input is a
ceiling being imposed from outside, not a measurement of the game — vsync is
genuinely off (`window_get_vsync_mode` returns 0, `Engine.max_fps` is 0), so
it is the platform presenting.

So treat 120 at 1600x900 as a floor. To get a real load figure, push past the
cap with resolution:

  1600x900    120.0 fps    8.3 ms   (capped; true cost is lower)
  2560x1440    63.4 fps   15.7 ms
  3840x2160    45.7 fps   22.0 ms

60+ at 1440p with 770 map boxes, ~200 draw calls and eight actors fighting is
the honest claim.

## project.godot comments must start with ";"

A `#` line is NOT a comment in `project.godot` — it silently voids the key
below it. Two `#` lines above `textures/vram_compression/import_etc2_astc=true`
made the engine read that setting back as `false` while the file plainly said
`true`, and `make release` refused to export with "Cannot export for universal
or arm64 if ETC2 ASTC texture format is disabled".

`make check` now fails on any `#` comment in that file.

## Aiming

Right mouse aims. The gun and its front sight move to **exactly the centre of
the screen** and the HUD crosshair disappears — the sight is the aim point, so
a second reticle on top of it is clutter. This is a deliberate departure from
Krunker, which keeps a canted off-centre gun and its crosshair while aiming
irons: two critics argued for the Krunker behaviour and it is simply worse to
shoot with. A scoped weapon draws its own reticle inside the optic.
