class_name LearnsetUI
extends CanvasLayer
## Post-victory "you learned a move" overlay. Shows each learn event's new card
## (with an "Upgraded from X" / "New move!" caption) and a Continue button.
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var to_id := String(ev.get("to", ""))
	var card := CardWidget.build(to_id, "", Run.starter_id, false, "")
	card.disabled = true
	col.add_child(card)

	var caption := Label.new()
	if bool(ev.get("is_upgrade", false)):
		var from_id := String(ev.get("from", ""))
		var from_name := String(Balance.cards[from_id]["name"]) if Balance.cards.has(from_id) else from_id
		caption.text = "%s → %s" % [from_name, String(Balance.cards[to_id]["name"])]
	else:
		caption.text = "New move!"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	col.add_child(caption)
	return col
