class_name WorldGrid
extends RefCounted
## Single source of truth for the first-person tile-grid layout.
## Player position is always a tile center; movement/turns are pure data
## operations the controller tweens visually. No physics involved.

const TILE_SIZE := 3.0
const WALL_HEIGHT := 3.0
const EYE_HEIGHT := 1.6

enum Facing { NORTH, EAST, SOUTH, WEST }
const FACING_DIR := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

enum TileKind {
	WALL,
	CORRIDOR,
	ENCOUNTER,
	OPTIONAL_ENCOUNTER,
	GATE_ENCOUNTER,
	ALCOVE,
	SHOP_DOOR,
	GYM_FLOOR,
	GYM_DOOR,
}

var tiles: Dictionary = {}          # Vector2i -> TileKind
var gate_encounter: Dictionary = {} # Vector2i -> int (encounter index that must be cleared)
var tile_meta: Dictionary = {}      # Vector2i -> Dictionary ({encounter_index} or {shop_window})
var zone_of: Dictionary = {}        # Vector2i -> String (zone id, for wall texture/name lookup)

var run_ref  # Run autoload, injected so is_walkable can check live clear state


static func world_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * TILE_SIZE, 0.0, cell.y * TILE_SIZE)


static func yaw_for_facing(facing: int) -> float:
	return -facing * PI / 2.0


func set_tile(cell: Vector2i, kind: TileKind, zone_id: String = "") -> void:
	tiles[cell] = kind
	if zone_id != "":
		zone_of[cell] = zone_id


func kind_at(cell: Vector2i) -> int:
	return tiles.get(cell, TileKind.WALL)


func is_walkable(cell: Vector2i) -> bool:
	if not tiles.has(cell):
		return false
	var kind: int = tiles[cell]
	if kind == TileKind.WALL:
		return false
	if gate_encounter.has(cell) and run_ref != null:
		var required_slot: int = gate_encounter[cell]
		if run_ref.encounter_index <= required_slot:
			return false
	return true


func neighbor(cell: Vector2i, facing: int) -> Vector2i:
	return cell + FACING_DIR[facing]
