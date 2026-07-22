class_name ThemePalette
## Terrain materials (Phase 7 / material-primary). A material is the source of truth
## for a cell: its `category` decides walkability and roof, and its color/height/shape
## decide appearance.
##   exterior — walkable, open sky (grass, dirt, road, sand, surf, …)
##   interior — walkable, roofed  (the floor_* materials)
##   barrier  — blocks, rendered as a prop (walls, buildings, trees, fences, hazards)
## A cell is roofed iff its material is `interior`. See docs/TERRAIN_PALETTE.md.

## theme -> default materials for the legacy generic glyphs `.`=ground, `#`=barrier,
## `_`=floor. Only consulted on the legacy read path + the one-time bake migration;
## material-primary cells carry an explicit material.
const THEMES := {
	"open_field":    { "ground": "grass",       "barrier": "mountain",        "floor": "tile" },
	"forest_maze":   { "ground": "grass",       "barrier": "tree",            "floor": "tile" },
	"cave_branches": { "ground": "rock_floor",  "barrier": "boulder",         "floor": "rock_floor" },
	"town_pocket":   { "ground": "pavement",    "barrier": "building_wood",   "floor": "tile" },
	"big_city":      { "ground": "pavement",    "barrier": "building_brick",  "floor": "tile" },
	"ship_interior": { "ground": "wood",        "barrier": "wall_metal",      "floor": "wood" },
	"corporate":     { "ground": "metal_floor", "barrier": "wall_metal",      "floor": "metal_floor" },
	"mansion":       { "ground": "wood",        "barrier": "wall_interior",   "floor": "wood" },
	"volcanic":      { "ground": "ash",         "barrier": "boulder",         "floor": "ash" },
	"bridge":        { "ground": "planks",      "barrier": "railing",         "floor": "planks" },
	"gym_arena":     { "ground": "marble",      "barrier": "pillar",          "floor": "marble" },
	"plateau":       { "ground": "marble",      "barrier": "pillar",          "floor": "marble" },
}

## Legacy glyph -> material (the pre-material-primary override chars). `~` = deep
## (non-surfable) water; `s` = surf water. Read path + bake migration only.
const CHAR_MATERIAL := {
	";": "tall_grass", ",": "dirt", "=": "road", ":": "sand",
	"T": "tree", "H": "hedge", "+": "railing", "^": "mountain",
	"O": "boulder", "B": "building_brick", "b": "building_wood",
	"~": "water", "s": "water_surf", "*": "lava", "I": "pillar",
}

## material -> render spec. `category` drives walk/roof; `barrier` materials have a
## `height` (tile units) and are rendered as props; some are `emissive`/have a `shape`.
const MATERIALS := {
	# exterior ground (walkable, open sky)
	"grass":       { "color": Color(0.30, 0.55, 0.28), "category": "exterior" },
	"tall_grass":  { "color": Color(0.22, 0.46, 0.20), "category": "exterior" },
	"dirt":        { "color": Color(0.52, 0.42, 0.30), "category": "exterior" },
	"road":        { "color": Color(0.55, 0.52, 0.47), "category": "exterior" },
	"pavement":    { "color": Color(0.48, 0.47, 0.45), "category": "exterior" },
	"sand":        { "color": Color(0.80, 0.72, 0.50), "category": "exterior" },
	"rock_floor":  { "color": Color(0.34, 0.32, 0.30), "category": "exterior" },
	"ash":         { "color": Color(0.20, 0.18, 0.18), "category": "exterior" },
	"planks":      { "color": Color(0.45, 0.33, 0.20), "category": "exterior" },
	"dock":        { "color": Color(0.48, 0.35, 0.22), "category": "exterior" },
	# surf water is walkable ground (no barrier flag), a brighter blue than deep water
	"water_surf":  { "color": Color(0.30, 0.55, 0.80), "category": "exterior" },
	# interior floors (walkable, roofed) — inherently indoor surfaces
	"tile":        { "color": Color(0.70, 0.67, 0.58), "category": "interior" },
	"marble":      { "color": Color(0.82, 0.80, 0.78), "category": "interior" },
	"metal_floor": { "color": Color(0.40, 0.42, 0.46), "category": "interior" },
	"wood":        { "color": Color(0.42, 0.31, 0.19), "category": "interior" },
	"floor_cave":  { "color": Color(0.32, 0.30, 0.29), "category": "interior" },
	# barriers — meshes at `height`
	"wall":           { "color": Color(0.17, 0.18, 0.21), "height": 1.0, "barrier": true, "category": "barrier" },
	"wall_interior":  { "color": Color(0.55, 0.52, 0.50), "height": 1.0, "barrier": true, "category": "barrier" },
	"wall_metal":     { "color": Color(0.42, 0.44, 0.48), "height": 1.0, "barrier": true, "category": "barrier" },
	"tree":           { "color": Color(0.13, 0.34, 0.16), "height": 1.4, "barrier": true, "category": "barrier" },
	"hedge":          { "color": Color(0.20, 0.42, 0.22), "height": 0.6, "barrier": true, "category": "barrier" },
	"railing":        { "color": Color(0.52, 0.44, 0.32), "height": 0.5, "barrier": true, "category": "barrier" },
	"mountain":       { "color": Color(0.40, 0.36, 0.32), "height": 1.4, "barrier": true, "category": "barrier" },
	"boulder":        { "color": Color(0.38, 0.36, 0.34), "height": 0.9, "barrier": true, "category": "barrier" },
	"water":          { "color": Color(0.20, 0.40, 0.70), "height": 0.15, "barrier": true, "category": "barrier" },
	"lava":           { "color": Color(0.85, 0.35, 0.10), "height": 0.15, "barrier": true, "category": "barrier", "emissive": true },
	"pillar":         { "color": Color(0.70, 0.68, 0.64), "height": 1.6, "barrier": true, "category": "barrier", "shape": "pillar" },
	# buildings — solid facades in their own category (blocks, no ceiling). Height comes
	# from per-cell storeys; `floors` is the storey count the editor's spinbox starts at.
	"building_wood":      { "color": Color(0.52, 0.38, 0.24), "category": "building", "floors": 1 },
	"building_brick":     { "color": Color(0.55, 0.34, 0.30), "category": "building", "floors": 3 },
	"building_glass":     { "color": Color(0.40, 0.52, 0.62), "category": "building", "floors": 4 },
	"building_concrete":  { "color": Color(0.56, 0.56, 0.55), "category": "building", "floors": 2 },
	"building_gym":       { "color": Color(0.60, 0.44, 0.34), "category": "building", "floors": 1 },
	"building_stone":     { "color": Color(0.50, 0.47, 0.43), "category": "building", "floors": 2 },
	"building_sandstone": { "color": Color(0.76, 0.66, 0.46), "category": "building", "floors": 2 },
}

## material -> 1-char terrain code for the compact `cells` serialization. Distinct
## from object markers (S X c m w t L D), which live in a cell's own `o` field.
const MATERIAL_CODE := {
	"grass": ".", "tall_grass": ";", "dirt": ",", "road": "=", "sand": ":",
	"pavement": "p", "rock_floor": "r", "ash": "a", "planks": "k", "wood": "o",
	"dock": "d", "metal_floor": "f", "tile": "i", "marble": "e", "water_surf": "s",
	"floor_cave": "v",
	"wall": "#", "wall_interior": "n", "wall_metal": "z", "tree": "T", "hedge": "H",
	"railing": "+", "mountain": "^", "boulder": "O", "water": "~", "lava": "*", "pillar": "I",
	"building_wood": "b", "building_brick": "B", "building_glass": "G",
	"building_concrete": "C", "building_gym": "Y", "building_stone": "K",
	"building_sandstone": "N",
}

## Barrier prop shapes (Phase 7 slice 2). Materials without a `shape` render as a
## full-cell block. Others: tree (trunk+canopy), boulder (squat), pillar (column),
## flat (low pool — water/lava), post (low thin — fence/railing).
const SHAPES := {
	"tree": "tree", "boulder": "boulder", "hedge": "block",
	"railing": "post", "water": "flat", "lava": "flat", "pillar": "pillar",
}

const DEFAULT_GROUND := "grass"
const DEFAULT_BARRIER := "wall"

## Materials the map editor offers as a terrain brush, in palette order (exterior,
## then interior, then barrier). The editor groups them via `category_of`.
const PAINTABLE_MATERIALS := [
	# exterior
	"grass", "tall_grass", "dirt", "road", "sand", "pavement", "rock_floor",
	"ash", "planks", "dock", "water_surf",
	# interior (roofed)
	"tile", "marble", "metal_floor", "wood", "floor_cave",
	# building (blocks; storeys per cell)
	"building_wood", "building_brick", "building_glass", "building_concrete",
	"building_gym", "building_stone", "building_sandstone",
	# barrier
	"wall", "wall_interior", "wall_metal", "tree", "hedge", "railing", "mountain",
	"boulder", "water", "lava", "pillar",
]

## Editor tooltip per material: what it is + an example use case. The category
## (exterior/interior/barrier) is prepended by the editor from MATERIALS.
const MATERIAL_DESC := {
	"grass": "Short route grass. e.g. fields, town lawns, gym approaches.",
	"tall_grass": "Taller grass tufts. e.g. wild-encounter patches on routes.",
	"dirt": "Packed earth path. e.g. trodden trails, cave-mouth approaches.",
	"road": "Sandy route path. e.g. the main walking path across a route.",
	"pavement": "Town paving. e.g. city streets and plazas.",
	"sand": "Beachy sand. e.g. Cinnabar shore, coastal routes.",
	"rock_floor": "Open rocky ground (no roof). e.g. unroofed canyons, quarry floors.",
	"ash": "Volcanic scorched ground. e.g. Cinnabar's volcanic fields.",
	"planks": "Outdoor wooden boardwalk. e.g. bridges, walkways.",
	"dock": "Weathered pier planks over water. e.g. harbour docks.",
	"water_surf": "Surfable water — walkable with Surf. e.g. sea routes you cross by water.",
	"tile": "Indoor tile floor (roofed). e.g. Pokémon Center / Mart interiors.",
	"marble": "Polished stone floor (roofed). e.g. gym arenas, the Indigo Plateau.",
	"metal_floor": "Industrial metal floor (roofed). e.g. Silph Co., Game Corner.",
	"wood": "Indoor wood floor (roofed). e.g. houses, mansion, S.S. Anne interior.",
	"floor_cave": "Roofed cave floor. e.g. Mt. Moon, Rock Tunnel, Victory Road.",
	"wall": "Generic solid wall — tiles seamlessly. e.g. building interiors, dividers.",
	"wall_interior": "Warm interior wall. e.g. house / mansion inner walls.",
	"wall_metal": "Riveted metal wall. e.g. ship hull, Silph corridors.",
	"tree": "Dense tree (blocks). e.g. route treelines, forest edges.",
	"hedge": "Low trimmed bush. e.g. town borders, garden edges.",
	"railing": "Low fence / rail. e.g. bridge sides, ledges.",
	"mountain": "Cliff / rock wall — tiles solid. e.g. cave and canyon walls, route edges.",
	"boulder": "A single rounded rock (won't tile into a wall). e.g. a route obstacle, volcanic debris.",
	"building_wood": "Wood-facade building. Starts at 1 floor. e.g. houses, cabins, small shops.",
	"building_brick": "Brick building. Starts at 3 floors. e.g. apartments, city blocks.",
	"building_glass": "Glass-curtain building. Starts at 4 floors. e.g. offices, Silph-style towers.",
	"building_concrete": "Concrete building. Starts at 2 floors. e.g. plain blocks, warehouses.",
	"building_gym": "Gym facade. Starts at 1 floor. e.g. the exterior of a city gym.",
	"building_stone": "Stone building. Starts at 2 floors. e.g. old-town masonry, ruins.",
	"building_sandstone": "Sandstone building. Starts at 2 floors. e.g. desert / coastal towns.",
	"water": "Deep water — impassable. e.g. sea / lake borders, un-surfable depths.",
	"lava": "Molten lava — impassable, glowing. e.g. Cinnabar volcano hazards.",
	"pillar": "Standing column. e.g. gym / plateau pillars, ruins.",
}

static var _code_to_material := {}


## Material for a legacy glyph under a theme (read path + bake migration). Override
## glyph wins; else `#`->theme barrier, `_`->theme floor, else theme ground.
static func material_for(theme: String, ch: String) -> String:
	if CHAR_MATERIAL.has(ch):
		return CHAR_MATERIAL[ch]
	var t: Dictionary = THEMES.get(theme, THEMES["open_field"])
	match ch:
		"#": return String(t["barrier"])
		"_": return String(t["floor"])
		_:   return String(t["ground"])


static func color_of(material: String) -> Color:
	return MATERIALS.get(material, {}).get("color", Color(0.3, 0.3, 0.3))


static func height_of(material: String) -> float:
	return float(MATERIALS.get(material, {}).get("height", 1.0))


static func is_barrier(material: String) -> bool:
	return bool(MATERIALS.get(material, {}).get("barrier", false))


static func is_emissive(material: String) -> bool:
	return bool(MATERIALS.get(material, {}).get("emissive", false))


static func shape_of(material: String) -> String:
	return String(SHAPES.get(material, "block"))


## exterior | interior | barrier. Unknown materials default to exterior (walkable).
static func category_of(material: String) -> String:
	return String(MATERIALS.get(material, {}).get("category", "exterior"))


static func is_walkable_material(material: String) -> bool:
	var cat := category_of(material)
	return cat == "exterior" or cat == "interior"  # barrier and building both block


static func is_roofed_material(material: String) -> bool:
	return category_of(material) == "interior"


static func is_building_material(material: String) -> bool:
	return category_of(material) == "building"


## Storey count a building material starts at (editor spinbox default / render fallback).
static func floors_of(material: String) -> int:
	return int(MATERIALS.get(material, {}).get("floors", 1))


static func code_of_material(material: String) -> String:
	return String(MATERIAL_CODE.get(material, "."))


static func material_of_code(code: String) -> String:
	if _code_to_material.is_empty():
		for m in MATERIAL_CODE:
			_code_to_material[MATERIAL_CODE[m]] = m
	return String(_code_to_material.get(code, DEFAULT_GROUND))


static func theme_barrier(theme: String) -> String:
	return String(THEMES.get(theme, THEMES["open_field"])["barrier"])


static func theme_ground(theme: String) -> String:
	return String(THEMES.get(theme, THEMES["open_field"])["ground"])


static func theme_floor(theme: String) -> String:
	return String(THEMES.get(theme, THEMES["open_field"])["floor"])
