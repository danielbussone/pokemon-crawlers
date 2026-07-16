class_name WorldMapBuilder
extends Node3D
## Builds walkable open-area / maze stages from stage_layouts.json. Each stage is
## stamped at its author-placed `world_pos` (map editor's World View) in a shared
## grid; stages connect wherever the author makes their walkable cells meet.

const StageLayout = preload("res://scripts/world/stage_layout.gd")
const WG = preload("res://scripts/world/world_grid.gd")

## Tiny 5x7 block font, just the glyphs shop signage needs ("P.C" / "MART").
const _SIGN_GLYPHS := {
	"P": ["01110", "01001", "01001", "01110", "01000", "01000", "01000"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	".": ["00000", "00000", "00000", "00000", "00000", "00000", "00100"],
}

signal encounter_triggered(marker: EncounterMarker)
signal shop_entered(window: int, kind: String)

var grid
var markers: Array[EncounterMarker] = []
var spawn_cell := Vector2i.ZERO

var _encounter_cells: Array[Vector2i] = []
var _zone_sign_cells: Dictionary = {}   # zone_id -> Vector2i (world cell for signage)
var _gym_cell_stage: Dictionary = {}    # gym-zone world cell -> owning stage id (for naming)
var _forest_bounds: Array = []          # [{origin, size}] of forest stages, for backdrops
var _ship_bounds: Array = []            # [{origin, size}] of ship stages, for lamps + portholes
var _boss_cell := Vector2i.ZERO
var _wall_tex_cache: Dictionary = {}
var _shop_tex_cache: Dictionary = {}
var _prop_rng := RandomNumberGenerator.new()
var _prev_stage_exit_world := Vector2i.ZERO
var _shop_facings: Dictionary = {}   # shop cell -> approach facing
var _shop_body_cells: Dictionary = {}  # cell behind a shop door -> true (solid building body)
var _encounter_triggers_enabled := true
var _exit_gate_cells: Dictionary = {}  # mandatory slot -> world cell of its `X` gate
var _exit_gate_props: Dictionary = {}  # mandatory slot -> Node3D holding that gate's prop


func build(encounters: Array[Dictionary]) -> void:
	_prop_rng.seed = 20260704  # visual scatter only; fixed for a stable map
	grid = _build_grid(encounters)
	_warn_unreachable_encounters()

	for cell in grid.tiles.keys():
		_instance_tile(cell, grid.tiles[cell])
	for cell in grid.tiles.keys():
		_maybe_add_prop(cell, String(grid.zone_of.get(cell, "")))
	for b in _forest_bounds:
		_add_forest_backdrop(b["origin"], b["size"])
	for b in _ship_bounds:
		_dress_ship(b["origin"], b["size"])

	_build_signs()
	if not _encounter_cells.is_empty():
		_add_gym_lighting(_boss_cell)  # no boss cell in an encounter-less (explore) run
	_build_exit_gates()
	_build_markers(encounters)


## Data-only grid build for the headless sim harness: produces the maze layout
## (tiles, encounter cells, spawn) without instancing any 3D geometry.
func build_grid_only(encounters: Array[Dictionary]) -> void:
	_prop_rng.seed = 20260704
	grid = _build_grid(encounters)


func zone_name_for_cell(cell: Vector2i) -> String:
	var zone := String(grid.zone_of.get(cell, ""))
	if zone == "":
		return ""
	if zone == "gym":
		return _gym_label_for_cell(cell)
	return StageLayout.display_name(Balance, zone)


## Name for a gym-zone cell: the owning stage's gym_name, else its display_name
## (non-gym interiors like S.S. Anne reuse the `_` floor, so have no gym_name).
func _gym_label_for_cell(cell: Vector2i) -> String:
	var sid := String(_gym_cell_stage.get(cell, ""))
	if sid == "":
		return StageLayout.gym_display_name(Balance)
	var gname := StageLayout.gym_name_of(Balance, sid)
	return gname if gname != "" else StageLayout.display_name(Balance, sid)


func clear_marker(index: int) -> void:
	if index < 0 or index >= markers.size():
		return
	markers[index].clear()
	var enc := Run.encounter_at(index)
	if bool(enc.get("is_optional", false)):
		var cell := encounter_cell(index)
		if cell == Vector2i.ZERO or grid.kind_at(cell) != WG.TileKind.OPTIONAL_ENCOUNTER:
			return
		grid.set_tile(cell, WG.TileKind.CORRIDOR, String(grid.zone_of.get(cell, "")))
		grid.tile_meta.erase(cell)
		return
	# A leader falling opens its stage's exit gate. WorldGrid already reopens the
	# tile itself (same slot), so this just drops the prop standing in the way.
	_open_exit_gate(int(enc.get("mandatory_slot", -1)))


func _open_exit_gate(slot: int) -> void:
	if not _exit_gate_props.has(slot):
		return
	(_exit_gate_props[slot] as Node3D).queue_free()
	_exit_gate_props.erase(slot)


func set_encounter_triggers_enabled(enabled: bool) -> void:
	_encounter_triggers_enabled = enabled


func set_active_marker(index: int) -> void:
	for marker in markers:
		marker.set_active(marker.encounter_index == index)


func shop_approach_facing(shop_cell: Vector2i) -> int:
	return int(_shop_facings.get(shop_cell, WG.Facing.SOUTH))


func _on_tile_entered(cell: Vector2i, facing: int) -> void:
	if _try_trigger_encounter(cell, facing):
		return
	var meta = grid.tile_meta.get(cell)
	if meta != null and meta.has("shop_window"):
		shop_entered.emit(int(meta["shop_window"]), String(meta.get("shop_kind", "center")))


func encounter_cell(flat_idx: int) -> Vector2i:
	if flat_idx >= 0 and flat_idx < _encounter_cells.size():
		return _encounter_cells[flat_idx]
	return Vector2i.ZERO


func _try_trigger_encounter(cell: Vector2i, facing: int) -> bool:
	if not _encounter_triggers_enabled:
		return false
	# Face an adjacent encounter tile to start the fight. Gate and optional wilds
	# both use a walkable trigger corridor beside a blocked encounter tile, so
	# the player opts in by turning toward the Pokémon (can walk past otherwise).
	var front: Vector2i = cell + WG.FACING_DIR[facing]
	for i in _encounter_cells.size():
		if _encounter_cells[i] == front and _emit_encounter(i):
			return true
	return false


func _emit_encounter(flat_idx: int) -> bool:
	if flat_idx < 0 or flat_idx >= markers.size():
		return false
	if markers[flat_idx].cleared or not Run.can_trigger_encounter(flat_idx):
		return false
	encounter_triggered.emit(markers[flat_idx])
	return true


# --- Grid layout (stage_layouts.json) ---

func _build_grid(encounters: Array[Dictionary]):
	var g := WG.new()
	g.run_ref = Run
	_encounter_cells.clear()
	_encounter_cells.resize(encounters.size())
	_zone_sign_cells.clear()
	_gym_cell_stage.clear()
	_forest_bounds.clear()
	_ship_bounds.clear()
	_shop_facings.clear()
	_shop_body_cells.clear()
	_exit_gate_cells.clear()

	var stage_origin := Vector2i.ZERO
	var first_stage := true

	for stage_id in StageLayout.stage_ids_in_order(Balance):
		# Placement is author-driven: a stage's `world_pos` (set in the map editor's
		# World View) is its origin in the shared grid. Stages with no `world_pos` yet
		# fall back to legacy telescoping so the run still builds.
		if StageLayout.has_world_pos(Balance, stage_id):
			stage_origin = StageLayout.world_pos_of(Balance, stage_id)
		elif first_stage:
			stage_origin = Vector2i.ZERO
		else:
			var spawn_local := StageLayout.spawn_local(Balance, stage_id)
			stage_origin = _prev_stage_exit_world + Vector2i(0, 1) - spawn_local
		if first_stage:
			spawn_cell = StageLayout.spawn_world(Balance, stage_id, stage_origin)
			first_stage = false

		_stamp_stage(g, stage_id, stage_origin, encounters)
		var stage_size := StageLayout.size_local(Balance, stage_id)
		_zone_sign_cells[stage_id] = StageLayout.local_to_world(
				Vector2i(stage_size.x / 2, stage_size.y - 1), stage_origin)
		_prev_stage_exit_world = StageLayout.local_to_world(
				StageLayout.exit_local(Balance, stage_id), stage_origin)

	if not _encounter_cells.is_empty():
		_boss_cell = _encounter_cells[_encounter_cells.size() - 1]
	return g


## Structural reachability check: flood the walkable grid from spawn and warn for
## any encounter tile a wall (e.g. a shop footprint) has sealed off. Ignores gate
## clear-state — this is about physical connectivity, not progression order.
func _warn_unreachable_encounters() -> void:
	if grid == null or _encounter_cells.is_empty():
		return
	var reached := {spawn_cell: true}
	var frontier: Array[Vector2i] = [spawn_cell]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in WG.FACING_DIR:
			var n: Vector2i = c + d
			if reached.has(n) or grid.kind_at(n) == WG.TileKind.WALL:
				continue
			reached[n] = true
			frontier.append(n)
	for idx in _encounter_cells.size():
		var cell: Vector2i = _encounter_cells[idx]
		if cell != Vector2i.ZERO and not reached.has(cell):
			push_warning("WorldMapBuilder: encounter %d at %s is unreachable from spawn "
					% [idx, cell] + "(a shop footprint or wall may have sealed it off).")


func _stamp_stage(g, stage_id: String, origin: Vector2i,
		encounters: Array[Dictionary]) -> void:
	var size := StageLayout.size_local(Balance, stage_id)
	var blocked: Dictionary = {}
	for cell in StageLayout.blocked_cells_local(Balance, stage_id):
		blocked[cell] = true

	var zone_id := stage_id
	var materials := StageLayout.material_local(Balance, stage_id)
	var floor_materials := StageLayout.floor_material_local(Balance, stage_id)
	for ly in range(size.y):
		for lx in range(size.x):
			var local_cell := Vector2i(lx, ly)
			var world_cell := StageLayout.local_to_world(local_cell, origin)
			g.material_of[world_cell] = String(materials.get(local_cell, "grass"))
			g.floor_material_of[world_cell] = String(floor_materials.get(local_cell, "grass"))
			if blocked.has(local_cell):
				g.set_tile(world_cell, WG.TileKind.WALL, zone_id)
			else:
				g.set_tile(world_cell, WG.TileKind.CORRIDOR, zone_id)

	# Surfable-water cells (walkable, gated by Surf in is_walkable).
	for cell in StageLayout.surf_cells_local(Balance, stage_id):
		g.surf_cells[StageLayout.local_to_world(cell, origin)] = true

	# Gym anchors come from the grid ('_' floor, 'D' door); no-ops for non-gym stages.
	# The shared "gym" zone drives arena rendering, so remember which stage owns each
	# gym cell to name it correctly (its gym_name, else its display_name).
	for cell in StageLayout.gym_floor_cells_local(Balance, stage_id):
		var gym_world := StageLayout.local_to_world(cell, origin)
		g.set_tile(gym_world, WG.TileKind.GYM_FLOOR, "gym")
		_gym_cell_stage[gym_world] = stage_id
	var door_local := StageLayout.gym_door_local(Balance, stage_id)
	if door_local.x >= 0:
		var door_world := StageLayout.local_to_world(door_local, origin)
		g.set_tile(door_world, WG.TileKind.GYM_DOOR, zone_id)
		_gym_cell_stage[door_world] = stage_id

	# Forest stages get a receding wall of trees behind their edge (rendered in build);
	# ship stages get interior lamps + hull portholes. Both are deferred to build().
	var tmpl := StageLayout.template_id(Balance, stage_id)
	if tmpl == "forest_maze":
		_forest_bounds.append({"origin": origin, "size": size})
	elif tmpl == "ship_interior":
		_ship_bounds.append({"origin": origin, "size": size})

	var opt_spawns := StageLayout.optional_spawns_local(Balance, stage_id)
	var trainer_spawns := StageLayout.trainer_spawns_local(Balance, stage_id)
	var opt_idx := 0
	var tr_idx := 0
	for flat_i in encounters.size():
		var enc: Dictionary = encounters[flat_i]
		if String(enc["stage_id"]) != stage_id:
			continue
		if bool(enc.get("is_optional", false)):
			# Wilds sit on `w` cells; route trainers on `t` cells (separate placements).
			if String(enc.get("placement", "wild")) == "trainer":
				if tr_idx < trainer_spawns.size():
					_place_optional_encounter(g, trainer_spawns[tr_idx], origin, zone_id, flat_i)
					tr_idx += 1
			elif opt_idx < opt_spawns.size():
				_place_optional_encounter(g, opt_spawns[opt_idx], origin, zone_id, flat_i)
				opt_idx += 1
		elif bool(enc.get("is_mandatory", false)):
			var gate := StageLayout.gate_local(Balance, stage_id)
			var enc_zone := "gym" if bool(enc.get("is_gym", false)) else zone_id
			_place_mandatory_gate(g, gate, origin, enc_zone, flat_i, enc, stage_id)

	_stamp_shops(g, stage_id, origin, zone_id)


func _place_optional_encounter(g, spawn_def: Dictionary, origin: Vector2i,
		zone_id: String, flat_idx: int) -> void:
	var trigger_world := StageLayout.local_to_world(spawn_def["trigger"], origin)
	var encounter_world := StageLayout.local_to_world(spawn_def["encounter"], origin)
	g.set_tile(trigger_world, WG.TileKind.CORRIDOR, zone_id)
	g.set_tile(encounter_world, WG.TileKind.OPTIONAL_ENCOUNTER, zone_id)
	g.tile_meta[encounter_world] = {"encounter_index": flat_idx}
	_encounter_cells[flat_idx] = encounter_world


func _place_mandatory_gate(g, gate: Dictionary, origin: Vector2i, zone_id: String,
		flat_idx: int, enc: Dictionary, stage_id: String) -> void:
	var trigger_world := StageLayout.local_to_world(gate["trigger"], origin)
	var encounter_world := StageLayout.local_to_world(gate["encounter"], origin)
	var mandatory_slot := int(enc.get("mandatory_slot", 0))

	g.set_tile(trigger_world, WG.TileKind.CORRIDOR, zone_id)
	var enc_kind := WG.TileKind.GYM_FLOOR if zone_id == "gym" else WG.TileKind.GATE_ENCOUNTER
	g.set_tile(encounter_world, enc_kind, zone_id)
	g.tile_meta[encounter_world] = {"encounter_index": flat_idx}
	_encounter_cells[flat_idx] = encounter_world

	# Manual gating (Phase 7): a leader blocks only its own tile until cleared.
	# Authors gate progression with map chokepoints, so there is no auto-funnel
	# blocking the region north of the leader.
	_gate_block_cells(g, mandatory_slot, [encounter_world])

	# …but a leader in a dead-end side room (every city gym) is a chokepoint for
	# nothing, so the stage's exit gate (`X`) blocks on the same slot: the area
	# stays shut until its leader falls. Stages that gate by chokepoint alone
	# (Pewter, the Elite Four) author no `X` and are unaffected.
	var exit_gate := StageLayout.exit_gate_local(Balance, stage_id)
	if exit_gate.x >= 0:
		var exit_world := StageLayout.local_to_world(exit_gate, origin)
		_gate_block_cells(g, mandatory_slot, [exit_world])
		_exit_gate_cells[mandatory_slot] = exit_world


func _stamp_shops(g, stage_id: String, origin: Vector2i, zone_id: String) -> void:
	var shops := StageLayout.shop_cells_local(Balance, stage_id)
	var windows := StageLayout.shop_windows_local(Balance, stage_id)
	if shops.has("center"):
		_stamp_one_shop(g, StageLayout.local_to_world(shops["center"], origin),
				zone_id, int(windows.get("center", 1)), "center")
	if shops.has("mart"):
		_stamp_one_shop(g, StageLayout.local_to_world(shops["mart"], origin),
				zone_id, int(windows.get("mart", 2)), "mart")


func _stamp_one_shop(g, door: Vector2i, zone_id: String, window: int, kind: String) -> void:
	g.set_tile(door, WG.TileKind.SHOP_DOOR, zone_id)
	g.tile_meta[door] = {"shop_window": window, "shop_kind": kind}

	# The building body sits on the tile behind the door (opposite the approach), so
	# make that tile solid — otherwise the mesh overhangs a walkable cell and you can
	# walk through the shop. The approach is always the door's front, so this can't
	# wall the door off. `_warn_unreachable_encounters` flags a body that seals a path.
	var facing := _shop_approach_facing(g, door)
	_shop_facings[door] = facing
	var body: Vector2i = door - WG.FACING_DIR[facing]
	if g.kind_at(body) != WG.TileKind.WALL:
		g.set_tile(body, WG.TileKind.WALL, String(g.zone_of.get(body, zone_id)))
		_shop_body_cells[body] = true


func _gate_block_cells(g, mandatory_slot: int, cells: Array) -> void:
	for cell in cells:
		g.gate_encounter[cell] = mandatory_slot


# --- Per-tile geometry ---

func _instance_tile(cell: Vector2i, kind: int) -> void:
	var zone_id := String(grid.zone_of.get(cell, "route_viridian"))
	var pos := WG.world_pos(cell)
	var mat_name := String(grid.material_of.get(cell, "grass"))

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(WG.TILE_SIZE, 0.1, WG.TILE_SIZE)
	floor_mesh.mesh = floor_box
	# Floor shows the ground rendered under this cell (grass under a tree, etc).
	floor_mesh.material_override = _flat_material(
			ThemePalette.color_of(String(grid.floor_material_of.get(cell, "grass"))))
	floor_mesh.position = pos + Vector3(0, -0.05, 0)
	add_child(floor_mesh)

	if zone_id == "gym":
		_add_ceiling(pos, Color(0.3, 0.28, 0.26))
	else:
		match _stage_template(zone_id):
			"cave_branches":
				# Caves (Mt. Moon) get a rock roof so they read as enclosed, not open sky.
				_add_ceiling(pos, Color(0.17, 0.15, 0.14))
			"ship_interior":
				# Ships are an enclosed deck: a wooden ceiling over the hull, but not
				# over the surrounding sea cells that belong to the same stage grid.
				if mat_name != "water":
					_add_ceiling(pos, Color(0.30, 0.24, 0.17))

	# Barrier cells become 3D props (tree / building / boulder / pillar / water…);
	# walkable cells stay open so the props enclose the corridors (Phase 7 slice 2).
	# Shop-body cells are solid too, but the shop building mesh covers them — no prop.
	if kind == WG.TileKind.WALL and not _shop_body_cells.has(cell):
		_place_barrier_prop(pos, mat_name)

	if kind == WG.TileKind.SHOP_DOOR:
		var shop_kind := String(grid.tile_meta.get(cell, {}).get("shop_kind", "center"))
		_build_shop_building(cell, pos, shop_kind)
	elif kind == WG.TileKind.GYM_DOOR:
		_dress_gym_door(cell, pos)


## Stand a barrier prop on every closed exit gate, so an area whose leader is still
## standing reads as sealed rather than as an invisible wall. Each gate owns its
## meshes, and `_open_exit_gate` frees them when that leader falls.
func _build_exit_gates() -> void:
	_exit_gate_props.clear()
	for slot in _exit_gate_cells:
		var cell: Vector2i = _exit_gate_cells[slot]
		var holder := Node3D.new()
		add_child(holder)
		_exit_gate_props[slot] = holder
		_place_barrier_prop(WG.world_pos(cell), _gate_material_for(cell), holder)


## What a gate on `cell` is built from: whatever barrier walls it in (the hedge
## line, the cave rock, the sea), else the stage theme's default barrier. Keeps a
## gate in a hedge a hedge, and one across water unsurfable water.
func _gate_material_for(cell: Vector2i) -> String:
	for d in WG.FACING_DIR:
		var neighbour: Vector2i = cell + d
		if grid.kind_at(neighbour) != WG.TileKind.WALL:
			continue
		var mat := String(grid.material_of.get(neighbour, ""))
		if mat != "" and ThemePalette.is_barrier(mat):
			return mat
	return ThemePalette.theme_barrier(_stage_template(String(grid.zone_of.get(cell, ""))))


## A flat overhead slab at wall height, used for gym and cave roofs.
func _add_ceiling(pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WG.TILE_SIZE, 0.1, WG.TILE_SIZE)
	mi.mesh = box
	mi.material_override = _flat_material(color)
	mi.position = pos + Vector3(0, WG.WALL_HEIGHT, 0)
	add_child(mi)


## Template ('cave_branches', 'ship_interior', …) of the stage owning a cell's zone.
## Empty for the shared "gym" zone and any non-stage zone (no layout to read).
func _stage_template(zone_id: String) -> String:
	if zone_id == "" or zone_id == "gym":
		return ""
	if not Balance.stage_layouts.has(zone_id):
		return ""
	return StageLayout.template_id(Balance, zone_id)


## A barrier cell rendered as a 3D prop, shaped + sized by its terrain material.
## `parent` (default: this builder) lets a caller own the resulting meshes so it
## can free them later — used by the exit gates, which vanish when they open.
func _place_barrier_prop(pos: Vector3, material: String, parent: Node3D = null) -> void:
	var h := ThemePalette.height_of(material) * WG.WALL_HEIGHT
	var color := ThemePalette.color_of(material)
	var emissive := ThemePalette.is_emissive(material)
	var t := WG.TILE_SIZE
	match ThemePalette.shape_of(material):
		"tree":
			_add_terrain_box(pos + Vector3(0, h * 0.24, 0), Vector3(0.5, h * 0.48, 0.5),
					Color(0.30, 0.20, 0.11), false, parent)  # trunk
			# Canopy is wider than a tile so neighbours overlap into a solid wall, and
			# stacks two tiers so you can't see over or between the trees.
			_add_terrain_box(pos + Vector3(0, h * 0.60, 0), Vector3(t * 1.2, h * 0.62, t * 1.2),
					color.darkened(0.08), false, parent)     # lower canopy
			_add_terrain_box(pos + Vector3(0, h * 0.98, 0), Vector3(t * 1.05, h * 0.55, t * 1.05),
					color, false, parent)                    # upper canopy
		"boulder":
			_add_terrain_box(pos + Vector3(0, h * 0.5, 0), Vector3(t * 0.82, h, t * 0.82),
					color, false, parent)
		"pillar":
			_add_terrain_box(pos + Vector3(0, h * 0.5, 0), Vector3(0.7, h, 0.7), color, false, parent)
		"flat":  # water / lava — low pool covering the tile
			_add_terrain_box(pos + Vector3(0, 0.12, 0), Vector3(t, 0.14, t), color, emissive, parent)
		_:  # block — wall / building / mountain / hedge / railing
			_add_terrain_box(pos + Vector3(0, h * 0.5, 0), Vector3(t, h, t), color, emissive, parent)


func _add_terrain_box(center: Vector3, size: Vector3, color: Color, emissive: bool,
		parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.7
	mi.material_override = mat
	mi.position = center
	if parent != null:
		parent.add_child(mi)
	else:
		add_child(mi)


## Rings of tree blocks just outside a forest stage, each ring a touch taller and
## darker than the last so the forest edge recedes instead of ending at open sky.
## Kept close to the height of the in-forest trees (tree = 1.4 * WALL_HEIGHT) so the
## backdrop reads as more forest, not a black wall towering over the canopy.
func _add_forest_backdrop(origin: Vector2i, size: Vector2i) -> void:
	const RINGS := 3
	var base := ThemePalette.color_of("tree")
	for ring in range(1, RINGS + 1):
		var col := base.darkened(0.12 * ring)
		var height := WG.WALL_HEIGHT * (1.4 + 0.3 * ring)
		var x0 := origin.x - ring
		var x1 := origin.x + size.x - 1 + ring
		var y0 := origin.y - ring
		var y1 := origin.y + size.y - 1 + ring
		for x in range(x0, x1 + 1):
			_backdrop_tree(Vector2i(x, y0), col, height)
			_backdrop_tree(Vector2i(x, y1), col, height)
		for y in range(y0 + 1, y1):
			_backdrop_tree(Vector2i(x0, y), col, height)
			_backdrop_tree(Vector2i(x1, y), col, height)


func _backdrop_tree(cell: Vector2i, color: Color, height: float) -> void:
	if grid.tiles.has(cell):
		return  # don't cover a neighbouring stage's tiles — only fill empty space
	var pos := WG.world_pos(cell)
	var w := WG.TILE_SIZE * 1.25
	_add_terrain_box(pos + Vector3(0, height * 0.5, 0), Vector3(w, height, w), color, false)


## Dress a ship stage: warm ceiling lamps over the interior so it reads as "well
## lit", and portholes on hull walls (metal barriers that touch the surrounding sea).
func _dress_ship(origin: Vector2i, size: Vector2i) -> void:
	for ly in range(size.y):
		for lx in range(size.x):
			var cell := origin + Vector2i(lx, ly)
			var mat := String(grid.material_of.get(cell, ""))
			if grid.kind_at(cell) == WG.TileKind.WALL:
				# Only the outer hull (a metal wall facing open water) gets a porthole;
				# interior cabin dividers stay solid.
				if mat == "wall_metal" and _wall_touches_water(cell):
					var idir := _interior_dir_for_wall(cell)
					if idir != Vector2i.ZERO:
						_add_porthole(cell, idir)
			elif mat == "wood" and lx % 4 == 2 and ly % 3 == 2:
				_add_ship_lamp(WG.world_pos(cell))


## Direction from a wall cell toward the first adjacent walkable (interior) cell.
func _interior_dir_for_wall(cell: Vector2i) -> Vector2i:
	for d in WG.FACING_DIR:
		if grid.kind_at(cell + d) != WG.TileKind.WALL:
			return d
	return Vector2i.ZERO


func _wall_touches_water(cell: Vector2i) -> bool:
	for d in WG.FACING_DIR:
		if String(grid.material_of.get(cell + d, "")) == "water":
			return true
	return false


## A round porthole on the interior face of a hull wall, oriented to face inward.
func _add_porthole(cell: Vector2i, dir: Vector2i) -> void:
	var pos := WG.world_pos(cell)
	var face := pos \
			+ Vector3(dir.x, 0, dir.y) * (WG.TILE_SIZE * 0.5 - 0.03) \
			+ Vector3(0, WG.EYE_HEIGHT, 0)
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	mi.mesh = quad
	var mat := _textured_material(_ship_porthole_texture())
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = face
	# QuadMesh faces +Z; yaw so that normal points along `dir` (into the interior).
	mi.rotation.y = atan2(float(dir.x), float(dir.y))
	add_child(mi)


func _add_ship_lamp(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, WG.WALL_HEIGHT - 0.5, 0)
	light.light_color = Color(1.0, 0.85, 0.6)
	light.omni_range = 7.5
	light.light_energy = 1.6
	add_child(light)

	var lamp := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.1, 0.7)
	lamp.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.72)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.55)
	mat.emission_energy_multiplier = 1.8
	lamp.material_override = mat
	lamp.position = pos + Vector3(0, WG.WALL_HEIGHT - 0.06, 0)
	add_child(lamp)


## Metal plate with a round blue-glass window (cached). Reads as "you're at sea".
func _ship_porthole_texture() -> ImageTexture:
	if _shop_tex_cache.has("porthole"):
		return _shop_tex_cache["porthole"]
	var img := PixelArt.new_canvas_wh(48, 48)
	img.fill(Color(0.30, 0.32, 0.36))                      # metal plate
	var c := Vector2(24, 24)
	PixelArt.filled_circle(img, c, 21, Color(0.17, 0.18, 0.21))   # recessed shadow
	PixelArt.filled_circle(img, c, 18, Color(0.58, 0.61, 0.66))   # brass/steel ring
	PixelArt.filled_circle(img, c, 13, Color(0.24, 0.46, 0.64))   # sea-blue glass
	PixelArt.filled_circle(img, Vector2(20, 20), 7, Color(0.34, 0.60, 0.78))   # upper sheen
	PixelArt.filled_circle(img, Vector2(19, 19), 3.2, Color(0.80, 0.90, 0.98))  # glint
	# Four bolts around the ring.
	for p in [Vector2(24, 5), Vector2(24, 43), Vector2(5, 24), Vector2(43, 24)]:
		PixelArt.filled_circle(img, p, 1.6, Color(0.20, 0.21, 0.24))
	var tex := PixelArt.to_texture(img)
	_shop_tex_cache["porthole"] = tex
	return tex


func _build_shop_building(cell: Vector2i, pos: Vector3, shop_kind: String) -> void:
	var is_center := shop_kind == "center"
	var roof_color := Color(0.86, 0.18, 0.18) if is_center else Color(0.18, 0.4, 0.84)
	var roof_dark := roof_color.darkened(0.32)
	var roof_light := roof_color.lightened(0.22)
	var facing := int(_shop_facings.get(cell, WG.Facing.SOUTH))

	var push := Vector3(-WG.FACING_DIR[facing].x, 0, -WG.FACING_DIR[facing].y) * (WG.TILE_SIZE * 0.38)
	var root := Node3D.new()
	root.position = pos + push
	root.rotation.y = WG.yaw_for_facing(facing)
	add_child(root)

	# Big enough footprint (roughly a 1x0.7 tile) to fit a door, a window and
	# readable signage on the facade without cramming them together.
	var bw := 2.8
	var bd := 2.0
	var bh := 2.0
	var wall_t := 0.12
	var front_z := -bd * 0.5
	var back_z := bd * 0.5
	var wall_mat := _flat_material(Color(0.95, 0.95, 0.96))
	# Facade decals sit just outside the wall/jamb volume (which spans
	# [front_z, front_z + wall_t]) so they're never hidden behind a jamb's
	# own outward face when they overlap it in x/y.
	var face_z := front_z - 0.02
	var wall_top := 0.16 + bh

	_add_box(root, Vector3(0, 0.08, 0), Vector3(bw + 0.1, 0.16, bd + 0.08),
			_flat_material(Color(0.6, 0.58, 0.56)))

	# Side/back walls + a thin lintel above the door (no blank gap: the door
	# itself runs from the ground almost all the way up to this lintel).
	_add_box(root, Vector3(0, bh * 0.5 + 0.16, back_z - wall_t * 0.5),
			Vector3(bw, bh, wall_t), wall_mat)
	_add_box(root, Vector3(-bw * 0.5 + wall_t * 0.5, bh * 0.5 + 0.16, 0),
			Vector3(wall_t, bh, bd), wall_mat)
	_add_box(root, Vector3(bw * 0.5 - wall_t * 0.5, bh * 0.5 + 0.16, 0),
			Vector3(wall_t, bh, bd), wall_mat)

	# Jambs run flush from the inner face of the side walls to the door's
	# edges, so there is no gap between the facade and the door opening.
	var door_w := 0.62
	var door_h := bh - 0.3
	var door_top := 0.16 + door_h
	var side_inner_x := bw * 0.5 - wall_t
	var jamb_w := side_inner_x - door_w * 0.5
	var jamb_x := (side_inner_x + door_w * 0.5) * 0.5
	_add_box(root, Vector3(-jamb_x, bh * 0.5 + 0.16, front_z + wall_t * 0.5),
			Vector3(jamb_w, bh, wall_t), wall_mat)
	_add_box(root, Vector3(jamb_x, bh * 0.5 + 0.16, front_z + wall_t * 0.5),
			Vector3(jamb_w, bh, wall_t), wall_mat)
	_add_box(root, Vector3(0, door_top + (bh - door_h) * 0.5, front_z + wall_t * 0.5),
			Vector3(door_w, bh - door_h, wall_t), wall_mat)

	# Centered double door, flush with the wall face, filling the opening
	# from the ground straight up to the lintel.
	var mullion_w := 0.03
	var leaf_w := (door_w - mullion_w) * 0.5
	var leaf_x := (door_w + mullion_w) * 0.25
	_add_box(root, Vector3(-leaf_x, 0.16 + door_h * 0.5, face_z),
			Vector3(leaf_w, door_h, 0.02), _door_material())
	_add_box(root, Vector3(leaf_x, 0.16 + door_h * 0.5, face_z),
			Vector3(leaf_w, door_h, 0.02), _door_material())
	_add_box(root, Vector3(0, 0.16 + door_h * 0.5, face_z - 0.005),
			Vector3(mullion_w, door_h, 0.02), _flat_material(Color(0.92, 0.92, 0.94)))

	# One blue window and one text sign, on opposite sides of the door
	# (mirrored between the Center and the Mart, like the reference art).
	var window_x := -jamb_x if is_center else jamb_x
	var sign_x := jamb_x if is_center else -jamb_x
	_build_window(root, Vector3(window_x, 1.05, face_z))
	_add_quad(root, Vector3(sign_x, 1.05, face_z), Vector2(0.62, 0.3),
			_textured_material(_shop_text_sign_texture(is_center)))

	# Colored fascia band at the roofline with the pokeball emblem, flush
	# with the wall so the overhanging roof above can't hide it.
	var band_h := 0.32
	_add_box(root, Vector3(0, wall_top + band_h * 0.5, 0),
			Vector3(bw, band_h, bd), _flat_material(roof_color))
	_add_quad(root, Vector3(0, wall_top + band_h * 0.5, face_z),
			Vector2(0.4, 0.4), _textured_material(_shop_emblem_texture(is_center)))

	# Thick overhanging roof: a flat slab behind a rounded front lip. The lip's
	# rear tangent sits exactly at the wall face so it can never droop down in
	# front of the band/signage below it.
	var roof_mat := _flat_material(roof_color)
	var roof_over := 0.2
	var roof_h := 0.42
	var radius := roof_h * 0.5
	var roof_y0 := wall_top + band_h
	var roof_w := bw + roof_over * 2.0
	var lip_center_z := front_z - radius
	var slab_back_z := back_z + roof_over
	var slab_depth := slab_back_z - front_z
	_add_box(root, Vector3(0, roof_y0 + radius, front_z + slab_depth * 0.5),
			Vector3(roof_w, roof_h, slab_depth), roof_mat)

	var lip := MeshInstance3D.new()
	var lip_mesh := CylinderMesh.new()
	lip_mesh.top_radius = radius
	lip_mesh.bottom_radius = radius
	lip_mesh.height = roof_w
	lip_mesh.radial_segments = 16
	lip.mesh = lip_mesh
	lip.material_override = _flat_material(roof_color)
	lip.rotation_degrees = Vector3(0, 0, 90)
	lip.position = Vector3(0, roof_y0 + radius, lip_center_z)
	root.add_child(lip)

	_add_box(root, Vector3(0, roof_y0 + roof_h - 0.03, lip_center_z - radius * 0.6),
			Vector3(roof_w - 0.12, 0.04, 0.04), _flat_material(roof_light))
	_add_box(root, Vector3(0, roof_y0 + 0.02, lip_center_z - radius * 0.75),
			Vector3(roof_w - 0.12, 0.04, 0.04), _flat_material(roof_dark))

	var mat_anchor := Node3D.new()
	mat_anchor.position = pos
	mat_anchor.rotation.y = root.rotation.y
	add_child(mat_anchor)
	_add_box(mat_anchor, Vector3(0, 0.03, -WG.TILE_SIZE * 0.08), Vector3(0.9, 0.02, 0.62),
			_flat_material(roof_light))


## A window pane: tinted blue glass with a light cross mullion on top.
## The mullion sits at a smaller z (further outward, toward the camera) so
## it draws in front of the glass instead of being hidden behind it.
func _build_window(parent: Node3D, local_pos: Vector3) -> void:
	_add_box(parent, local_pos, Vector3(0.5, 0.62, 0.02), _window_material())
	var frame := Color(0.93, 0.94, 0.96)
	_add_box(parent, local_pos - Vector3(0, 0, 0.006), Vector3(0.5, 0.04, 0.01), _flat_material(frame))
	_add_box(parent, local_pos - Vector3(0, 0, 0.006), Vector3(0.04, 0.62, 0.01), _flat_material(frame))


func _shop_approach_facing(g, cell: Vector2i) -> int:
	var best_facing := WG.Facing.SOUTH
	var best_score := -1
	for facing in 4:
		var dir: Vector2i = WG.FACING_DIR[facing]
		var n := cell + dir
		if not g.tiles.has(n):
			continue
		var kind: int = g.kind_at(n)
		if kind == WG.TileKind.WALL:
			continue
		var score := 1
		if kind == WG.TileKind.CORRIDOR or kind == WG.TileKind.GATE_ENCOUNTER:
			score = 3
		elif kind == WG.TileKind.SHOP_DOOR:
			score = 2
		if facing == WG.Facing.SOUTH:
			score += 1
		if score > best_score:
			best_score = score
			best_facing = facing
	return best_facing


func _add_box(parent: Node3D, local_pos: Vector3, size: Vector3, mat: Material) -> void:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.position = local_pos
	parent.add_child(mesh_inst)


## Flat textured decal facing local -Z (the building's front). BoxMesh's UV
## unwrap doesn't give a thin face a full 0-1 texture range (it crops to a
## sliver of the source image), so any *textured* facade decal must use a
## quad instead of a thin box.
func _add_quad(parent: Node3D, local_pos: Vector3, size: Vector2, mat: Material) -> void:
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mesh_inst.mesh = quad
	mesh_inst.material_override = mat
	mesh_inst.position = local_pos
	mesh_inst.rotation_degrees = Vector3(0, 180, 0)
	parent.add_child(mesh_inst)


func _textured_material(tex: ImageTexture) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.9
	return mat


func _window_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.9)
	mat.roughness = 0.35
	mat.metallic = 0.05
	return mat


func _door_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.22, 0.3)
	mat.roughness = 0.85
	return mat


func _glass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.68, 0.92, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic = 0.05
	return mat


## Small round pokeball plate for the fascia band above the door.
func _shop_emblem_texture(is_center: bool) -> ImageTexture:
	var key := "emblem_center" if is_center else "emblem_mart"
	if _shop_tex_cache.has(key):
		return _shop_tex_cache[key]
	var bg := Color(0.96, 0.96, 0.97)
	var img := PixelArt.new_canvas_wh(40, 40)
	img.fill(bg)
	var stripe := Color(0.86, 0.18, 0.18) if is_center else Color(0.18, 0.4, 0.84)
	var cx := 20.0
	var cy := 20.0
	var r := 15.0
	PixelArt.filled_circle(img, Vector2(cx, cy), r, stripe)
	# Bottom half of the pokeball is white; only the top half stays colored.
	for y in range(int(cy), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy)) <= r:
				img.set_pixel(x, y, bg)
	PixelArt.rect(img, Rect2i(int(cx - r), int(cy - 1), int(r * 2.0) + 1, 2), Color(0.16, 0.16, 0.18))
	PixelArt.filled_circle(img, Vector2(cx, cy), 4.5, Color(0.16, 0.16, 0.18))
	PixelArt.filled_circle(img, Vector2(cx, cy), 2.8, bg)
	var tex := PixelArt.to_texture(img)
	_shop_tex_cache[key] = tex
	return tex


## "P.C" / "MART" plaque, drawn with the tiny block font in _SIGN_GLYPHS.
func _shop_text_sign_texture(is_center: bool) -> ImageTexture:
	var key := "text_sign_center" if is_center else "text_sign_mart"
	if _shop_tex_cache.has(key):
		return _shop_tex_cache[key]
	var text := "P.C" if is_center else "MART"
	var color := Color(0.82, 0.16, 0.16) if is_center else Color(0.16, 0.38, 0.82)
	var px := 3
	var glyph_w := 5 * px
	var glyph_h := 7 * px
	var text_w := text.length() * glyph_w + (text.length() - 1) * px
	var pad := 6
	var img := PixelArt.new_canvas_wh(text_w + pad * 2, glyph_h + pad * 2)
	img.fill(Color(0.96, 0.96, 0.97))
	_draw_pixel_text(img, text, pad, pad, px, color)
	var tex := PixelArt.to_texture(img)
	_shop_tex_cache[key] = tex
	return tex


func _draw_pixel_text(img: Image, text: String, x0: int, y0: int, px: int, color: Color) -> void:
	var cursor_x := x0
	for ch in text:
		var glyph: Array = _SIGN_GLYPHS.get(ch, [])
		for row in range(glyph.size()):
			var line: String = glyph[row]
			for col in range(line.length()):
				if line[col] == "1":
					PixelArt.rect(img, Rect2i(cursor_x + col * px, y0 + row * px, px, px), color)
		cursor_x += 5 * px + px


func _dress_gym_door(cell: Vector2i, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = _gym_label_for_cell(cell).to_upper()
	label.position = pos + Vector3(0, 2.4, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.outline_size = 14
	label.modulate = Color(0.95, 0.75, 0.25)
	label.visibility_range_end = 9.0
	label.visibility_range_end_margin = 2.5
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(label)

	var accent_floor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WG.TILE_SIZE - 0.4, 0.02, WG.TILE_SIZE - 0.4)
	accent_floor.mesh = box
	accent_floor.material_override = _flat_material(Color(0.75, 0.55, 0.2))
	accent_floor.position = pos + Vector3(0, 0.03, 0)
	add_child(accent_floor)


func _floor_color(zone_id: String) -> Color:
	match zone_id:
		"route_viridian":
			return Color(0.55, 0.5, 0.38)
		"viridian_forest":
			return Color(0.32, 0.4, 0.24)
		"pewter":
			return Color(0.5, 0.48, 0.45)
		"gym":
			return Color(0.45, 0.43, 0.4)
		_:
			return Color(0.5, 0.5, 0.5)


# --- Wall textures (procedural, cached per zone) ---

func _wall_texture(zone_id: String) -> ImageTexture:
	if _wall_tex_cache.has(zone_id):
		return _wall_tex_cache[zone_id]
	var img := PixelArt.new_canvas_wh(64, 64)
	match zone_id:
		"route_viridian":
			_paint_hedge(img)
		"viridian_forest":
			_paint_treeline(img)
		"pewter":
			_paint_fence(img)
		"gym":
			_paint_brick(img)
		_:
			_paint_hedge(img)
	var tex := PixelArt.to_texture(img)
	_wall_tex_cache[zone_id] = tex
	return tex


func _paint_hedge(img: Image) -> void:
	img.fill(Color(0.22, 0.4, 0.18))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in 70:
		var p := Vector2(rng.randf_range(0, 64), rng.randf_range(0, 64))
		PixelArt.filled_circle(img, p, rng.randf_range(1.0, 2.2), Color(0.32, 0.52, 0.24))
	for _i in 14:
		PixelArt.rect(img, Rect2i(rng.randi_range(0, 60), rng.randi_range(0, 60), 2, 1), Color(0.4, 0.3, 0.15))


func _paint_treeline(img: Image) -> void:
	img.fill(Color(0.14, 0.24, 0.13))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 6:
		var x := 4 + i * 10
		PixelArt.rect(img, Rect2i(x, 30, 3, 34), Color(0.28, 0.2, 0.12))
	for _i in 60:
		var p := Vector2(rng.randf_range(0, 64), rng.randf_range(0, 34))
		PixelArt.filled_circle(img, p, rng.randf_range(2.5, 5.0), Color(0.2, 0.4, 0.18))


func _paint_fence(img: Image) -> void:
	img.fill(Color(0.62, 0.5, 0.35))
	for i in 4:
		var y := 6 + i * 15
		PixelArt.rect(img, Rect2i(0, y, 64, 4), Color(0.45, 0.35, 0.22))
	for i in 5:
		var x := 4 + i * 13
		PixelArt.rect(img, Rect2i(x, 0, 3, 64), Color(0.5, 0.4, 0.26))


func _paint_brick(img: Image) -> void:
	img.fill(Color(0.42, 0.4, 0.37))
	var mortar := Color(0.3, 0.28, 0.26)
	for row in 8:
		var y := row * 8
		PixelArt.rect(img, Rect2i(0, y, 64, 1), mortar)
		var offset := 0 if row % 2 == 0 else 8
		var x := offset
		while x < 64:
			PixelArt.rect(img, Rect2i(x, y, 1, 8), mortar)
			x += 16
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for _i in 6:
		PixelArt.rect(img, Rect2i(rng.randi_range(0, 56), rng.randi_range(0, 56), 8, 6), Color(0.36, 0.34, 0.31))


# --- Signs, props, gym lighting ---

func _build_signs() -> void:
	for zone_id in _zone_sign_cells:
		var text := _sign_text(String(zone_id))
		if text == "":
			continue
		var cell: Vector2i = _zone_sign_cells[zone_id]
		_sign(WG.world_pos(cell) + Vector3(0, 4.0, 0), text)


func _sign_text(zone_id: String) -> String:
	match zone_id:
		"route_viridian":
			return "ROUTE 1\nWild Pokémon ahead — your journey begins!"
		"viridian_forest":
			return "VIRIDIAN FOREST\nBeware of Bug Pokémon"
		"pewter":
			return "PEWTER CITY\nHome of the Boulder Badge"
		_:
			return ""


func _sign(pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 72
	label.outline_size = 18
	label.modulate = Color(1, 1, 0.85)
	label.visibility_range_end = 11.0
	label.visibility_range_end_margin = 3.0
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(label)


func _maybe_add_prop(cell: Vector2i, zone_id: String) -> void:
	if zone_id == "" or zone_id == "gym":
		return
	if grid.kind_at(cell) == WG.TileKind.SHOP_DOOR:
		return
	for dir_idx in 4:
		if grid.kind_at(cell + WG.FACING_DIR[dir_idx]) == WG.TileKind.SHOP_DOOR:
			return
	if (cell.x + cell.y) % 3 != 0:
		return
	var side := 1 if (cell.y % 2 == 0) else -1
	var wall_cell := cell + Vector2i(side, 0)
	if grid.kind_at(wall_cell) != WG.TileKind.WALL:
		return
	# The prop is offset into the neighbouring barrier cell, so don't plant a tree
	# or boulder on top of a water/lava pool — it looks like it's growing out of it.
	var wall_mat := String(grid.material_of.get(wall_cell, ""))
	if wall_mat == "water" or wall_mat == "lava":
		return
	var pos := WG.world_pos(cell) + Vector3(side * (WG.TILE_SIZE * 0.5 + 2.5), 0, 0)
	match zone_id:
		"route_viridian":
			_tree(pos, _prop_rng.randf_range(0.8, 1.1))
		"viridian_forest":
			_tree(pos, _prop_rng.randf_range(1.0, 1.4))
		"pewter":
			_boulder(pos)


func _tree(pos: Vector3, scale: float) -> void:
	var tree := Node3D.new()
	tree.position = pos
	tree.scale = Vector3(scale, scale, scale)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 2.0
	var trunk := MeshInstance3D.new()
	trunk.mesh = trunk_mesh
	trunk.material_override = _flat_material(Color(0.45, 0.32, 0.2))
	trunk.position = Vector3(0, 1.0, 0)
	tree.add_child(trunk)
	for level in 2:
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.0
		cone_mesh.bottom_radius = 1.5 - level * 0.45
		cone_mesh.height = 1.8
		var cone := MeshInstance3D.new()
		cone.mesh = cone_mesh
		cone.material_override = _flat_material(Color(0.2, 0.45, 0.22).lightened(level * 0.08))
		cone.position = Vector3(0, 2.4 + level * 1.1, 0)
		tree.add_child(cone)
	add_child(tree)


func _boulder(pos: Vector3) -> void:
	var mesh := SphereMesh.new()
	var r := _prop_rng.randf_range(0.5, 1.1)
	mesh.radius = r
	mesh.height = r * 2.0
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.material_override = _flat_material(Color(0.45, 0.43, 0.4))
	rock.position = pos + Vector3(0, r * 0.5, 0)
	rock.scale = Vector3(1.0, 0.65, 0.85)
	rock.rotation_degrees = Vector3(0, _prop_rng.randf_range(0, 360), 0)
	add_child(rock)


func _add_gym_lighting(boss_cell: Vector2i) -> void:
	var base := WG.world_pos(boss_cell)
	var wall_x := WG.TILE_SIZE * 0.5 - 0.08
	var back_z := -WG.TILE_SIZE * 0.35
	for side in [-1, 1]:
		var pos := base + Vector3(side * wall_x, 1.8, back_z)
		var light := OmniLight3D.new()
		light.position = pos
		light.light_color = Color(1.0, 0.6, 0.3)
		light.omni_range = 6.0
		light.light_energy = 1.2
		add_child(light)

		var flame := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(0.4, 0.5)
		flame.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.6, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		mat.emission_energy_multiplier = 2.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.render_priority = -10
		flame.material_override = mat
		flame.position = pos
		flame.rotation_degrees = Vector3(0, 0, 90.0 * side)
		add_child(flame)


func _build_markers(encounters: Array[Dictionary]) -> void:
	markers.clear()
	for i in encounters.size():
		var enc := encounters[i]
		# A trainer encounter shows the trainer's portrait + name; a wild shows its Pokemon.
		var trainer_id := String(enc.get("trainer_id", ""))
		var sprite_id: String
		var display_name: String
		var companions: Array = []
		if trainer_id != "":
			sprite_id = TrainerOps.portrait_of(Balance, trainer_id)
			display_name = TrainerOps.trainer_name(Balance, trainer_id)
			# Stand the trainer's team beside them (Misty + Starmie, Surge + Raichu…).
			# Cap the row so a long sequential team doesn't sprawl past the tile.
			var team: Array = enc.get("team_pool", [])
			companions = team.slice(0, mini(3, team.size()))
		else:
			sprite_id = String(enc["enemy_id"])
			display_name = String(Balance.enemies[sprite_id]["name"])
			if String(enc["kind"]) == "wild":
				display_name = "Wild " + display_name
		var marker := EncounterMarker.new()
		add_child(marker)
		marker.position = WG.world_pos(_encounter_cells[i])
		marker.setup(i, sprite_id, display_name, _marker_kind_for(enc), companions)
		markers.append(marker)


func _marker_kind_for(enc: Dictionary) -> int:
	if bool(enc.get("is_gym", false)):
		return EncounterMarker.MarkerKind.BOSS
	if bool(enc.get("is_mandatory", false)):
		return EncounterMarker.MarkerKind.GATE
	return EncounterMarker.MarkerKind.OPTIONAL


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	return mat
