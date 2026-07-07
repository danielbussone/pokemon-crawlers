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


func popup(text: String, color: Color, screen_pos: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = screen_pos - Vector2(40, 10)
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -40), 0.9) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)


func damage_popup(amount: int, screen_pos: Vector2) -> void:
	popup("-%d" % amount, Color(1.0, 0.45, 0.35), screen_pos)


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


func flash_player_hit() -> void:
	var tween := create_tween()
	tween.tween_property(_hit_flash, "color", Color(0.85, 0.1, 0.1, 0.35), 0.05)
	tween.tween_property(_hit_flash, "color", Color(0.85, 0.1, 0.1, 0.0), 0.25)


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
