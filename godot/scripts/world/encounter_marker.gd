class_name EncounterMarker
extends Node3D
## One encounter tile's visuals: creature sprite, name label, pulsing ring.
## Physics-free — the grid (WorldGrid.gate_encounter) decides whether the
## player can reach this tile; PlayerController.tile_entered decides when
## the fight actually starts.
##
## Markers read at a glance by kind:
##   OPTIONAL — cool blue ring, dimmed label; skippable wild.
##   GATE     — warm gold ring + arch signage; mandatory funnel fight.
##   BOSS      — fiery ring + arch signage + "GYM LEADER" banner.

## Visual/behavioral class of an encounter marker.
enum MarkerKind { OPTIONAL, GATE, BOSS }

const DUO_GAP := 0.04  # world-space gap between trainer and partner opaque edges

var encounter_index := -1
var enemy_id := ""
var marker_kind := MarkerKind.OPTIONAL
var active := false
var cleared := false

var _sprite_group: Node3D
var _sprites: Array[Sprite3D] = []
var _label: Label3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _signage: Node3D
var _signage_mats: Array[StandardMaterial3D] = []
var _barrier_mat: StandardMaterial3D
var _t := 0.0
var _creature_base_y := 0.0
var _flash_tween: Tween
var _lunge_tween: Tween
var _lunging := false


func setup(p_index: int, p_enemy_id: String, display_name: String,
		p_kind: int = MarkerKind.OPTIONAL) -> void:
	encounter_index = p_index
	enemy_id = p_enemy_id
	marker_kind = p_kind

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
	_ring_mat.albedo_color = _base_color()
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Gates/bosses glow so they read as "must fight" even at a distance; wilds
	# stay flat so they recede as skippable set dressing.
	if marker_kind != MarkerKind.OPTIONAL:
		_ring_mat.emission_enabled = true
		_ring_mat.emission = _base_color()
		_ring_mat.emission_energy_multiplier = 1.4
	_ring.material_override = _ring_mat
	add_child(_ring)

	if marker_kind != MarkerKind.OPTIONAL:
		_build_signage()

	# Start dimmed; main.gd calls set_active() on the current gate to light it.
	set_active(false)


## Per-kind accent color shared by the ring, signage and barrier.
func _base_color() -> Color:
	match marker_kind:
		MarkerKind.GATE:
			return Color(1.0, 0.78, 0.25)
		MarkerKind.BOSS:
			return Color(1.0, 0.45, 0.2)
		_:
			return Color(0.45, 0.7, 0.95)


## Arch + banner that frames a gate/boss so it reads as a blocking funnel
## fight from any approach angle. A translucent pane fills the arch while the
## fight is pending and vanishes with the rest of the marker once cleared.
func _build_signage() -> void:
	_signage = Node3D.new()
	add_child(_signage)
	_signage_mats.clear()

	var accent := _base_color()
	var post_w := 0.16
	var span := 1.35        # half-distance between the two posts
	var post_h := 2.35
	var beam_y := post_h + 0.12

	for side in [-1.0, 1.0]:
		_signage.add_child(_arch_box(
				Vector3(side * span, post_h * 0.5, 0.0),
				Vector3(post_w, post_h, post_w), accent))
	# Cross beam joining the posts.
	_signage.add_child(_arch_box(
			Vector3(0.0, beam_y, 0.0),
			Vector3(span * 2.0 + post_w, 0.22, post_w), accent))

	# Translucent "barrier" pane inside the arch — a soft visual gate.
	var barrier := MeshInstance3D.new()
	var pane := QuadMesh.new()
	pane.size = Vector2(span * 2.0, post_h)
	barrier.mesh = pane
	barrier.position = Vector3(0.0, post_h * 0.5, 0.0)
	_barrier_mat = StandardMaterial3D.new()
	_barrier_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.14)
	_barrier_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_barrier_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_barrier_mat.emission_enabled = true
	_barrier_mat.emission = accent
	_barrier_mat.emission_energy_multiplier = 0.5
	barrier.material_override = _barrier_mat
	_signage.add_child(barrier)

	var banner := Label3D.new()
	banner.text = "GYM LEADER" if marker_kind == MarkerKind.BOSS else "TRAINER BATTLE"
	banner.position = Vector3(0.0, beam_y + 0.5, 0.0)
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.font_size = 44
	banner.outline_size = 12
	banner.modulate = accent.lightened(0.25)
	banner.visibility_range_end = 11.0
	banner.visibility_range_end_margin = 3.0
	banner.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_signage.add_child(banner)


func _arch_box(local_pos: Vector3, box_size: Vector3, color: Color) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	mat.roughness = 0.6
	inst.material_override = mat
	inst.position = local_pos
	_signage_mats.append(mat)
	return inst


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
	var base := _base_color()
	if active:
		_ring_mat.albedo_color = Color(base.r, base.g, base.b, 0.9)
		if _ring_mat.emission_enabled:
			_ring_mat.emission_energy_multiplier = 2.0
		_label.modulate = Color(1, 1, 1, 1)
	else:
		# Wilds recede (dim, no glow boost); pending gates stay clearly lit.
		var ring_a := 0.32 if marker_kind == MarkerKind.OPTIONAL else 0.6
		_ring_mat.albedo_color = Color(base.r, base.g, base.b, ring_a)
		if _ring_mat.emission_enabled:
			_ring_mat.emission_energy_multiplier = 1.2
		var label_a := 0.5 if marker_kind == MarkerKind.OPTIONAL else 0.85
		_label.modulate = Color(1, 1, 1, label_a)
	_apply_signage_intensity()


func _apply_signage_intensity() -> void:
	if _signage == null:
		return
	var boost := 1.7 if active else 0.9
	for mat in _signage_mats:
		mat.emission_energy_multiplier = boost
	if _barrier_mat != null:
		_barrier_mat.emission_energy_multiplier = 0.9 if active else 0.4


func clear() -> void:
	cleared = true
	active = false
	_ring.visible = false
	_label.visible = false
	if _signage != null:
		var sig_tween := create_tween()
		sig_tween.tween_property(_signage, "scale", Vector3(0.01, 1.0, 0.01), 0.35) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		sig_tween.tween_callback(func(): _signage.visible = false)
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
		var base := _base_color()
		_ring_mat.albedo_color = Color(base.r, base.g, base.b, pulse)
