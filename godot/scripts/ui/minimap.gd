class_name Minimap
extends Control
## Top-down HUD minimap with fog of war: only tiles the player has discovered
## are drawn. Walking a tile also reveals its 8 neighbors, so the walls
## (barriers) flanking explored corridors show up as you go. Everything
## undiscovered stays in the dark backing (fog). Scrolls to keep the player
## centered — the maze is much larger than any fixed window.

const CELL_PX := 16.0
const WINDOW_ROWS := 10
const WINDOW_COLS := 6
const MARGIN := 6.0

var grid: WorldGrid
var visited: Dictionary = {}    # Vector2i -> true (tiles actually walked)
var revealed: Dictionary = {}   # Vector2i -> true (walked tiles + their neighbors)
var player_cell := Vector2i.ZERO
var player_facing := 0


func _ready() -> void:
	custom_minimum_size = Vector2(
		(WINDOW_COLS * 2 + 1) * CELL_PX + MARGIN * 2,
		(WINDOW_ROWS * 2 + 1) * CELL_PX + MARGIN * 2,
	)


func mark_visited(cell: Vector2i, facing: int) -> void:
	visited[cell] = true
	_reveal_around(cell)
	player_cell = cell
	player_facing = facing
	queue_redraw()


## Discover a tile and the ring of cells around it, so barriers next to a
## walked corridor become visible (fog of war lifts locally as you explore).
func _reveal_around(cell: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			revealed[cell + Vector2i(dx, dy)] = true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.05, 0.85))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 2.0)

	if grid == null:
		return
	var center := size / 2.0
	var gap := 1.5

	for row in range(-WINDOW_ROWS, WINDOW_ROWS + 1):
		for col in range(-WINDOW_COLS, WINDOW_COLS + 1):
			var cell := player_cell + Vector2i(col, row)
			var screen_pos := center + Vector2(col * CELL_PX, row * CELL_PX) - Vector2(CELL_PX, CELL_PX) / 2.0
			var cell_rect := Rect2(screen_pos, Vector2(CELL_PX - gap, CELL_PX - gap))
			# Fog of war: undiscovered tiles (and off-map slots) stay dark.
			if not revealed.has(cell) or not grid.tiles.has(cell):
				continue
			var kind: int = grid.kind_at(cell)
			if kind == WorldGrid.TileKind.WALL:
				# Explored barrier: solid slab, plus a subtle edge so adjacent
				# walls read as a continuous wall rather than a blob.
				draw_rect(cell_rect, Color(0.28, 0.26, 0.32))
				draw_rect(cell_rect, Color(0.12, 0.11, 0.15), false, 1.0)
				continue
			var color := _color_for_kind(cell, kind)
			# Discovered-but-not-yet-walked tiles are dimmed (seen down a
			# corridor); tiles you've actually stepped on show at full color.
			if not visited.has(cell):
				color = color.darkened(0.45)
			draw_rect(cell_rect, color)

	var tri := PackedVector2Array([
		Vector2(0, -CELL_PX * 0.42), Vector2(CELL_PX * 0.32, CELL_PX * 0.34), Vector2(-CELL_PX * 0.32, CELL_PX * 0.34),
	])
	var xform := Transform2D(deg_to_rad(player_facing * 90.0), center)
	var rotated := PackedVector2Array()
	for p in tri:
		rotated.append(xform * p)
	draw_colored_polygon(rotated, Color(1.0, 0.95, 0.3))
	draw_polyline(rotated + PackedVector2Array([rotated[0]]), Color(0.3, 0.25, 0.05), 1.5)


func _color_for_kind(cell: Vector2i, kind: int) -> Color:
	match kind:
		WorldGrid.TileKind.ENCOUNTER, WorldGrid.TileKind.GATE_ENCOUNTER:
			if grid.gate_encounter.has(cell) and int(grid.gate_encounter[cell]) < Run.encounter_index:
				return Color(0.35, 0.75, 0.35)
			return Color(0.9, 0.7, 0.25)
		WorldGrid.TileKind.OPTIONAL_ENCOUNTER:
			return Color(0.55, 0.75, 0.9)
		WorldGrid.TileKind.SHOP_DOOR:
			var shop_kind := String(grid.tile_meta.get(cell, {}).get("shop_kind", "center"))
			return Color(0.85, 0.3, 0.3) if shop_kind == "center" else Color(0.3, 0.45, 0.85)
		WorldGrid.TileKind.GYM_DOOR:
			return Color(0.85, 0.65, 0.2)
		WorldGrid.TileKind.GYM_FLOOR:
			return Color(0.6, 0.55, 0.35)
		_:
			return Color(0.75, 0.75, 0.75)
