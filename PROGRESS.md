# BLOCKSHOT — gauntlet progress

Single-player voxel arena FPS in Godot 4.7. **Bar: [Krunker.io](https://krunker.io/)**.
Builders build, separate harsh critics with fresh context compare our output
against real Krunker screenshots, we act on the gaps, repeat. Exit is winning
the comparison, never a round count.

---

## Status — all nine pieces won

Every piece has been picked over Krunker by a fresh critic judging the
finished build. The last one took five verdicts to get there.

| Piece | r1 | r2 | r3 | final | What the final verdict turned on |
|---|---|---|---|---|---|
| Match flow | – | **OURS** | – | **OURS** | every signal traced to an emitter and a listener |
| Block art | KRUNKER | KRUNKER | **OURS** | **OURS** | sky within 2.4 channel-points of Burg |
| Movement | KRUNKER | KRUNKER | **OURS** | **OURS** | late re-jump penalty finally exercised |
| HUD | KRUNKER | KRUNKER | **OURS** | **OURS** | ammo cluster rebuilt to the reference layout |
| Weapon feedback | – | KRUNKER | – | **OURS** | flash and tracer visible in every fired frame |
| Hit registration | – | KRUNKER | – | **OURS** | all five weapons match the sourced table |
| Bots | KRUNKER | KRUNKER | KRUNKER | **OURS** | no stranded bot in 35 samples |
| Map | KRUNKER | KRUNKER | KRUNKER | **OURS** | three roof silhouettes, 5.3× cover spread |
| Viewmodel | – | KRUNKER | KRUNKER | **OURS** | canted ADS with hands, crosshair kept |

Four critics also died mid-analysis across rounds 2 and 3, burning their run on
exhaustive pixel work and yielding nothing. Later assignments told them to
answer in one or two passes and to yield a rough verdict over a perfect one
they never deliver.

---

## The bugs the critics found that we could not see

Every one of these was invisible from the code and only showed up because
something outside the code compared output against a reference.

**Every muzzle flash was a screen-filling white slab.** Godot's billboard
shader discards node scale unless `billboard_keep_scale` is set, so a 1×1 quad
rendered at full size half a metre from the lens on every shot. The critic only
reported "no flash appears in any frame". Chasing that found the slab.

**Tracers were invisible.** At 420 m/s a 20 m shot lives under 50 ms — three
frames. Now 140 m/s with an 11 m segment.

**Every hand-built face was wound backwards.** Back-face culling was removing
the *near* faces, so you looked through walls into interiors. The fix was one
vertex order; it also silently doubled the shadow cost that had been hidden.

**A third of the spawns were inside solid rock.** Widening the perimeter towers
swallowed four. The only symptom was three bots idle at 95% in a probe.

**One bot spawned in a sealed pocket** and paced a 9 m box for entire matches.
The geometry test passed it happily — being inside no box says nothing about
being connected to anything.

**The shotgun did 120 damage against a sourced ~50**, one-shotting where
Krunker needs two. The probe had derived its expectations from our own weapon
table and reported "ALL MATCH SOURCED REFERENCE" while it was 2.4× out.

**`seed=7` controlled almost nothing.** 24 call sites use the bare `randf()`
family, which Godot auto-seeds from the clock, so runs of the same seed differed
— even the baked textures. A critic read one bad sample as a stranded bot; it
was a lottery ticket. Now the global RNG is seeded and bot claims come from a
five-seed sweep.

**`#` is not a comment in `project.godot`.** Two `#` lines silently voided the
key beneath them, so `import_etc2_astc` read back as `false` while the file
plainly said `true`, and `make release` refused to export. Comments there must
start with `;`.

---

## Measured results

Movement, from `movetest`:

| | measured | source |
|---|---|---|
| walk | 7.50 m/s | — |
| slide-hop peak | 16.50 m/s | — |
| slide-hop gain | 2.20× | "faster than any other movement type" |
| distance gain over 3 s | 1.68× | — |
| strafe bonus | 1.20× | documented 1.2 default |
| stairs climbed, no jump | 2.80 of 3.00 m | one block must be walkable |
| wall-jumps performed | 2 | matches the 2-charge setting |
| late re-jump penalty | 0.892 | 0.88 setting, +1 tick of accel |

Shots to kill, from `hittest`, against the table in `reference/krunker-weapons.md`
(the expectations live in the probe as data, so it cannot agree with itself):

| weapon | body | head | source |
|---|---|---|---|
| assault | 5 | 3 | 5 / 3 |
| pistol | 5 | 4 | 5 / 4 |
| shotgun | 2 | 2 | 2 / 2 point-blank |
| smg | 6 | 6 | 6 / 6 |
| sniper | 1 | 1 | 1 / 1 |

Bots, five seeds × seven bots from `tools/botsweep.sh`:

| | value |
|---|---|
| engagement, min / mean / max | 38.1% / 53.8% / 78.0% |
| bots below 10% engagement | 0 of 35 |
| bot-samples that use cover | 85.7% |
| worst air time | 41.8% |
| incoming hits per second | 1.0 – 2.1 |

Map: 778 boxes, 0 degenerate, 0 coplanar faces, 12 of 12 spawns usable and
mutually reachable, cover spread across 16 m cells down from 69× to 5.3×.

**Performance is a cap, not a measurement.** `make bench` has returned exactly
120.0 fps and exactly 60.0 fps on the same build, and returns the same figure
with 0 bots or 7, at 640×360 or 1600×900, with the physics tick at 60/120/240.
vsync is genuinely off. Push past it with resolution for the real curve:
**63.4 fps at 2560×1440, 45.7 at 4K.**

---

## Deliberate departures from the bar

- **Bots were detuned on request** after play testing: incoming hits/sec 1.79 →
  0.43 on the same seed, jumps/sec 10.29 → 5.21. Aim error 3.2° → 8.0° with a
  settle floor so tracking never becomes a laser.
- **Movement envelope scaled down about a third** after play testing said
  crossing the 64 m arena in 2.5 s was frantic rather than fast. Ratios kept.
- **Single-block steps are walkable.** `CharacterBody3D` has no step-up, so
  every 1 m riser stopped you dead until `Motor._step_up()`.
- **Classes at spawn.** Four loadouts, each a primary plus the pistol.

---

## How to run

```sh
make run        # play from source
make release    # export a real universal binary and run it
make check      # parse every script, fail loudly
make bench      # frame timings as JSON
make movetest   # movement envelope
make bottest    # bot behaviour
make hittest    # shots-to-kill vs the sourced table
make classtest  # 13 checks over the class-select state machine
tools/round.sh <name>      # full evidence round into shots/<name>
tools/botsweep.sh <dir>    # five-seed bot aggregate
```
