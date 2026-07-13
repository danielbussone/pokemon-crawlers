class_name CombatFX
extends Control
## Battle feedback layer: floating text, type icons in flight, screen flash, HP tween.

var _hit_flash: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_hit_flash = ColorRect.new()
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hit_flash.color = Color(0.85, 0.1, 0.1, 0.0)
	add_child(_hit_flash)


func popup(text: String, color: Color, screen_pos: Vector2, size: int = 22) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 5)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = screen_pos - Vector2(40, 10)
	label.pivot_offset = Vector2(40, size * 0.5)
	label.scale = Vector2(0.6, 0.6)
	add_child(label)

	var tween := create_tween()
	# Rise, with a quick "pop" scale-in running alongside.
	tween.tween_property(label, "position", label.position + Vector2(0, -44), 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "scale", Vector2(1, 1), 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.4)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


## Damage numbers grow and redden with magnitude, so big hits read as big.
func damage_popup(amount: int, screen_pos: Vector2) -> void:
	var size := 22 + clampi(amount, 0, 26)
	var color := Color(1.0, 0.55, 0.30) if amount < 12 else Color(1.0, 0.30, 0.24)
	popup("-%d" % amount, color, screen_pos, size)


func blocked_popup(screen_pos: Vector2) -> void:
	popup("BLOCKED", Color(0.75, 0.8, 0.95), screen_pos)


func missed_popup(screen_pos: Vector2) -> void:
	popup("MISS", Color(0.85, 0.85, 0.75), screen_pos)


func status_popup(label_text: String, screen_pos: Vector2) -> void:
	popup(label_text, Color(0.85, 0.65, 1.0), screen_pos)


func fly_effect(pokemon_type: String, from_screen: Vector2, to_screen: Vector2) -> Signal:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _type_icon_texture(pokemon_type)
	icon.position = from_screen - Vector2(16, 16)
	add_child(icon)

	var tween := create_tween()
	tween.tween_property(icon, "position", to_screen - Vector2(16, 16), 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(icon.queue_free)
	return tween.finished


func flash_player_hit(strength: float = 0.35) -> void:
	var tween := create_tween()
	tween.tween_property(_hit_flash, "color", Color(0.85, 0.1, 0.1, strength), 0.05)
	tween.tween_property(_hit_flash, "color", Color(0.85, 0.1, 0.1, 0.0), 0.25)


## Brief camera shake for impact. Safe during combat (the player is frozen, so
## nothing else is driving the camera). Intensity is in world units.
func screen_shake(intensity: float, duration: float = 0.22) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var base := cam.position
	var steps := 5
	var step := duration / float(steps + 1)
	var tween := create_tween()
	for i in steps:
		var off := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * intensity
		tween.tween_property(cam, "position", base + off, step)
	tween.tween_property(cam, "position", base, step)


func tween_enemy_hp(bar: ProgressBar, new_value: float, duration := 0.35) -> void:
	create_tween().tween_property(bar, "value", new_value, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func creature_screen_pos(marker: EncounterMarker) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return get_viewport().get_visible_rect().size * 0.5
	return cam.unproject_position(marker.global_position + Vector3(0, 1.2, 0))


func player_card_anchor() -> Vector2:
	var size := get_viewport().get_visible_rect().size
	return Vector2(size.x * 0.5, size.y * 0.9)


static func _type_icon_texture(pokemon_type: String) -> Texture2D:
	var color := CreatureFactory.type_color(pokemon_type)
	var img := PixelArt.new_canvas(32)
	match pokemon_type:
		"FIRE":
			PixelArt.icon_flame(img, color)
		"WATER":
			PixelArt.icon_water(img, color)
		"GRASS":
			PixelArt.icon_leaf(img, color)
		"POISON":
			PixelArt.icon_drip(img, color)
		"ROCK":
			PixelArt.icon_rock(img, color)
		_:
			PixelArt.icon_streaks(img, color)
	return PixelArt.to_texture(img)
