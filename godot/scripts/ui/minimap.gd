class_name Minimap
extends Control
## Top-down HUD minimap: reveals visited tiles, shows player position/facing.
## Scrolls to keep the player centered — the corridor is much longer than any
## fixed window, so this shows a legible local neighborhood, not the whole map.

const CELL_PX := 16.0
const WINDOW_ROWS := 8
const WINDOW_COLS := 3
const MARGIN := 6.0

var grid: WorldGrid
var visited: Dictionary = {}   # Vector2i -> true
var player_cell := Vector2i.ZERO
var player_facing := 0


func _ready() -> void:
	custom_minimum_size = Vector2(
		(WINDOW_COLS * 2 + 1) * CELL_PX + MARGIN * 2,
		(WINDOW_ROWS * 2 + 1) * CELL_PX + MARGIN * 2,
	)


func mark_visited(cell: Vector2i, facing: int) -> void:
	visited[cell] = true
	player_cell = cell
	player_facing = facing
	queue_redraw()


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
			if not visited.has(cell):
				# Faint outline for known-but-unvisited grid slots so the map
				# still reads as a coherent grid, not scattered squares.
				if grid.tiles.has(cell):
					draw_rect(cell_rect, Color(1, 1, 1, 0.06))
				continue
			var kind: int = grid.kind_at(cell)
			draw_rect(cell_rect, _color_for_kind(cell, kind))

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
		WorldGrid.TileKind.ENCOUNTER:
			if grid.gate_encounter.has(cell) and int(grid.gate_encounter[cell]) < Run.encounter_index:
				return Color(0.35, 0.75, 0.35)
			return Color(0.9, 0.7, 0.25)
		WorldGrid.TileKind.SHOP_DOOR:
			return Color(0.85, 0.3, 0.3) if cell.x < 0 else Color(0.3, 0.45, 0.85)
		WorldGrid.TileKind.GYM_FLOOR:
			return Color(0.6, 0.55, 0.35)
		_:
			return Color(0.75, 0.75, 0.75)
