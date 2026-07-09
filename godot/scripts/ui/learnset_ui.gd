class_name LearnsetUI
extends CanvasLayer
## Post-victory "you learned a move" overlay. Upgrades show the previous card,
## an arrow, and the new card; net-new moves show a single card + "New move!".
## Purely informative — the deck changes are already applied by LearnsetOps.

signal done

var events: Array = []


func _init(p_events: Array) -> void:
	events = p_events
	layer = 12  # above DraftUI (11); shown first, before the draft


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var upgrades := 0
	for ev in events:
		if bool(ev.get("is_upgrade", false)):
			upgrades += 1
	var title := Label.new()
	if upgrades == events.size() and events.size() > 0:
		title.text = "Level up! %d move%s upgraded" % [events.size(), "" if events.size() == 1 else "s"]
	elif upgrades > 0:
		title.text = "Level up! Learned %d new move%s (%d upgraded)" % [
			events.size(), "" if events.size() == 1 else "s", upgrades]
	else:
		title.text = "Level up! Learned %d new move%s" % [events.size(), "" if events.size() == 1 else "s"]
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for ev in events:
		row.add_child(_learn_card(ev))

	var cont := Button.new()
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(0, 40)
	cont.pressed.connect(func(): done.emit())
	vbox.add_child(cont)


func _learn_card(ev: Dictionary) -> Control:
	var to_id := String(ev.get("to", ""))
	var is_upgrade := bool(ev.get("is_upgrade", false))
	var from_id := String(ev.get("from", ""))

	if is_upgrade and from_id != "":
		return _upgrade_row(from_id, to_id)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var card := _card_preview(to_id)
	col.add_child(card)

	var caption := Label.new()
	caption.text = "New move!"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	col.add_child(caption)
	return col


func _upgrade_row(from_id: String, to_id: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	row.add_child(_card_preview(from_id))

	var arrow := Label.new()
	arrow.text = ">"
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 36)
	arrow.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	row.add_child(arrow)

	row.add_child(_card_preview(to_id))
	return row


func _card_preview(card_id: String) -> Button:
	var card := CardWidget.build(card_id, "", Run.starter_id, false, "")
	card.disabled = true
	return card
