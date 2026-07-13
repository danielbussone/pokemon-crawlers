class_name ThemePalette
## Cosmetic terrain materials (Phase 7). Resolves a stage `theme` + a grid char to
## a material name, and materials to render specs (albedo color, barrier height).
## Purely cosmetic — walkability is decided by the grid, not by material. See
## docs/TERRAIN_PALETTE.md.

## theme -> default materials for the generic chars: `.`=ground, `#`=barrier, `_`=floor.
const THEMES := {
	"open_field":    { "ground": "grass",       "barrier": "mountain",        "floor": "tile" },
	"forest_maze":   { "ground": "grass",       "barrier": "tree",            "floor": "tile" },
	"cave_branches": { "ground": "rock_floor",  "barrier": "boulder",         "floor": "rock_floor" },
	"town_pocket":   { "ground": "pavement",    "barrier": "building_small",  "floor": "tile" },
	"big_city":      { "ground": "pavement",    "barrier": "building_large",  "floor": "tile" },
	"ship_interior": { "ground": "wood",        "barrier": "wall_metal",      "floor": "wood" },
	"corporate":     { "ground": "metal_floor", "barrier": "wall_metal",      "floor": "metal_floor" },
	"mansion":       { "ground": "wood",        "barrier": "wall_interior",   "floor": "wood" },
	"volcanic":      { "ground": "ash",         "barrier": "boulder",         "floor": "ash" },
	"bridge":        { "ground": "planks",      "barrier": "railing",         "floor": "planks" },
	"gym_arena":     { "ground": "marble",      "barrier": "pillar",          "floor": "marble" },
	"plateau":       { "ground": "marble",      "barrier": "pillar",          "floor": "marble" },
}

## Override chars: force a specific material regardless of theme.
const CHAR_MATERIAL := {
	";": "tall_grass", ",": "dirt", "=": "road", ":": "sand",
	"T": "tree", "H": "hedge", "+": "railing", "^": "mountain",
	"O": "boulder", "B": "building_large", "b": "building_small",
	"~": "water", "*": "lava", "I": "pillar",
}

## material -> render spec. `barrier` materials have a `height` (tile units).
const MATERIALS := {
	# ground (walkable) — flat tiles
	"grass":       { "color": Color(0.30, 0.55, 0.28) },
	"tall_grass":  { "color": Color(0.22, 0.46, 0.20) },
	"dirt":        { "color": Color(0.52, 0.42, 0.30) },
	"road":        { "color": Color(0.55, 0.52, 0.47) },
	"pavement":    { "color": Color(0.48, 0.47, 0.45) },
	"sand":        { "color": Color(0.80, 0.72, 0.50) },
	"rock_floor":  { "color": Color(0.34, 0.32, 0.30) },
	"ash":         { "color": Color(0.20, 0.18, 0.18) },
	"planks":      { "color": Color(0.45, 0.33, 0.20) },
	"wood":        { "color": Color(0.42, 0.31, 0.19) },
	"metal_floor": { "color": Color(0.40, 0.42, 0.46) },
	"tile":        { "color": Color(0.70, 0.67, 0.58) },
	"marble":      { "color": Color(0.82, 0.80, 0.78) },
	# barriers — meshes at `height`
	"wall":           { "color": Color(0.17, 0.18, 0.21), "height": 1.0, "barrier": true },
	"wall_interior":  { "color": Color(0.55, 0.52, 0.50), "height": 1.0, "barrier": true },
	"wall_metal":     { "color": Color(0.42, 0.44, 0.48), "height": 1.0, "barrier": true },
	"tree":           { "color": Color(0.13, 0.34, 0.16), "height": 1.4, "barrier": true },
	"hedge":          { "color": Color(0.20, 0.42, 0.22), "height": 0.6, "barrier": true },
	"railing":        { "color": Color(0.52, 0.44, 0.32), "height": 0.5, "barrier": true },
	"mountain":       { "color": Color(0.40, 0.36, 0.32), "height": 1.4, "barrier": true },
	"boulder":        { "color": Color(0.38, 0.36, 0.34), "height": 0.9, "barrier": true },
	"building_large": { "color": Color(0.44, 0.32, 0.30), "height": 1.4, "barrier": true },
	"building_small": { "color": Color(0.52, 0.40, 0.34), "height": 1.2, "barrier": true },
	"water":          { "color": Color(0.20, 0.40, 0.70), "height": 0.15, "barrier": true },
	"lava":           { "color": Color(0.85, 0.35, 0.10), "height": 0.15, "barrier": true, "emissive": true },
	"pillar":         { "color": Color(0.70, 0.68, 0.64), "height": 1.6, "barrier": true },
}

const DEFAULT_GROUND := "grass"
const DEFAULT_BARRIER := "wall"


## Material for a grid char under a theme. Override chars win; else the theme's
## default for `#` (barrier), `_` (floor), or `.`/objects (ground).
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
