class_name EncounterMarker
extends Node3D
## One encounter tile's visuals: creature sprite, name label, pulsing ring.
## Physics-free — the grid (WorldGrid.gate_encounter) decides whether the
## player can reach this tile; PlayerController.tile_entered decides when
## the fight actually starts.

const DUO_GAP := 0.04  # world-space gap between trainer and partner opaque edges

var encounter_index := -1
var enemy_id := ""
var active := false
var cleared := false

var _sprite_group: Node3D
var _sprites: Array[Sprite3D] = []
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _t := 0.0
var _creature_base_y := 0.0
var _flash_tween: Tween
var _lunge_tween: Tween
var _lunging := false


func setup(p_index: int, p_enemy_id: String, display_name: String) -> void:
	encounter_index = p_index
	enemy_id = p_enemy_id

	_sprite_group = Node3D.new()
	add_child(_sprite_group)
	_sprites.clear()

	var companion := _companion_species_id(p_enemy_id)
	if companion != "":
		var trainer := CreatureFactory.build_sprite(p_enemy_id)
		_sprite_group.add_child(trainer)
		_sprites.append(trainer)

		var partner := CreatureFactory.build_partner_sprite(companion)
		_sprite_group.add_child(partner)
		_sprites.append(partner)
		_layout_trainer_duo(trainer, partner)
	else:
		var solo := CreatureFactory.build_sprite(p_enemy_id)
		_sprite_group.add_child(solo)
		_sprites.append(solo)

	_creature_base_y = _sprite_group.position.y

	_label = Label3D.new()
	_label.text = display_name
	_label.position = Vector3(0, 2.6, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.outline_size = 14
	_label.modulate = Color(1, 1, 1, 0.9)
	# Fade out with distance so labels down a straight corridor don't all
	# converge/overlap into illegible text at the vanishing point.
	_label.visibility_range_end = 9.0
	_label.visibility_range_end_margin = 2.5
	_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_label)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.1
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.position = Vector3(0, 0.05, 0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.6)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = _ring_mat
	add_child(_ring)


static func _companion_species_id(p_enemy_id: String) -> String:
	if p_enemy_id == "brock":
		return "onix"
	if p_enemy_id.begins_with("rival_"):
		return p_enemy_id.trim_prefix("rival_")
	if p_enemy_id.begins_with("bug_catcher_"):
		return p_enemy_id.trim_prefix("bug_catcher_")
	return ""


static func _layout_trainer_duo(trainer: Sprite3D, partner: Sprite3D) -> void:
	CreatureFactory.center_sprite_on_opaque(trainer)
	CreatureFactory.center_sprite_on_opaque(partner)
	var half_t := CreatureFactory.sprite_opaque_half_width(trainer)
	var half_p := CreatureFactory.sprite_opaque_half_width(partner)
	var span := half_t + DUO_GAP + half_p
	trainer.position.x = -span * 0.5
	partner.position.x = span * 0.5


func set_active(value: bool) -> void:
	active = value and not cleared
	if cleared:
		return
	if active:
		_ring_mat.albedo_color = Color(1.0, 0.85, 0.25, 0.85)
		_label.modulate = Color(1, 1, 1, 1)
	else:
		_ring_mat.albedo_color = Color(0.5, 0.5, 0.5, 0.35)
		_label.modulate = Color(1, 1, 1, 0.55)


func clear() -> void:
	cleared = true
	active = false
	_ring.visible = false
	_label.visible = false
	var tween := create_tween()
	tween.tween_property(_sprite_group, "scale", Vector3(0.01, 0.01, 0.01), 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _sprite_group.visible = false)


func hit_flash() -> void:
	if cleared:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	for spr in _sprites:
		spr.modulate = Color(1, 1, 1, 1)
	_flash_tween.set_parallel(true)
	for spr in _sprites:
		_flash_tween.tween_property(spr, "modulate", Color(1.0, 0.35, 0.35, 1.0), 0.06) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.chain().set_parallel(true)
	for spr in _sprites:
		_flash_tween.tween_property(spr, "modulate", Color(1, 1, 1, 1), 0.18) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func attack_lunge() -> void:
	if cleared:
		return
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	_lunging = true
	var original := _sprite_group.position
	var nudge := Vector3(0, 0, 0.15)
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(_sprite_group, "position", original + nudge, 0.08) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(_sprite_group, "position", original, 0.08) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_lunge_tween.tween_callback(func(): _lunging = false)


func _process(delta: float) -> void:
	if cleared:
		return
	_t += delta
	if not _lunging:
		_sprite_group.position.y = _creature_base_y + (sin(_t * 2.0 + encounter_index) * 0.5 + 0.5) * 0.1
	if active:
		var pulse := 0.6 + 0.3 * sin(_t * 4.0)
		_ring_mat.albedo_color = Color(1.0, 0.85, 0.25, pulse)
