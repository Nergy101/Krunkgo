# BLOCKSHOT — gauntlet progress

Single-player voxel arena FPS in Godot 4.7. **Bar: [Krunker.io](https://krunker.io/)**.
Builders build, separate harsh critics compare our output against real Krunker,
we act on the gaps, repeat. Exit is winning the comparison, never a round count.

---

## Status

| Piece | Critic r1 | Critic r2 | Latest action |
|---|---|---|---|
| Match flow | not judged | **OURS** | first piece to win; dead signals then wired to the HUD |
| Movement feel | KRUNKER | KRUNKER | wall-jump added and now measured; cap freed to 26 |
| Bot behaviour | KRUNKER | KRUNKER | cover-seeking added after `bot_leave_cover_chance` was found dead |
| Hit registration | not judged | KRUNKER | shotgun measurement was broken by a zone-purity filter; fixed |
| HUD | KRUNKER | KRUNKER | crosshair now measures right; ammo chip and bar pips added |
| Block art + lighting | KRUNKER | agent died | r1 palette/env measurements applied |
| Map geometry | KRUNKER | agent died | 25 -> ~150 props, stairwells, crenellation |
| Weapon feedback | not judged | agent died | casings, per-weapon voices, travelling tracers |
| Viewmodel | not judged | agent died | own SubViewport, no wall clipping |

Four round-2 critics died mid-analysis. Five reported, and **one said OURS** —
the first piece to beat the bar.

## The see-through bug — root cause

Reported twice by the user. Two independent causes; I fixed the wrong one first.

1. **Zero-width wall piers.** A fixed 3-wide doorway punched into a 4-long wall
   face left a 0-wide pier, which renders inverted and vanishes.
   `MapBuilder._validate()` now runs at load and prints
   `MAPCHECK {"boxes":605,"degenerate":0}`; doorways are sized to their wall.
   A real bug, but not the one being seen.
2. **Every hand-built face was wound backwards.** `_emit_box` emitted
   `[0,1,2,0,2,3]` — right-hand-rule order — but Godot treats clockwise-from-
   the-front as the front face. Back-face culling therefore removed the *near*
   side of every box: you looked through walls into buildings, and through
   crates and containers. Proven by rendering once with `CULL_DISABLED`, which
   made everything solid. Fixed by flipping to `[0,2,1,0,3,2]`.

The second bug had been present since the first map and was also corrupting the
lighting, since every visible surface was lit by an inward-pointing normal.
`Blockman` and `Viewmodel` were never affected because they use engine
`BoxMesh` — which is why characters and guns always looked right.

It also **inflated every performance number recorded before now**: with front
faces culled, most geometry was skipped in both the camera and shadow passes.
Correct geometry costs real work, so the shadow budget dropped to 2 splits, a
62 m range and a 2048 map. Honest figure: **116-128 fps avg, p50 7.6-9.1 ms,
p95 10-11 ms** at 1600x900. An earlier 31 fps reading was CPU contention from
nine critics running image analysis, not a regression. SSAO measures free.

## Round 1 detail

| Piece | Round 1 finding |
|---|---|
| Movement | wall-jump entirely missing |
| Map | 1 prop per 154 m², none indoors or on a roof |
| Art | 43-58% saturation vs Burg's 27-29%; our textures had *less* detail than the bar |
| HUD | crosshair 4x too tight, measured in pixels |
| Bots | zero health awareness |


### Hit registration — `godot --path . -- hittest`

```
WEAPON    first-shot dev  body dmg  STK  sourced ref  head dmg  STK head
assault      0.0096 m        23.0     5       5          34.5       3
pistol       0.0096 m        34.0     3       3          54.4       2
smg          0.0096 m        18.0     6       6          18.0       6
sniper       0.0096 m       100.0     1       1         150.0       1
shotgun      0.9395 m        18.55    6       —          23.19       5
self_hits_total: 0
```

Every shots-to-kill matches `reference/krunker-weapons.md`. The SMG's head
damage equalling its body damage is the sourced Krunker quirk — it is the one
weapon with no headshot bonus — and it falls out of the per-weapon `hs_mult`
rather than a special case. Zone boxes now derive from `Blockman.ZONES`, the
same numbers the visible model is built from, and there are four of them: the
old three-box layout had no zone for the arms at all.

Four probe bugs had to be fixed before any of those numbers meant anything:
moving the dummy and raycasting in the same frame queried its **old** transform
(Area3D reaches the physics server on flush) so everything read zero hits;
recoil accumulated across the batch and walked the shots off target; the
first-shot metric never reset `shots_in_burst` so it measured a burst; and
`is_first_shot()` was consulted *after* `shots_in_burst` was incremented, so the
opener could never qualify.

**Every critic that has reported says KRUNKER wins.** That is the loop working as
designed, not a failure. Round 2 of critics has not run yet.

## Measured results

### Performance — `tools/round.sh r12`

```
avg_fps 133.7 · p50 6.96 ms · p95 10.65 ms · p99 13.06 ms
draw calls 239 · primitives 40514 · nodes 975
```

Vsync finally released, so this is a real headroom figure rather than a pinned
60. Comfortably above the 120 fps floor with 40k primitives on screen.

### Movement — `godot --path . -- movetest`

```
peak_walk_mps       11.000     slidehop_gain_ratio  1.773
peak_slidehop_mps   19.500     strafe_gain_ratio    1.200   (matches Krunker's documented default)
hops_to_peak             3     jump_apex_m          1.173
turn_retention       0.833     hard_cap_mps        26.000
```

Three real bugs found getting there: ground friction ran on the tick you left
the floor and taxed every launch; the probe was measuring a collision with a
building; and its crouch input was gated on `velocity.y < 0`, which
`move_and_slide` zeroes on the landing tick — exactly the tick the slide starts.

### Bots — `godot --path . -- bottest`

| metric | before | after |
|---|---|---|
| worst idle | 97.3% | 30.1% |
| avg engagement | 24.3% | 45.4% |
| slide ticks | 0 | 155 |
| out-of-bounds | 0 | 0 |

The mid-air hang I diagnosed from a screenshot did not exist. The real defect
was an unstick rule rolling a 25% jump chance *every tick*, so any blocked bot
hopped 120×/second forever.

## Critic round 1 — verdicts and what they caught

All five ran read-only with fresh context against `reference/bar/`.

**Bots — KRUNKER.** No health awareness anywhere: a bot at 15 HP pushed a
shotgun exactly like one at 100. Also caught that three of seven bots had zero
slide ticks, so my "intended slide-hop traversal" explanation of high air time
was only true for the other four. Fixed: `Tuning.bot_retreat_health`, retreat
branch, sniper stillness weighting.

**Movement — KRUNKER.** Wall-jump is a class-defining Krunker mechanic and did
not exist in any form. Also spotted that `slide_speed_cap = 19.5` saturated the
chain by hop 3, making `hard_speed_cap = 26` unreachable. Fixed: wall-jump with
charges reset on landing, cap raised to 23.5.

**Map — KRUNKER.** Counted it: 25 prop boxes across 3,844 m², one per 154 m²,
**none** indoors or on a roof, against 6–10 discrete props in every reference
frame. Also found the three-storey guardhouse billed as "the only roof that sees
the whole map" was unreachable — `_building` emitted floor slabs with no stairs
between them. Fixed: prop vocabulary (containers, barrels, pallets, telegraph
runs, awnings), interior stairwells, three cover heights, crenellated perimeter
with towers at varied heights.

**HUD — KRUNKER.** Pixel-measured the reticle: Krunker rests at a 36 px gap with
10 px dashes at 576h (16% of screen height); ours was 14 px and 7 px, about a
quarter of the footprint, and the speed readout sat inside the reticle. Fixed to
the measured numbers.

**Art — KRUNKER.** Sampled HSV directly: our field ran 43–58% saturation against
Burg's 27–29%, with neutral-grey pixels at 0.4–3.4% versus the bar's 7–23%. It
also **refuted my own assumption** — I worried the procedural textures looked
noisy; it measured our high-frequency sigma at 7.8–16.2 against the bar's
14.4–24.2 and showed we had *less* surface detail, not more. Applied its exact
palette and environment values and raised texture contrast.

## Evidence pipeline — a defect worth recording

The bot critic noticed our five "live bot fight" screenshots were the same
static corner of a room with HP frozen at 100/100 and no enemy on screen. Under
the harness the player has no input, so every visual critic was judging the game
from five pictures of a wall.

First fix attempt put a shoulder cam on an engaged bot. That showed combat but
paired it with the *local player's* HUD and viewmodel, so the frame lied: dead
player, frozen ammo, a gun floating over someone else's fight.

Real fix: `Player.enable_autopilot()` drives the actual player through the
actual `Motor` and `Weapon` using `BotBrain`, so the first-person view fights
for real and every overlay is honest. `shots/r12/game_2.png` now shows an enemy,
damage numbers, impact debris, a killfeed line and ammo counting down.
Separately, the viewmodel is a `CanvasLayer` composite and kept drawing over the
map shots — `main.viewmodel_visible(false)` now hides it for those.

## Known defects, ranked

1. **Critic round 2 has not run.** Every fix since round 1 is self-verified only,
   and weapon feedback, hit registration, viewmodel and match flow have never
   faced a critic at all.
2. Bots still do not use cover deliberately — they retreat on low health now, but
   nothing routes them behind geometry to break line of sight.
3. `bottest` still cannot separate purposeful slide-hop traversal from time spent
   airborne for any other reason, so `air_pct` remains an untrustworthy number.
4. The shotgun's 0.94 m first-shot deviation is by design (pellet cone), but the
   probe reports it in the same column as the precision weapons, which invites a
   misreading.

## How to run

```sh
GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot
$GODOT --headless --path . --import        # once; builds the class cache
$GODOT --path .                            # play
$GODOT --path . -- movetest                # movement metrics
$GODOT --path . -- bottest                 # bot behaviour metrics
tools/round.sh r13                         # parse + bench + all screenshots
```

Controls: WASD, Space jump (auto-bhop), Shift slide, wall-jump by jumping into a
wall mid-air, LMB fire, RMB ADS, R reload, 1/2/3 weapons, Q cycle, V melee,
Tab scoreboard, F5 restart, Esc pause.

## Resume here

1. Weapon feedback pass — `fx.gd` and `audio.gd` are untouched since round 0.
2. Hit-registration silhouette hitboxes plus `scripts/hittest.gd`.
3. Critic round 2 across all pieces, including viewmodel and match flow which
   have never been judged.## Status

| Piece | Critic r1 | Critic r2 | Notes |
|---|---|---|---|
| Match flow | not judged | **OURS** | first piece to win |
| Movement feel | KRUNKER | KRUNKER | wall-jump added + measured, cap freed to 26 |
| Bot behaviour | KRUNKER | KRUNKER | cover-seeking added after `bot_leave_cover_chance` found dead |
| Hit registration | not judged | KRUNKER | shotgun measurement was broken; now fixed |
| HUD | KRUNKER | KRUNKER | crosshair now measures right; ammo chip added |
| Block art + lighting | KRUNKER | agent died | palette values applied from r1 measurements |
| Map geometry | KRUNKER | agent died | 25 -> ~150 props, stairwells, crenellation |
| Weapon feedback | not judged | agent died | casings, per-weapon voices, travelling tracers |
| Viewmodel | not judged | agent died | own SubViewport, no wall clipping |

Four round-2 critics died mid-analysis. Five reported; **one said OURS.**

## The see-through bug — root cause

Reported twice by the user. It had two independent causes, and I fixed the
wrong one first.

1. **Zero-width wall piers.** A fixed 3-wide doorway punched into a 4-long wall
   face left a 0-wide pier. `MapBuilder._validate()` now runs at load and prints
   `MAPCHECK {"boxes":605,"degenerate":0}`; doorways are sized to their wall.
   Real bug, but not the one the user was seeing.
2. **Every hand-built face was wound backwards.** `_emit_box` emitted
   `[0,1,2,0,2,3]`, the right-hand-rule order, but Godot treats clockwise-from-
   the-front as the front face. Back-face culling therefore removed the *near*
   side of every box: you looked through walls into buildings, and through
   crates and containers. Proven by rendering once with `CULL_DISABLED`, where
   everything became solid. Fixed by flipping to `[0,2,1,0,3,2]`.

That second bug had been there since the first map and it was also corrupting
the lighting, because every visible surface was lit by an inward-pointing
normal. `Blockman` and `Viewmodel` were never affected — they use engine
`BoxMesh`, which is why characters and guns always looked correct.

**It also inflated every performance number ever recorded here.** With the front
faces culled, most geometry was skipped in both the camera and shadow passes.
Correct geometry costs real work, so the shadow budget was cut to 2 splits, a
62 m range and a 2048 map. Honest figure now: **116-128 fps avg, p50 7.6-9.1 ms,
p95 ~10-11 ms** at 1600x900. An earlier 31 fps reading was CPU contention from
nine critics running image analysis, not a regression; SSAO measures free.

## Measured results

### Performance — `tools/round.sh r12`

```
avg_fps 133.7 · p50 6.96 ms · p95 10.65 ms · p99 13.06 ms
draw calls 239 · primitives 40514 · nodes 975
```

Vsync finally released, so this is a real headroom figure rather than a pinned
60. Comfortably above the 120 fps floor with 40k primitives on screen.

### Movement — `godot --path . -- movetest`

```
peak_walk_mps       11.000     slidehop_gain_ratio  1.773
peak_slidehop_mps   19.500     strafe_gain_ratio    1.200   (matches Krunker's documented default)
hops_to_peak             3     jump_apex_m          1.173
turn_retention       0.833     hard_cap_mps        26.000
```

Three real bugs found getting there: ground friction ran on the tick you left
the floor and taxed every launch; the probe was measuring a collision with a
building; and its crouch input was gated on `velocity.y < 0`, which
`move_and_slide` zeroes on the landing tick — exactly the tick the slide starts.

### Bots — `godot --path . -- bottest`

| metric | before | after |
|---|---|---|
| worst idle | 97.3% | 30.1% |
| avg engagement | 24.3% | 45.4% |
| slide ticks | 0 | 155 |
| out-of-bounds | 0 | 0 |

The mid-air hang I diagnosed from a screenshot did not exist. The real defect
was an unstick rule rolling a 25% jump chance *every tick*, so any blocked bot
hopped 120×/second forever.

## Critic round 1 — verdicts and what they caught

All five ran read-only with fresh context against `reference/bar/`.

**Bots — KRUNKER.** No health awareness anywhere: a bot at 15 HP pushed a
shotgun exactly like one at 100. Also caught that three of seven bots had zero
slide ticks, so my "intended slide-hop traversal" explanation of high air time
was only true for the other four. Fixed: `Tuning.bot_retreat_health`, retreat
branch, sniper stillness weighting.

**Movement — KRUNKER.** Wall-jump is a class-defining Krunker mechanic and did
not exist in any form. Also spotted that `slide_speed_cap = 19.5` saturated the
chain by hop 3, making `hard_speed_cap = 26` unreachable. Fixed: wall-jump with
charges reset on landing, cap raised to 23.5.

**Map — KRUNKER.** Counted it: 25 prop boxes across 3,844 m², one per 154 m²,
**none** indoors or on a roof, against 6–10 discrete props in every reference
frame. Also found the three-storey guardhouse billed as "the only roof that sees
the whole map" was unreachable — `_building` emitted floor slabs with no stairs
between them. Fixed: prop vocabulary (containers, barrels, pallets, telegraph
runs, awnings), interior stairwells, three cover heights, crenellated perimeter
with towers at varied heights.

**HUD — KRUNKER.** Pixel-measured the reticle: Krunker rests at a 36 px gap with
10 px dashes at 576h (16% of screen height); ours was 14 px and 7 px, about a
quarter of the footprint, and the speed readout sat inside the reticle. Fixed to
the measured numbers.

**Art — KRUNKER.** Sampled HSV directly: our field ran 43–58% saturation against
Burg's 27–29%, with neutral-grey pixels at 0.4–3.4% versus the bar's 7–23%. It
also **refuted my own assumption** — I worried the procedural textures looked
noisy; it measured our high-frequency sigma at 7.8–16.2 against the bar's
14.4–24.2 and showed we had *less* surface detail, not more. Applied its exact
palette and environment values and raised texture contrast.

## Evidence pipeline — a defect worth recording

The bot critic noticed our five "live bot fight" screenshots were the same
static corner of a room with HP frozen at 100/100 and no enemy on screen. Under
the harness the player has no input, so every visual critic was judging the game
from five pictures of a wall.

First fix attempt put a shoulder cam on an engaged bot. That showed combat but
paired it with the *local player's* HUD and viewmodel, so the frame lied: dead
player, frozen ammo, a gun floating over someone else's fight.

Real fix: `Player.enable_autopilot()` drives the actual player through the
actual `Motor` and `Weapon` using `BotBrain`, so the first-person view fights
for real and every overlay is honest. `shots/r12/game_2.png` now shows an enemy,
damage numbers, impact debris, a killfeed line and ammo counting down.
Separately, the viewmodel is a `CanvasLayer` composite and kept drawing over the
map shots — `main.viewmodel_visible(false)` now hides it for those.

## Known defects, ranked

1. **Critic round 2 has not run.** Every fix since round 1 is self-verified only,
   and weapon feedback, hit registration, viewmodel and match flow have never
   faced a critic at all.
2. Bots still do not use cover deliberately — they retreat on low health now, but
   nothing routes them behind geometry to break line of sight.
3. `bottest` still cannot separate purposeful slide-hop traversal from time spent
   airborne for any other reason, so `air_pct` remains an untrustworthy number.
4. The shotgun's 0.94 m first-shot deviation is by design (pellet cone), but the
   probe reports it in the same column as the precision weapons, which invites a
   misreading.

## How to run

```sh
GODOT=/Applications/Godot_mono.app/Contents/MacOS/Godot
$GODOT --headless --path . --import        # once; builds the class cache
$GODOT --path .                            # play
$GODOT --path . -- movetest                # movement metrics
$GODOT --path . -- bottest                 # bot behaviour metrics
tools/round.sh r13                         # parse + bench + all screenshots
```

Controls: WASD, Space jump (auto-bhop), Shift slide, wall-jump by jumping into a
wall mid-air, LMB fire, RMB ADS, R reload, 1/2/3 weapons, Q cycle, V melee,
Tab scoreboard, F5 restart, Esc pause.

## Resume here

1. Weapon feedback pass — `fx.gd` and `audio.gd` are untouched since round 0.
2. Hit-registration silhouette hitboxes plus `scripts/hittest.gd`.
3. Critic round 2 across all pieces, including viewmodel and match flow which
   have never been judged.
