class_name StarterUI
extends CanvasLayer
## Full-screen starter selection at run start, plus a trainer appearance
## (boy/girl) toggle — the appearance drives the HUD portrait, not the deck.

signal picked(starter_id: String, appearance_id: String)

var _appearance := "boy"


func _ready() -> void:
	layer = 20
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "POKEMON CRAWLERS"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var appearance_label := Label.new()
	appearance_label.text = "Choose your trainer:"
	appearance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	appearance_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(appearance_label)

	var appearance_row := HBoxContainer.new()
	appearance_row.add_theme_constant_override("separation", 12)
	appearance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(appearance_row)

	var group := ButtonGroup.new()
	for appearance_id in ["boy", "girl"]:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = appearance_id == _appearance
		button.custom_minimum_size = Vector2(96, 120)
		var art := TextureRect.new()
		art.texture = PortraitFactory.build(appearance_id)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.offset_bottom = -18
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
		var label := Label.new()
		label.text = appearance_id.capitalize()
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
		button.pressed.connect(func(): _appearance = appearance_id)
		appearance_row.add_child(button)

	var subtitle := Label.new()
	subtitle.text = "Kanto Opening Arc — Route 1 to the Boulder Badge\nChoose your starter:"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	vbox.add_child(subtitle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for starter_id in ["bulbasaur", "squirtle", "charmander"]:
		var starter: Dictionary = Balance.starters[starter_id]
		var ptype := String(Run.STARTER_TYPES[starter_id])
		var color := CreatureFactory.type_color(ptype)

		var button := Button.new()
		button.custom_minimum_size = Vector2(240, 260)
		button.text = ""
		button.pressed.connect(func(): picked.emit(starter_id, _appearance))
		row.add_child(button)

		var starter_vbox := VBoxContainer.new()
		starter_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		starter_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		starter_vbox.add_theme_constant_override("separation", 4)
		button.add_child(starter_vbox)

		var art := TextureRect.new()
		art.texture = CreatureArt.get_texture(starter_id)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.custom_minimum_size = Vector2(0, 110)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		starter_vbox.add_child(art)

		var label := Label.new()
		label.text = "%s\n[%s]\n\n%s" % [String(starter["name"]), ptype, _deck_summary(starter)]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", color.lightened(0.35))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		starter_vbox.add_child(label)

	var hint := Label.new()
	hint.text = "Charmander is intentionally the hard mode for this slice."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(hint)


func _deck_summary(starter: Dictionary) -> String:
	var counts := {}
	for card_id in starter["deck"]:
		var card_name := String(Balance.cards[card_id]["name"])
		counts[card_name] = int(counts.get(card_name, 0)) + 1
	var parts: Array[String] = []
	for card_name in counts:
		if counts[card_name] > 1:
			parts.append("%s x%d" % [card_name, counts[card_name]])
		else:
			parts.append(card_name)
	return "\n".join(parts)
