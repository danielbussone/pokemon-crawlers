# Terrain Palette — Environment Art (Phase 7)

Design spec for cosmetic terrain rendering across the 9-level Kanto arc. Drives
`world_builder` rendering and a future editor palette.

Last updated: 2026-07-12

---

## Scope (locked)

- **Cosmetic only.** A material changes how a cell *looks* (color / mesh / height /
  props). It does **not** change walkability or gameplay. Walkability stays binary:
  **ground = walkable**, **barrier = blocks**. Material is a skin on top.
- **Functional tiles are deferred** (see the end): surfable water, lava damage,
  ledges (one-way), warps/stairs, ice/spinners. We render some of them as plain
  cosmetic barriers now (deep water, lava) and add the gameplay later.

## Encoding model (layered — how cells get their material)

Painting every cell's material by hand doesn't scale. Instead, three layers:

1. **Object/walkability grid** (exists): `.` ground · `#` barrier · objects
   `S X c m w L D` (+ reserved `r t`). This is the source of truth for walk/block.
2. **`theme` per stage sets the default material palette** — a forest theme makes
   `.`→grass and `#`→tree; a cave theme makes `.`→rock-floor and `#`→boulder; etc.
   **This alone gets ~80% of the look with zero extra authoring.**
3. **Override chars** re-skin individual cells for within-stage variety (a paved
   road through a grassy route, a pond, a lamppost). Small, curated set (below).
4. *(Future)* optional **per-cell terrain layer** (parallel grid) for full control,
   painted in the map editor — only when a stage needs bespoke detail.

---

## Themes → default palette

Extends the existing `template` field. `open_field / forest_maze / cave_branches /
town_pocket / gym_arena` exist; the rest are new.

| Theme | Default ground | Default barrier | Accents / props | Stages |
|-------|----------------|-----------------|-----------------|--------|
| `open_field` | grass | mountain | dirt path, tree, fence | route_viridian, route_vermilion, route6_7, cycling_road, silence_bridge, sea_route, route22, viridian_front |
| `forest_maze` | grass | tree (dense) | tall grass | viridian_forest |
| `cave_branches` | rock floor | boulder | gravel, dark fog | ss_anne*, silph*, mansion*, victory_road |
| `town_pocket` | pavement + grass | small building | hedge, fence, sign | pewter, cerulean, vermilion, fuchsia |
| `big_city` *(new)* | pavement | large building | hedge, sign | celadon, saffron, viridian |
| `ship_interior` *(new)* | wood / metal | metal wall | railing, crates | ss_anne |
| `corporate` *(new)* | tile / metal | metal + glass wall | pillar, counter | game_corner, silph_lower, silph_upper |
| `mansion` *(new)* | wood | wall + furniture | statue, rubble | mansion |
| `volcanic` *(new)* | ash / stone | rock + lava(cosmetic) | red fog | cinnabar |
| `bridge` *(new)* | planks / metal walk | railing + water(cosmetic) | — | silence_bridge, cycling_road |
| `gym_arena` | themed by gym type | pillar + wall | statue | (gym rooms) |
| `plateau` *(new)* | marble | pillar + wall | statue, banner | e4_lorelei … e4_champion |

*(interior stages currently sit under `cave_branches`; retheme them when the new
themes land.)*

---

## Material catalog (render spec)

Colors are starting points (linear-ish RGB); tune in engine. Barrier "height" is
relative tile units (floor = 0).

### Ground (walkable) — flat tiles

| Material | Char | Color | Notes |
|----------|------|-------|-------|
| grass (short) | `.`† | `0.30,0.55,0.28` | outdoor default |
| tall grass | `;` | `0.24,0.48,0.22` | taller tufts; encounter flavor |
| dirt / path | `,` | `0.52,0.42,0.30` | |
| road (paved) | `=` | `0.55,0.52,0.47` | slab seams |
| sand | `:` | `0.80,0.72,0.50` | |
| rock floor | `.`† (cave theme) | `0.34,0.32,0.30` | |
| gravel | — (theme) | `0.42,0.40,0.38` | speckled |
| ash / scorched | — (volcanic) | `0.22,0.20,0.20` | faint embers |
| planks (wood) | `_`† (ship/bridge) | `0.45,0.33,0.20` | board lines |
| metal walk | `_`† (corporate) | `0.40,0.42,0.46` | grated |
| tile | `_`† (interior default) | `0.72,0.68,0.55` | checker |
| carpet | — (theme) | `0.45,0.15,0.18` | patterned |
| marble | `_`† (plateau) | `0.82,0.80,0.78` | veined |

† `.` and `_` are theme-skinned: `.` = the theme's outdoor ground, `_` = the
theme's interior/gym floor. Distinct chars (`;` `,` `=` `:`) force a specific look.

### Barrier (blocks) — meshes

| Material | Char | Color | Height | Mesh/prop |
|----------|------|-------|--------|-----------|
| wall (generic) | `#`† | theme | 1.0 | block, theme skin |
| tree | `T` | `0.12,0.34,0.16` | 1.4 | trunk + tapered canopy |
| hedge / bush | `H` | `0.20,0.42,0.22` | 0.6 | low rounded |
| fence / railing | `+` | `0.5,0.42,0.3` | 0.5 | thin posts + rail |
| mountain / cliff | `^` | `0.40,0.36,0.32` | 1.8 | tall angular |
| boulder / rock | `O` | `0.38,0.36,0.34` | 0.9 | rounded |
| building (large) | `B` | `0.42,0.30,0.28` | 2.2 | facade + windows |
| building (small) | `b` | `0.5,0.38,0.32` | 1.4 | house + roof |
| water (deep) | `~` | `0.20,0.40,0.70` | 0.15 | flat blue, ripple (cosmetic barrier) |
| lava | `*` | `0.85,0.35,0.10` | 0.15 | glowing, emissive (cosmetic barrier) |
| pillar / column | `I` | `0.70,0.68,0.64` | 2.0 | column |
| glass / window | — (theme) | `0.6,0.75,0.85,α` | 1.0 | translucent |
| counter / desk | — (theme) | `0.5,0.4,0.3` | 0.7 | waist-high |
| statue | — (theme) | `0.6,0.6,0.62` | 1.3 | figure |
| sign / post | — (theme) | — | 0.8 | flavor |

†`#` is theme-skinned to the default barrier (tree in forest, boulder in cave,
building in city, metal wall in corporate…).

### Override char set (final)

Ground: `.` theme-ground · `_` theme-floor · `;` tall grass · `,` dirt · `=` road · `:` sand
Barrier: `#` theme-barrier · `T` tree · `H` hedge · `+` fence · `^` mountain · `O` boulder · `B` big building · `b` small building · `~` water · `*` lava · `I` pillar

(Avoids the object chars `S X c m w L D r t`. Everything else comes from the theme.)

---

## Rendering approach (`world_builder`)

- **Ground:** floor tile mesh per cell; set albedo from the material color; mostly
  flat, small height jitter for gravel/ash; scroll/emissive for water/lava.
- **Barrier:** either a **block** at the material's height (walls, buildings) or a
  **prop mesh** (tree = trunk+canopy, mountain = angular, fence = posts, pillar =
  column, boulder = rounded). Keep the current procedural-mesh style; branch on
  material.
- **Per-zone atmosphere:** tint fog/ambient by theme (cave = dark, volcanic = red,
  forest = green-tinted, plateau = cool/grand). Reuse the existing gym-lighting hook.
- A `theme_palette(theme) -> {ground_material, barrier_material, floor_material,
  fog_tint, props}` table centralizes this; `stage_layout` exposes each cell's
  resolved material (char override → else theme default).

---

## Deferred — functional tiles (later gameplay phase)

Rendered as plain cosmetic barriers/ground for now; gameplay added later:

- **Surfable water** — walkable via Surf (currently deep water = cosmetic barrier).
- **Lava damage** — HP tick when standing on it (currently cosmetic barrier).
- **Ledges** — one-way drop (the signature Pokémon tile).
- **Warps / stairs** — multi-floor interiors (Silph, Mansion, caves).
- **Ice / spinner tiles** — forced sliding (Silph teleport panels, ice puzzles).

---

## Implementation sketch (next)

1. `theme_palette.gd` (or a table in `stage_layout`): theme → default materials + fog.
2. `stage_layout.parsed`: resolve a **material** per cell (override char → theme
   default), alongside walkability.
3. `world_builder`: render ground/barrier meshes by material (color + height + prop);
   apply per-theme fog/ambient.
4. Retheme stages to the new themes (table above); add override chars where a stage
   wants specifics (roads, ponds, park trees).
5. Editor: extend the palette to the full material set (paints override chars).
