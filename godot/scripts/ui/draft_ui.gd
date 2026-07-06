class_name DraftUI
extends CanvasLayer
## Post-victory card draft: pick one of the offered cards or skip.

signal done(pick: String)  # empty string = skipped

var options: Array[String] = []


func _init(p_options: Array[String]) -> void:
	options = p_options
	layer = 11


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
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

	var title := Label.new()
	title.text = "Victory! Add a card to your deck:"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for card_id in options:
		var picked_id := String(card_id)
		var button := CardWidget.build(picked_id, "", Run.starter_id, false, "")
		button.pressed.connect(func(): done.emit(picked_id))
		row.add_child(button)

	var skip := Button.new()
	skip.text = "Skip (keep deck lean)"
	skip.custom_minimum_size = Vector2(0, 38)
	skip.pressed.connect(func(): done.emit(""))
	vbox.add_child(skip)
