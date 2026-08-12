# Krunker.io Visual Language Reference

## 1. Art Style
- Not true voxel — built from **resizable low-poly cuboids ('cubes')** in the map editor, not a voxel grid. "Cubes are the basic blocks of everything else... dimensions can be changed into flat planes, columns, walls" and "the best maps are made by resizing and repacking basic cubes... similar to LEGO or Minecraft." (https://krunkerio.fandom.com/wiki/Map_Editor_Guide, https://www.fortnitequiz.com/krunker-map-editor-guide/)
- Editor also ships pre-made low-poly props (crates, barrels, trees, vehicles, containers, doors) with simplified rectangular hitboxes that often don't match the visible mesh (documented bug/quirk). (https://krunkerio.fandom.com/wiki/Map_Editor_Guide)
- Texture resolution: UNKNOWN (not documented). Textures uploaded as **.jpg/.png**; upload size caps raised over time "for better-quality assets." (https://www.globaleconnections.com/blog/krunker-editor-the-ultimate-guide-to-creating-custom-maps) Visual read is flat/simplified colour with light noise, not hard pixel-art — `[INFERENCE]` from community screenshots.
- Settings expose a **"No Textures"** toggle (all textures removed) and a **"Green Screen"** debug toggle (all textures forced green) — confirms textures are discrete mapped assets, not vertex colour. (https://krunkerio.fandom.com/wiki/Settings)
- Style is inconsistent across eras: early 2018-19 community-made maps (CrispyCrust) are plainer/blockier; later v5.5+ "visual overhaul" passes (artist Jerm Hunter) added denser prop detail and stylised colour grading without changing block layouts. Reddit explicitly critiques this inconsistency. (https://www.reddit.com/r/KrunkerIO/comments/eeynws/krunkers_art_style_is_inconsistent_season_2_has/)

## 2. Colour Palette (per classic map)
Hex values are **best-effort approximations inferred from written map-theme descriptions**, not pixel-sampled — mark every hex `[INFERENCE]`; only the underlying theme text is directly sourced.

| Map | One-line palette | Approx. hex (inferred) | Source |
|---|---|---|---|
| Burg | Sandy tan/limestone walled village, warm stone+wood, torch tunnels, blue water channel | Stone `#C9B389`, wood `#8B5A2B`, water `#3E7C8C`, torch `#F2A542` | https://krunkerio.fandom.com/wiki/Burg |
| Sandstorm | Sandy desert town, tan/beige housing, tall apartments, palm-green accents | Sand `#D9C08C`, beige `#E4CFA4`, palm `#5C8A3A` | https://krunkerio.fandom.com/wiki/Sandstorm |
| Littletown | Suburban dead-end — one red house, one blue house, white shed/blue truck centerpiece | Red `#B03A2E`, blue `#2E5FB0`, white `#EDEDED` | https://krunkerio.fandom.com/wiki/Littletown |
| Undergrowth | Aztec ruin, tight close-quarters stone corridors | Stone `#8C7A5E`, moss `#5A6B3E` | https://krunkerio.fandom.com/wiki/Undergrowth |
| Kanji | Night-time neon futuristic Japanese megalopolis, two connected towers | Night sky `#0B1026`, neon pink `#FF2E9A`, neon cyan `#22D3EE`, building grey `#3A3F4B` | https://krunkerio.fandom.com/wiki/Kanji |
| Subzero | Snowy ski resort, pine trees, cable cars, stone church-like centre, distant mountains | Snow `#F2F5F7`, pine `#2F4F3A`, stone `#9AA0A6`, sky `#BFD9E8` | https://krunkerio.fandom.com/wiki/Subzero |
| Freight | Snowy harbor/warehouses, lighthouse, boat, industrial metal sheds | Warehouse rust `#8C4A3A`, snow `#F0F2F3`, metal `#6B6F73` | https://krunkerio.fandom.com/wiki/Freight |
| Shipment | Shipping port, stacked blue/rust containers, yellow crane, red explosive barrels | Container blue `#1F5FA8`, rust `#A34B2E`, crane yellow `#F2C230`, barrel red `#C0392B` | https://krunkerio.fandom.com/wiki/Shipment |

Cross-map constant props: blue container `#1F5FA8`, red container `#C0392B` (editor default models); wood crates `#8B5A2B`; traffic cones orange `#E2711D`. (https://krunkerio.fandom.com/wiki/Map_Editor_Guide)

## 3. Lighting Model
- **Baked** for static geometry — patch notes explicitly call out a "Rebake" operation ("Adjusted Lighting on Sandstorm a bit: Rebake", v3.2.8). (https://krunkerio.fandom.com/wiki/Sandstorm)
- Settings expose 4 discrete **Lighting** quality tiers plus a separate **Ambient Shading** toggle ("makes objects look more realistic... in reaction with light sources") layered atop the bake. (https://krunkerio.fandom.com/wiki/Settings)
- Shadows are optional/tiered: **Shadows** (on/off), **Soft Shadows**, **High-Res Shadows**, and **Dynamic Shadows** ("Renders shadows in real-time, especially player shadows") — implies static-geometry shadow is baked/cheap while player shadows are the real-time cost. (https://krunkerio.fandom.com/wiki/Settings)
- Directional sun: not explicitly named in sourced docs; night maps (Kanji) vs daylight snow maps (Subzero/Freight) plus emissive props (Burg torches, Kanji neon) imply one key light + local emissives per map — `[INFERENCE]`, mechanism unconfirmed.
- Fog: **UNKNOWN** — no source states fog colour/falloff/existence. Render Distance is a separate hard-cull slider, suggesting distant geometry is culled rather than fog-faded by default.
- Skybox: varies per map theme (daytime vs Kanji's explicit night sky); exact implementation (cubemap/gradient/skydome) **UNKNOWN**.

## 4. Outlines & Post-Processing
- No confirmed black cel-shading outlines on world geometry or characters in any sourced doc — **UNKNOWN/likely absent**; the "blocky" read comes from flat-shaded low-poly silhouettes, not ink outlines.
- Editor-only green wireframe hitbox outlines exist as a dev tool, not an in-game render feature. (https://krunkerio.fandom.com/wiki/Map_Editor_Guide)
- Post-processing pipeline confirmed via official client config keys `shaderRendering`, `postProcessing`, `bloom` (example: `postProcessing,true` / `bloom,false`). (https://docs.krunker.io/guides/resource-packs)
- Antialiasing is an explicit opt-in toggle ("Smooths out jagged lines at the cost of... reducing frames") — edges are jagged/aliased by default. (https://krunkerio.fandom.com/wiki/Settings)
- Vignette, Saturation, Color Hue, Depth Map (pseudo-DoF/B&W), Green Screen are cosmetic client sliders, neutral/off by default (Saturation 1.0, Hue 0, Vignette 0, Depth Map 0). (https://krunkerio.fandom.com/wiki/Settings)
- **Weapon Shine** toggle adds a specular/gloss pass specifically to weapon models, distinct from world shading. (https://krunkerio.fandom.com/wiki/Settings)

## 5. Scale
Editor unit-to-metre ratio is UNKNOWN; task convention (player ≈ 2 units tall, block = 1 unit) used qualitatively below — no source gives exact block counts.
- Building height: Littletown houses are explicitly "two-story" (https://krunkerio.fandom.com/wiki/Littletown). Kanji's twin towers reach megalopolis scale with bounce pads for vertical traversal (one of only two maps with bounce pads, the other Lostworld). (https://krunkerio.fandom.com/wiki/Kanji)
- Corridor widths/sightlines: Sandstorm is built around "a long corridor and large open spaces" (two long corridors + underground connector) and is explicitly the favourite for ranked/competitive long-sightline play. Undergrowth is the opposite — "short walls and tight halls," favoring Shotgun/Akimbo Uzi over long-range weapons. (https://krunkerio.fandom.com/wiki/Sandstorm, https://krunkerio.fandom.com/wiki/Undergrowth)
- Verticality: Atomic is explicitly called "one of the only dual layered maps in rotation," implying classic-era maps (Burg, Sandstorm, Littletown, Undergrowth, Subzero, Freight) are largely single-level with roof access/tunnels, not stacked multi-floor arenas. (https://krunkerio.fandom.com/wiki/Maps)
- Ramps vs stairs: Ramps are a first-class editor object that can carry a movement **boost** (adjustable) in the ramp direction, used for traversal/parkour (e.g. Subzero's parkour course). Stairs aren't called out as a separate primitive; multi-story buildings use interior stairs/ladders implicitly. (https://www.fortnitequiz.com/krunker-map-editor-guide/, https://krunkerio.fandom.com/wiki/Subzero)
- Cover props (Crate, Stack, Barrel, Acid Barrel, Cardboard, Pallet) are documented jump-on-able, roughly waist-to-shoulder height, used for micro-verticality/sightline breaks throughout maps. (https://krunkerio.fandom.com/wiki/Map_Editor_Guide)

## 6. Burg Layout (specific)
- Base template: explicitly a remake of **Counter-Strike's de_dust2** — dust2's Long/Mid/Tunnels/Catwalk topology maps directly onto Burg. (https://krunkerio.fandom.com/wiki/Burg)
- Setting: walled sand/stone village ("City of Ur"-style), water channel through the map, multiple torch-lit tunnels. (https://krunkerio.fandom.com/wiki/Burg)
- Named zones from patch history: **Mid** (raised in one patch specifically to enable more engagements from B Site — implying Mid is an elevated platform overlooking both sites), **Long** (a hole/opening was made higher here), an **underpass** connector, and containers placed at both Mid and Long for cover. (Burg patch history, v0.9.99997 / v1.1.0 entries)
- Sniper positions: Long is the named long-sightline lane (dust2 Long-A equivalent), corroborated by community trickshot/sniper-gameplay videos, though exact block coordinates aren't documented in text. (https://www.youtube.com/watch?v=Senzd7KVEhA — title only)
- Set-piece: non-playable execution diorama (police + guillotine + caged skeletons + explosive carts) at the former truck site — cosmetic, not accessible in rotation games. (https://krunkerio.fandom.com/wiki/Burg)
- Numeric block dimensions: **UNKNOWN** — no source gives block counts; only qualitative dust2-derived topology is sourced.

## 7. Viewmodel
- Position/scale fully configurable: **Weapon FOV** (separate from world FOV), **Weapon X/Y/Z Offset** (0-4, default 1 each), **Weapon ADS Y Offset** (0-2, default 1), **Weapon Rotation** (-2 to 2, default 0), **Weapon Leaning** (0-6, default 1 — the gun's tilt/cant angle). (https://krunkerio.fandom.com/wiki/Settings)
- Default posture `[INFERENCE]` from non-zero default sliders: gun sits lower-right of center, canted/leaning rather than dead-upright — this leaning-weapon silhouette is a Krunker signature, distinct from CoD/CS's centered-upright viewmodels.
- Bobbing: **Weapon Bobbing** slider (0-2, default 1) — present at moderate default, disableable at 0. (https://krunkerio.fandom.com/wiki/Settings)
- ADS: **Hide Weapon on ADS** is OFF by default — weapon stays visible while scoped (not a CS:GO-style hidden-arms scope). Separate ADS Y Offset implies the gun visibly repositions toward the crosshair on ADS. Scopes have an optional **Scope Border** (on by default) or fully custom image scope. (https://krunkerio.fandom.com/wiki/Settings)
- Sniper-specific flourish: a **Sniper Flap** on the rifle model bobs with player movement, purely cosmetic. Muzzle flash and bullet trails are on by default. (https://krunkerio.fandom.com/wiki/Settings)
- Default world FOV is 90 (range 60-175); high FOV explicitly distorts "character and weapon... out of proportion" (fish-eye), hence the separate weapon-FOV slider. (https://krunkerio.fandom.com/wiki/Settings)
- Exact viewmodel size/screen-percentage: **UNKNOWN**.

## 8. HUD
- **Crosshair**: type selectable (default/custom/layered/image/precision); default crosshair "does not keep a constant mark in the center" (dynamic/spread-reactive). Colour defaults **white**, freely recolourable (solid colours only, no gradients), plus a separate Shadow colour. (https://krunkerio.fandom.com/wiki/Settings)
- **Health**: shown via "Show UI" (on by default). **Dynamic HP Bar** (on by default) animates damage taken rather than snapping instantly; separate **HUD Health High** / **HUD Health Low** colour pickers imply a colour gradient as HP drops (exact stock colours UNKNOWN). (https://krunkerio.fandom.com/wiki/Settings)
- **Ammo counter**: bundled under the same "Show UI" toggle as health; exact screen position UNKNOWN (conventionally bottom-right — `[INFERENCE]`).
- **Killfeed**: "Show Kill Feed" toggle (on by default), shows "Player Killed Player" messages; in default UI, chat and killfeed are combined into one panel. (https://krunkerio.fandom.com/wiki/Settings; https://gamepretty.com/krunker-krunker-io-settings-guide/)
- **Scoreboard**: explicitly **top-right of screen**, with a legacy ("Use Old Scoreboard") style toggle. (https://gamepretty.com/krunker-krunker-io-settings-guide/)
- **Minimap**: "Show Minimap" toggle exists; described as having been "overhauled and integrated in-game" in a later update. Exact position/shape UNKNOWN from sourced text.
- **Hitmarker**: fully custom via a **Hitmarker Image** URL field (any image/GIF); default shape UNKNOWN precisely (`[INFERENCE]`: classic X/cross per genre convention — customizability itself is sourced).
- **Damage numbers**: "Show Damage" toggle shows numeric damage as a floating popup; separate **Damage Color** and **Crit Color** pickers (normal vs critical/headshot hits render differently), plus **Damage Scale** slider (0.1-2, default 1). The kill-reward "Popup Score" has its own separate Color/Shadow/Scale settings. (https://krunkerio.fandom.com/wiki/Settings)
- **Optional add-ons**: movement speed (renders **below the crosshair** when enabled — explicit position), medals, ping (on by default), FPS, death counter — all togglable. (https://krunkerio.fandom.com/wiki/Settings)
- **UI Scale**: one global slider (0.1-1) resizes all HUD elements together, confirming a single scalable UI layer. (https://krunkerio.fandom.com/wiki/Settings)

## If you build one thing right
1. **Boxy, resizable-cube level geometry with flat-shaded low-poly cover props** (crates, containers, barrels) — the strongest single genre signal, inherited directly from the editor's "everything is a resizable cube, repack like LEGO" philosophy. (https://krunkerio.fandom.com/wiki/Map_Editor_Guide)
2. **The canted, off-center, bobbing viewmodel that stays visible through ADS by default** — asymmetric weapon posture plus visible bob, no clean scope-only view, is instantly distinct from AAA-shooter viewmodel conventions. (https://krunkerio.fandom.com/wiki/Settings)
3. **The dust2-derived Burg layout silhouette** — walled sand/stone village, water channel, torch-lit tunnels, Long/Mid/Tunnels topology inherited wholesale from Counter-Strike's de_dust2; Burg is explicitly "synonymous with Krunker." (https://krunkerio.fandom.com/wiki/Burg)
</content>
<parameter name="i">Persist krunker-look reference verbatim