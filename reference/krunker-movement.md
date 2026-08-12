# Krunker.io Movement — Sourced Reference

All values are Krunker's *client display / wiki-documented* numbers. Krunker's internal world units are **not metres**. Working assumption for conversions (stated by community mapmakers, not an official spec): a standing player is **~2 units tall**, and a standard map grid block is **1 unit**. Where a source gives no raw unit value (most movement speed/physics numbers in Krunker are unitless multipliers applied to a hidden base constant), this is noted — conversion to metres is impossible without the client source, so it is marked UNKNOWN.

---

## 1. Base speed and per-class multipliers

Krunker's own class table publishes movement speed as a **unitless multiplier** (base walk speed × multiplier). No raw base speed (units/sec) is published anywhere in the wiki, docs, or changelogs.

| Class | Movement Speed Multiplier | Health | Wall-jump/grind | Source |
|---|---|---|---|---|
| Triggerman | 1.05 | 100 | None | https://krunkerio.fandom.com/wiki/Krunker.io_Wiki (class data table) |
| Hunter | 1.0 | 60 | None | same |
| Run N Gun | 1.18 | 100 | 2 consecutively | same |
| Spray N Pray | 0.9 | 180 | None | same |
| Vince | 1.0 | 90 | None | same |
| Detective | 1.0 | 100 | None | same |
| Marksman | 1.0 | 90 | None | same |
| Rocketeer | 0.86 | 130 | None | same |
| Agent (Akimbo Uzi) | 1.2 | 110 | 3 consecutively | same |
| Runner | 1.0 | 120 | Unlimited | same |
| Deagler (customs only) | 1.0 | 60 | None | same |
| Bowman (Crossbow) | 1.0 | 100 | None | same |
| Commando (FAMAS) | 1.0 | 100 | None | same |
| Trooper (Blaster) | 1.0 | 100 | 3 consecutively | same |
| Infiltrator (Charge Rifle) | 1.0 | 90 | None | same |
| Survivor (Build Tool, customs) | 0.8 | 150 | None | same |

Note: "Crossbow" and "Akimbo Uzi" from the assignment brief are weapons, not separate classes — they map to **Bowman** and **Agent** respectively above; there is no standalone "Crossbow" or "Akimbo Uzi" class.

Sprinting is not a separate mechanic in Krunker — holding two movement keys diagonally ("strafing", e.g. W+A) is Krunker's substitute for sprint and moves faster than a single direction key: Custom Games exposes this as **Strafe Speed**, default **1.2×**, adjustable 1.0–2.0 in custom-game physics settings.
Source: https://krunkerio.fandom.com/wiki/Custom_Games (Physics → Strafe Speed)

Per-weapon "Move Speed" is also independently editable in custom games, slider range **0.5–3.0** (multiplier), meaning class speed and weapon speed stack.
Source: https://krunkerio.fandom.com/wiki/Custom_Games (Weapon Configuration → Move Speed)

| Topic | Value | Source |
|---|---|---|
| Base walk speed (raw units/sec) | UNKNOWN — never published; only relative multipliers exist | — |
| Strafe/"sprint" multiplier (default) | 1.2× (custom-game slider, range 1.0–2.0) | https://krunkerio.fandom.com/wiki/Custom_Games |
| Per-weapon move-speed multiplier range | 0.5–3.0 (custom games) | https://krunkerio.fandom.com/wiki/Custom_Games |

---

## 2. Jump, gravity, terminal velocity

| Topic | Value | Unit / notes | Source |
|---|---|---|---|
| Jump height/velocity (raw) | UNKNOWN — no raw number published | Krunker exposes only a "Jump Force" multiplier | — |
| Jump Force multiplier (default) | 1.0 (range 0.1–3.0 in custom games) | Overlaps with gravity setting; low values e.g. let Spray N Pray clear obstacles it normally can't | https://krunkerio.fandom.com/wiki/Custom_Games (Physics → Jump Force) |
| Gravity multiplier (default) | 1.0 (range 0–2.0 in custom games) | Default gravity is described by the wiki itself as "already much lower than realistic"; 0.1–0.2 produces 10+ "meter" hangtime jumps | https://krunkerio.fandom.com/wiki/Custom_Games (Physics → Gravity) |
| Terminal velocity | UNKNOWN — not documented anywhere found | — | — |
| Consecutive bhop momentum gain | Confirmed qualitative effect ("builds you up a lot of momentum"); no formula published | — | https://krunkerio.fandom.com/wiki/Moveset (raw wikitext, Keybinds section) |

---

## 3. Slide mechanics

| Topic | Value | Source |
|---|---|---|
| Trigger condition | Press crouch (default Shift) right as you land from a jump (or while moving fast on ground) | https://krunkerio.fandom.com/wiki/Moveset |
| Introduced | Update 1.1.0 (Mar 11, 2019) | https://krunkerio.fandom.com/wiki/Moveset |
| Slide speed vs. normal movement | Explicitly stated to be "faster than any other movement type in the game" (no numeric multiplier published) | https://krunkerio.fandom.com/wiki/Moveset |
| Slide duration | "Lasts for about a second" (wiki prose); custom-game "Slide Time" slider goes 1–5 (relative units, 5 = longest/best slidehops) | https://krunkerio.fandom.com/wiki/Moveset ; https://krunkerio.fandom.com/wiki/Custom_Games (Physics → Slide Time) |
| Slide cooldown | UNKNOWN — not documented; slidehop chaining implies no hard cooldown, only friction ramp-up after ~0.25s | https://www.gamepur.com/guides/how-to-slide-hop-in-krunker |
| Can slide backward | Added in v2.8.1, then removed in v2.8.4 — as of current game, sliding backward is disabled | https://krunkerio.fandom.com/wiki/Slidehopping (Trivia) |
| Preserves/converts speed | Yes — slide is described as converting jump momentum into ground speed, and can be re-launched into another jump before friction fully kicks in | https://krunkerio.fandom.com/wiki/Slidehopping |
| Can turn while sliding | Yes, explicitly supported and used to slide around corners | https://krunkerio.fandom.com/wiki/Moveset |

---

## 4. Slide-hopping / bunny-hopping

| Topic | Value | Source |
|---|---|---|
| Core loop | jump → slide (crouch) just before landing → jump again before slide friction fully kicks in → repeat | https://krunkerio.fandom.com/wiki/Slidehopping ; https://www.gamepur.com/guides/how-to-slide-hop-in-krunker |
| Window to re-jump out of a slide | "~a quarter of a second" after landing | https://www.gamepur.com/guides/how-to-slide-hop-in-krunker |
| Speed accumulation | Each successful slide-hop chain combines jump speed + slide speed, compounding across repetitions (no published cap value) | https://www.gamepur.com/guides/how-to-slide-hop-in-krunker |
| Speed cap | UNKNOWN — no explicit max-speed constant published; practical cap is set by player execution/frame timing, not a stated engine constant | — |
| FPS dependency | Originally FPS-dependent (higher FPS = faster slide-hops); made FPS-independent in update 2.8.4 | https://krunkerio.fandom.com/wiki/Slidehopping |
| "Slide Control" client setting | Low-FPS players can raise a personal "Slide Control" setting to partially compensate; benefit shrinks as framerate rises | https://krunkerio.fandom.com/wiki/Slidehopping |
| Strafe slide-hopping | Variant taking a ~90° turn mid-slide-hop, used to juke shots | https://krunkerio.fandom.com/wiki/Slidehopping |
| Plain bhop (no slide) | Confirmed distinct/valid tech: "Consecutively jumping (bhopping) builds you up a lot of momentum" | https://krunkerio.fandom.com/wiki/Moveset |

---

## 5. Air control / air acceleration / strafe-jump speed gain

| Topic | Value | Source |
|---|---|---|
| Air strafing exists as a named movement mode | "Air Strafe" is explicitly listed as one of Krunker's movement types | https://krunkerio.fandom.com/wiki/Moveset (raw wikitext, movement list) |
| Does strafe-jumping add speed | Implied yes — bhop/strafe chaining is the primary way competitive players cross maps fast; treated as equivalent in effect to CPMA-style air strafing (the wiki even lists "Sakura Race Mode (CPMA)" as a related mode) | https://krunkerio.fandom.com/wiki/Moveset |
| Numeric air-accel constant | UNKNOWN — not published | — |
| Diagonal-key movement bonus | Holding two movement keys (WA/WD) enables "strafing," Krunker's faster diagonal-movement mode, at 1.2× default per Custom Games Strafe Speed setting | https://krunkerio.fandom.com/wiki/Moveset ; https://krunkerio.fandom.com/wiki/Custom_Games |

---

## 6. Wall jump / wall grind

| Topic | Value | Source |
|---|---|---|
| Classes with wall-jump/grind | Runner (unlimited), Agent (3 consecutive, buffed from 2 in v4.1.1), Trooper (3 consecutive), Run N Gun (2 consecutive, added v2.5.6, capped to 2 in v3.8.5) | https://krunkerio.fandom.com/wiki/Krunker.io_Wiki (class table); https://krunkerio.fandom.com/wiki/Agent ; https://krunkerio.fandom.com/wiki/Run_N_Gun |
| Trigger | Jump while touching/moving into a wall | https://krunkerio.fandom.com/wiki/Moveset |
| Consecutive-jump cap origin | v3.8.5 patch explicitly limited SMG (Run N Gun) and UZI (Agent) wall-jumps to 2 consecutive; Agent later raised to 3 in v4.1.1 | https://krunkerio.fandom.com/wiki/Run_N_Gun (Patch History) ; https://krunkerio.fandom.com/wiki/Agent (Patch History) |
| Wall-jump power tuning | Custom-game "Wall Jumping Power" slider exists (exact numeric range not stated by wiki text, but confirmed adjustable, off/low/high) | https://krunkerio.fandom.com/wiki/Custom_Games (Physics → Wall Jumping Power) |
| Wall-running (continuous, not discrete jumps) | Not a documented Krunker mechanic — "Wallgrind" is the closest analog: a rapid chain of wall-jumps along a surface, not a sustained run state | https://krunkerio.fandom.com/wiki/Moveset |

---

## 7. Crouch

| Topic | Value | Source |
|---|---|---|
| Trigger key | Shift (default, remappable) | https://krunkerio.fandom.com/wiki/Getting_Started |
| Movement speed while crouched | Reduced ("movement will be hindered") — no numeric percentage published anywhere found | https://krunkerio.fandom.com/wiki/Moveset ; https://krunkerio.fandom.com/wiki/Getting_Started |
| Jump height while crouched | Reduced ("jumps will be much shorter and lower") — no numeric value published | https://krunkerio.fandom.com/wiki/Moveset |
| Accuracy effect | Increases accuracy / "steadies your aim" | https://krunkerio.fandom.com/wiki/Getting_Started |
| Hitbox effect | Makes player a smaller target (explicitly stated); numeric height delta UNKNOWN | https://krunkerio.fandom.com/wiki/Moveset |
| Crouch height (raw units) | UNKNOWN | — |

---

## 8. FOV

| Topic | Value | Source |
|---|---|---|
| Default FOV | 70° (per "Getting Started" tutorial page) — a separate wiki citation for the Settings page states default of 90°, indicating this changed between versions or differs by cited snapshot | https://krunkerio.fandom.com/wiki/Getting_Started (raw: "The default FoV is 70 (degrees)") vs. https://krunkerio.fandom.com/wiki/Settings ("The default is 90, but it can be lowered down to 60 or raised up to 175") — conflicting sources, both cited verbatim; treat 70 as legacy/older-doc value and 90 as the current Settings-page value |
| FOV range | 60–175° | https://krunkerio.fandom.com/wiki/Settings |
| Recommended competitive FOV | 90° ("most common FoV for FPS," reasonable middle ground) | https://krunkerio.fandom.com/wiki/Getting_Started |
| FOV-on-sprint (strafe) behaviour | Not a distinct automatic FOV kick — Krunker has no separate "sprint FOV" setting; players instead choose a static higher FOV because "HIGH FOV is better for improving movement — increased perception of speed, see the ground more" | https://www.philzgoodman.com/krunkerio-guides/whats-the-best-fov-field-of-view-to-use-in-krunker |
| ADS FOV change | Yes — aiming down sights changes FOV/zoom; magnitude is player-configurable via "ADS Zoom Power" setting (exact default value not stated in any source found) | https://www.philzgoodman.com/krunkerio-guides/whats-the-best-fov-field-of-view-to-use-in-krunker |
| Weapon FOV (separate slider) | Independent FOV applied only to the held weapon model | https://krunkerio.fandom.com/wiki/Settings |

---

## 9. Mouse sensitivity model

| Topic | Value | Source |
|---|---|---|
| Model | Simple linear scalar slider ("Sensitivity") multiplying raw mouse delta; separate X/Y sensitivity sliders and separate Aim-X/Aim-Y (ADS) sensitivity sliders exist | https://krunkerio.fandom.com/wiki/Settings ; https://gamepretty.com/krunker-krunker-io-settings-guide/ |
| Default value | 1 | https://krunkerio.fandom.com/wiki/Settings |
| Range | 0.1–15 | https://krunkerio.fandom.com/wiki/Settings |
| Mouse acceleration | Present as an opt-in "Experimental" toggle, off by default ("increases speed/distance cursor travels in response to mouse speed") | https://krunkerio.fandom.com/wiki/Settings |
| Mouse-flick filtering | "Mouse Flick Fix" experimental toggle+slider filters erratic input | https://krunkerio.fandom.com/wiki/Settings |
| cm/360 conversion formula | UNKNOWN — no official formula published; mouse-sensitivity.com's Krunker page (which would likely have this) returned HTTP 403 and could not be read | https://www.mouse-sensitivity.com/forums/topic/4759-krunker/ (unreachable, cited for completeness) |

---

## 10. Player collision capsule

| Topic | Value | Source |
|---|---|---|
| Height (raw units) | Not numerically published; only qualitatively stated that the Map Editor's on-screen reference/bounding box "is as tall as the player," used by mappers as a sizing guide | https://www.fortnitequiz.com/krunker-map-editor-guide/ |
| Radius (raw units) | UNKNOWN — not published | — |
| Spawn point placement rule | "Ground level + one unit of height" (implies ~1 unit relates to player footprint clearance, not full height) | https://www.fortnitequiz.com/krunker-map-editor-guide/ |
| Hitbox scale (custom games) | Adjustable multiplier 0–1 via "Hitbox Scale" server setting (1 = normal, 0 = smallest) | https://krunkerio.fandom.com/wiki/Custom_Games (Game Logic → Hitbox Scale) |
| AI hitbox multipliers (KrunkScript) | `hitBotW` (width) and `hitBoxH` (height) multipliers exist for spawned AI bots, both examples default to 1 in docs | https://docs.krunker.io/guides/game-logic |
| Known hitbox quirk | Rotated map-editor models keep their pre-rotation (axis-aligned) hitbox, so visual and collision geometry can diverge | https://krunkerio.fandom.com/wiki/Map_Editor_Guide |
| Best-effort conversion | Given the "player ≈ 2 units tall" convention supplied in the task brief and no contradicting official number, treat capsule height ≈ 2 units, radius UNKNOWN — do not fabricate a number | — |

---

## 11. Tick rate / physics rate

| Topic | Value | Source |
|---|---|---|
| Server tick rate | "Confirmed... at least 30 tickrate" | https://www.philzgoodman.com/krunkerio-guides (Articles index) |
| "High Tickrate" client setting | Toggle that increases client→server packet send frequency to improve hit registration, at the cost of bandwidth (a network send-rate setting, not the server simulation rate itself) | https://krunkerio.fandom.com/wiki/Settings (Network → Network Rate (Hz)) |
| "Network Rate (Hz)" | Selectable option, exact Hz values not enumerated in the wiki text pulled | https://krunkerio.fandom.com/wiki/Settings |
| Physics/game-loop delta | KrunkScript exposes a `delta` (ms since last tick) to game logic, confirming a delta-time-based (not fixed-step) client update loop | https://docs.krunker.io/guides/game-logic |
| Client prediction | Exists by default and can be disabled via `GAME.DEFAULT.disablePrediction()`, confirming client-side movement prediction with server reconciliation (standard lag-comp architecture) | https://docs.krunker.io/guides/game-logic |
| Lag Compensation setting | Client-side toggle/slider that predicts past-state hit registration for laggy connections; devs recommend OFF on fast connections | https://krunkerio.fandom.com/wiki/Settings ; https://www.philzgoodman.com/krunkerio-guides/best-krunker-settings |

---

## Feel summary

- **Movement is the skill expression, not the gunplay.** Krunker explicitly brands slide-hopping as "the primary way skilled players move around maps," and multiple classes' viability hinges on mastering it (e.g. Run N Gun is unplayable at a beginner level without it). The skill ceiling lives almost entirely in chained jump→slide→jump timing, not aim mechanics.
- **No true sprint state — only diagonal "strafing."** There's no hold-to-run key; players get a speed boost only by holding two movement keys together (WA/WD), which is deliberately harder to control ("moving diagonally so it is harder to control"), tying speed to input complexity rather than a free toggle.
- **Everything stacks multiplicatively and is exposed as tunable multipliers, not absolute physics.** Class speed, weapon speed, strafe speed, jump force, and gravity are all separate unitless multipliers layered on a hidden base — this is a strong signal Krunker's engine itself is built around a small set of tunable scalars rather than a from-first-principles physics sim, which is very replicable in a Godot CharacterBody3D.
- **Slide/bhop chaining is intentionally low-friction and momentum-preserving, with a forgiving ~0.25s re-jump window** — this is closer to Quake/CPMA-style bunny-hopping (the wiki itself calls a related mode "Sakura Race Mode (CPMA)") than to a strict Source-engine bhop, and it was deliberately decoupled from framerate in v2.8.4 to keep it fair, showing the devs treat movement skill as a first-class balance concern.
- **Class identity is expressed through mobility, not just weapons.** Wall-jump access (Runner/Agent/Trooper/Run N Gun only) and speed multipliers (0.86× Rocketeer to 1.2× Agent) are core class-defining stats alongside health and gun — meaning "which gun do I get" and "how do I move" are the same design decision, not orthogonal systems.
