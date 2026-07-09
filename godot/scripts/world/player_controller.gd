class_name PlayerController
extends Node3D
## First-person tile-grid rig (Grimrock/Etrian-Odyssey style): discrete
## forward/back/strafe moves and 90° turns, tweened between tile centers.
## No body, no physics — you ARE the camera. Personality lives in the HUD
## portrait instead of a visible player model.

signal tile_entered(cell: Vector2i, facing: int)

const MOVE_DURATION := 0.18
const TURN_DURATION := 0.15
const ACTIONS := ["move_forward", "move_back", "strafe_left", "strafe_right", "turn_left", "turn_right"]

var grid: WorldGrid
var grid_pos := Vector2i.ZERO
var facing: int = WorldGrid.Facing.NORTH
var frozen := false:
	set(value):
		frozen = value
		if frozen:
			_queued_action = ""

var _moving := false
var _queued_action := ""
var _camera: Camera3D
var _combat_pitch_tween: Tween

const COMBAT_LOOK_UP_DEG := 7.0


func setup(_starter_color: Color) -> void:
	add_to_group("player")
	_camera = Camera3D.new()
	_camera.position = Vector3(0, WorldGrid.EYE_HEIGHT, 0)
	_camera.current = true
	add_child(_camera)


func warp_to(cell: Vector2i, p_facing: int) -> void:
	grid_pos = cell
	facing = p_facing
	position = WorldGrid.world_pos(cell)
	rotation.y = WorldGrid.yaw_for_facing(facing)
	tile_entered.emit(grid_pos, facing)


func set_combat_view(active: bool) -> void:
	if _camera == null:
		return
	if _combat_pitch_tween != null and _combat_pitch_tween.is_valid():
		_combat_pitch_tween.kill()
	var target := deg_to_rad(-COMBAT_LOOK_UP_DEG) if active else 0.0
	_combat_pitch_tween = create_tween()
	_combat_pitch_tween.tween_property(_camera, "rotation:x", target, 0.22) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	if frozen or grid == null:
		return
	for action in ACTIONS:
		if Input.is_action_just_pressed(action):
			_handle_action(action)
			break


func _handle_action(action: String) -> void:
	if _moving:
		_queued_action = action
		return
	match action:
		"move_forward":
			_start_move(0)
		"move_back":
			_start_move(2)
		"strafe_left":
			_start_move(3)
		"strafe_right":
			_start_move(1)
		"turn_left":
			_start_turn(-1)
		"turn_right":
			_start_turn(1)


func _start_move(offset: int) -> void:
	var dir: Vector2i = WorldGrid.FACING_DIR[(facing + offset) % 4]
	var target: Vector2i = grid_pos + dir
	if not grid.is_walkable(target):
		_bump(dir)
		return
	_moving = true
	var tween := create_tween()
	tween.tween_property(self, "position", WorldGrid.world_pos(target), MOVE_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		grid_pos = target
		tile_entered.emit(grid_pos, facing)
		_finish_step()
	)


func _start_turn(dir: int) -> void:
	facing = posmod(facing + dir, 4)
	var target_yaw := WorldGrid.yaw_for_facing(facing)
	var delta_yaw := wrapf(target_yaw - rotation.y, -PI, PI)
	_moving = true
	var tween := create_tween()
	tween.tween_property(self, "rotation:y", rotation.y + delta_yaw, TURN_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		tile_entered.emit(grid_pos, facing)
		_finish_step()
	)


func _finish_step() -> void:
	_moving = false
	if _queued_action != "":
		var next := _queued_action
		_queued_action = ""
		_handle_action(next)


func _bump(dir: Vector2i) -> void:
	var original := position
	var nudge := Vector3(dir.x, 0, dir.y).normalized() * 0.15
	var tween := create_tween()
	tween.tween_property(self, "position", original + nudge, 0.08) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", original, 0.08) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
