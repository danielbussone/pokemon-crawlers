class_name WorldBuilder
extends Node3D
## Builds the walkable Kanto slice as a first-person tile grid: Route/Viridian
## -> Viridian Forest -> Pewter City, with the 13 encounters laid out along a
## single-file corridor (plus two shop alcoves and a small gym room at the end).
## All geometry/textures are generated at runtime — no imported assets.

signal encounter_triggered(marker: EncounterMarker)
signal shop_entered(window: int, kind: String)

var grid: WorldGrid
var markers: Array[EncounterMarker] = []
var spawn_cell := Vector2i.ZERO

var _encounter_cells: Array[Vector2i] = []
var _zone_first_row: Dictionary = {}   # zone_id -> row (for signage)
var _boss_cell := Vector2i.ZERO
var _wall_tex_cache: Dictionary = {}
var _prop_rng := RandomNumberGenerator.new()


func build(encounters: Array[Dictionary]) -> void:
	_prop_rng.seed = 20260704  # visual scatter only; fixed for a stable map
	grid = _build_grid(encounters)

	for cell in grid.tiles.keys():
		_instance_tile(cell, grid.tiles[cell])
	for cell in grid.tiles.keys():
		_maybe_add_prop(cell, String(grid.zone_of.get(cell, "")))

	_build_signs()
	_add_gym_lighting(_boss_cell)
	_build_markers(encounters)


func zone_name_for_cell(cell: Vector2i) -> String:
	match String(grid.zone_of.get(cell, "")):
		"route_viridian":
			return "Route 1 — Viridian Outskirts"
		"viridian_forest":
			return "Viridian Forest"
		"pewter":
			return "Pewter City"
		"gym":
			return "Pewter Gym"
		_:
			return ""


func clear_marker(index: int) -> void:
	if index >= 0 and index < markers.size():
		markers[index].clear()


func set_active_marker(index: int) -> void:
	for marker in markers:
		marker.set_active(marker.encounter_index == index)


func _on_tile_entered(cell: Vector2i, _facing: int) -> void:
	var meta = grid.tile_meta.get(cell)
	if meta == null:
		return
	if meta.has("encounter_index"):
		var idx: int = meta["encounter_index"]
		if idx == Run.encounter_index and idx < markers.size() and not markers[idx].cleared:
			encounter_triggered.emit(markers[idx])
	elif meta.has("shop_window"):
		shop_entered.emit(int(meta["shop_window"]), String(meta.get("shop_kind", "center")))


# --- Grid layout ---

func _build_grid(encounters: Array[Dictionary]) -> WorldGrid:
	var g := WorldGrid.new()
	g.run_ref = Run

	spawn_cell = Vector2i.ZERO
	var spawn_zone := String(encounters[0]["stage_id"]) if not encounters.is_empty() else "route_viridian"
	g.set_tile(spawn_cell, WorldGrid.TileKind.CORRIDOR, spawn_zone)
	_zone_first_row[spawn_zone] = 0

	var row := 0
	for i in encounters.size():
		var enc: Dictionary = encounters[i]
		var zone_id := String(enc["stage_id"])
		if not _zone_first_row.has(zone_id):
			_zone_first_row[zone_id] = row + 1

		# Trigger sits one tile before the creature, not on its tile — otherwise
		# the camera ends up co-located with (behind/inside) the sprite it's
		# fighting, and can only see the next one further down the corridor.
		row += 1
		var trigger_cell := Vector2i(0, -row)
		g.set_tile(trigger_cell, WorldGrid.TileKind.CORRIDOR, zone_id)
		g.tile_meta[trigger_cell] = {"encounter_index": i}

		row += 1
		var encounter_cell := Vector2i(0, -row)
		g.set_tile(encounter_cell, WorldGrid.TileKind.ENCOUNTER, zone_id)
		_encounter_cells.append(encounter_cell)
		_boss_cell = encounter_cell

		g.gate_encounter[encounter_cell] = i

		var shop_window := int(enc.get("shop_window_after", 0))
		if shop_window > 0:
			var door_row := row + 1
			var right := Vector2i(1, -door_row)
			var left := Vector2i(-1, -door_row)
			# Left = Center, right = Mart — matches _dress_shop_door's is_center
			# convention. Each door now opens only its own service (see shop_ui.gd).
			g.set_tile(right, WorldGrid.TileKind.SHOP_DOOR, zone_id)
			g.tile_meta[right] = {"shop_window": shop_window, "shop_kind": "mart"}
			g.set_tile(left, WorldGrid.TileKind.SHOP_DOOR, zone_id)
			g.tile_meta[left] = {"shop_window": shop_window, "shop_kind": "center"}

	_carve_gym_room(g, row)
	return g


func _carve_gym_room(g: WorldGrid, boss_row: int) -> void:
	for r in range(boss_row - 2, boss_row + 1):
		g.zone_of[Vector2i(0, -r)] = "gym"
		for side_c in [-1, 1]:
			var cell := Vector2i(side_c, -r)
			g.set_tile(cell, WorldGrid.TileKind.GYM_FLOOR, "gym")


# --- Per-tile geometry ---

func _instance_tile(cell: Vector2i, kind: int) -> void:
	var zone_id := String(grid.zone_of.get(cell, "route_viridian"))
	var pos := WorldGrid.world_pos(cell)

	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(WorldGrid.TILE_SIZE, 0.1, WorldGrid.TILE_SIZE)
	floor_mesh.mesh = floor_box
	floor_mesh.material_override = _flat_material(_floor_color(zone_id))
	floor_mesh.position = pos + Vector3(0, -0.05, 0)
	add_child(floor_mesh)

	if zone_id == "gym":
		var ceil_mesh := MeshInstance3D.new()
		var ceil_box := BoxMesh.new()
		ceil_box.size = Vector3(WorldGrid.TILE_SIZE, 0.1, WorldGrid.TILE_SIZE)
		ceil_mesh.mesh = ceil_box
		ceil_mesh.material_override = _flat_material(Color(0.3, 0.28, 0.26))
		ceil_mesh.position = pos + Vector3(0, WorldGrid.WALL_HEIGHT, 0)
		add_child(ceil_mesh)

	var wall_tex := _wall_texture(zone_id)
	for dir_idx in 4:
		var dir: Vector2i = WorldGrid.FACING_DIR[dir_idx]
		if grid.kind_at(cell + dir) == WorldGrid.TileKind.WALL:
			_place_wall(pos, dir, wall_tex)

	if kind == WorldGrid.TileKind.SHOP_DOOR:
		_dress_shop_door(cell, pos)


func _place_wall(tile_pos: Vector3, dir: Vector2i, tex: ImageTexture) -> void:
	var wall := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(WorldGrid.TILE_SIZE, WorldGrid.WALL_HEIGHT)
	wall.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Without tiling, the 64x64 source texture stretches once across the full
	# 3x3m wall face — standing close and looking at it dead-on (e.g. the
	# corridor is only 1.5m to a side wall) makes it read as one giant
	# smeared blob instead of a repeating pattern.
	mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	wall.material_override = mat

	var offset := Vector3(dir.x, 0, dir.y) * (WorldGrid.TILE_SIZE / 2.0)
	wall.position = tile_pos + offset + Vector3(0, WorldGrid.WALL_HEIGHT / 2.0, 0)
	if dir == Vector2i(0, -1):
		wall.rotation_degrees = Vector3(90, 0, 0)
	elif dir == Vector2i(0, 1):
		wall.rotation_degrees = Vector3(-90, 0, 0)
	elif dir == Vector2i(1, 0):
		wall.rotation_degrees = Vector3(0, 0, 90)
	elif dir == Vector2i(-1, 0):
		wall.rotation_degrees = Vector3(0, 0, -90)
	add_child(wall)


func _dress_shop_door(cell: Vector2i, pos: Vector3) -> void:
	var is_center := cell.x < 0
	var accent := Color(0.85, 0.3, 0.3) if is_center else Color(0.3, 0.45, 0.85)

	var label := Label3D.new()
	label.text = "POKéMON CENTER" if is_center else "POKé MART"
	label.position = pos + Vector3(0, 2.4, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 56
	label.outline_size = 14
	label.modulate = accent.lightened(0.3)
	label.visibility_range_end = 9.0
	label.visibility_range_end_margin = 2.5
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(label)

	var accent_floor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WorldGrid.TILE_SIZE - 0.4, 0.02, WorldGrid.TILE_SIZE - 0.4)
	accent_floor.mesh = box
	accent_floor.material_override = _flat_material(accent)
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
	# Smaller, denser blotches than the first pass — at 3x tiling on a close
	# 3m wall, a handful of big overlapping circles read as one giant blob
	# rather than a hedge texture; more/smaller ones stay legible up close.
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
	for zone_id in _zone_first_row:
		var text := _sign_text(String(zone_id))
		if text == "":
			continue
		var row: int = _zone_first_row[zone_id]
		_sign(Vector3(0, 4.0, -row * WorldGrid.TILE_SIZE), text)


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
	if (cell.x + cell.y) % 3 != 0:
		return
	var side := 1 if (cell.y % 2 == 0) else -1
	if grid.kind_at(cell + Vector2i(side, 0)) != WorldGrid.TileKind.WALL:
		return
	# Offset must clear the wall plane (TILE_SIZE*0.5) by more than the prop's
	# own radius, or wide-based props (tree foliage cones up to ~2.1m across
	# at max scale) clip back through the wall into camera view.
	var pos := WorldGrid.world_pos(cell) + Vector3(side * (WorldGrid.TILE_SIZE * 0.5 + 2.5), 0, 0)
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
	var base := WorldGrid.world_pos(boss_cell)
	var wall_x := WorldGrid.TILE_SIZE * 0.5 - 0.08
	var back_z := -WorldGrid.TILE_SIZE * 0.35
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
		flame.material_override = mat
		flame.position = pos
		flame.rotation_degrees = Vector3(0, 0, 90.0 * side)
		flame.render_priority = -10
		add_child(flame)


func _build_markers(encounters: Array[Dictionary]) -> void:
	markers.clear()
	for i in encounters.size():
		var enc := encounters[i]
		var enemy_id := String(enc["enemy_id"])
		var display_name := String(Balance.enemies[enemy_id]["name"])
		if String(enc["kind"]) == "wild":
			display_name = "Wild " + display_name
		var marker := EncounterMarker.new()
		add_child(marker)
		marker.position = WorldGrid.world_pos(_encounter_cells[i])
		marker.setup(i, enemy_id, display_name)
		markers.append(marker)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	return mat
