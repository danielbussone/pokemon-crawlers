class_name StarterUI
extends CanvasLayer
## Full-screen starter selection at run start, plus a trainer appearance
## (boy/girl) toggle — the appearance drives the HUD portrait, not the deck.

signal picked(starter_id: String, appearance_id: String)

const TRAINER_BTN_SIZE := Vector2(180, 210)
const TRAINER_ART_SIZE := Vector2(140, 150)
const STARTER_BTN_SIZE := Vector2(260, 320)

var _appearance := "boy"


func _ready() -> void:
	layer = 20
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(top_spacer)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 24)
	outer.add_child(vbox)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(bottom_spacer)

	var title := Label.new()
	title.text = "POKEMON CRAWLERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(title, 56)
	vbox.add_child(title)

	var appearance_label := Label.new()
	appearance_label.text = "Choose your trainer:"
	appearance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(appearance_label, 24)
	vbox.add_child(appearance_label)

	var appearance_row := _centered_hbox()
	vbox.add_child(appearance_row)
	var appearance_inner: HBoxContainer = appearance_row.get_child(1)
	appearance_inner.add_theme_constant_override("separation", 16)

	var group := ButtonGroup.new()
	for appearance_id in ["boy", "girl"]:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = appearance_id == _appearance
		button.custom_minimum_size = TRAINER_BTN_SIZE
		button.pressed.connect(func(): _appearance = appearance_id)
		appearance_inner.add_child(button)

		var inner := VBoxContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("separation", 8)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		button.add_child(inner)

		var art_center := CenterContainer.new()
		art_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art_center.custom_minimum_size = Vector2(0, 158)
		inner.add_child(art_center)

		var art := TextureRect.new()
		art.texture = PortraitFactory.build(appearance_id)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		art.custom_minimum_size = TRAINER_ART_SIZE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_center.add_child(art)

		var label := Label.new()
		label.text = appearance_id.capitalize()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_label(label, 20)
		inner.add_child(label)

	var subtitle := Label.new()
	subtitle.text = "Kanto Opening Arc — Route 1 to the Boulder Badge\nChoose your starter:"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(subtitle, 22)
	vbox.add_child(subtitle)

	var row := _centered_hbox()
	vbox.add_child(row)
	var starter_inner: HBoxContainer = row.get_child(1)
	starter_inner.add_theme_constant_override("separation", 20)

	for starter_id in ["bulbasaur", "squirtle", "charmander"]:
		var starter: Dictionary = Balance.starters[starter_id]
		var ptype := String(Run.STARTER_TYPES[starter_id])
		var color := CreatureFactory.type_color(ptype)

		var button := Button.new()
		button.custom_minimum_size = STARTER_BTN_SIZE
		button.text = ""
		button.pressed.connect(func(): picked.emit(starter_id, _appearance))
		starter_inner.add_child(button)

		var starter_vbox := VBoxContainer.new()
		starter_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		starter_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		starter_vbox.add_theme_constant_override("separation", 8)
		starter_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		button.add_child(starter_vbox)

		var art_center := CenterContainer.new()
		art_center.custom_minimum_size = Vector2(0, 128)
		art_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		starter_vbox.add_child(art_center)

		var art := TextureRect.new()
		art.texture = CreatureArt.get_texture(starter_id)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		art.custom_minimum_size = Vector2(118, 118)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_center.add_child(art)

		var name_label := Label.new()
		name_label.text = String(starter["name"])
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_label(name_label, 24, color.lightened(0.45))
		starter_vbox.add_child(name_label)

		var type_label := Label.new()
		type_label.text = "[%s]" % ptype
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_label(type_label, 18, color.lightened(0.3))
		starter_vbox.add_child(type_label)

		var deck_label := Label.new()
		deck_label.text = _deck_summary(starter)
		deck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		deck_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		deck_label.custom_minimum_size = Vector2(228, 0)
		deck_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		deck_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_label(deck_label, 18, color.lightened(0.45))
		starter_vbox.add_child(deck_label)

	var hint := Label.new()
	hint.text = "Charmander is intentionally the hard mode for this slice."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(720, 0)
	hint.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_label(hint, 18, Color(0.9, 0.92, 0.96))
	vbox.add_child(hint)


static func _centered_hbox() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := HBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	row.add_child(inner)
	row.add_child(right)
	return row


static func _style_label(label: Label, font_size: int, color: Color = Color.WHITE) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.08, 0.95))


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
