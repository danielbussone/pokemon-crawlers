class_name RareCandyUI
extends CanvasLayer
## Rare Candy spend overlay (Phase 3): after a boss win, pick one eligible deck
## card to evolve, or save the token for later. Purely presents the choice; the
## deck change is applied by RareCandyOps.spend once the player picks.

signal done(pick: String)  # empty string = saved for later

const RareCandyOps = preload("res://scripts/core/rare_candy_ops.gd")

var _card_ids: Array[String] = []
var _tokens: int = 0


func _init(p_card_ids: Array[String], p_tokens: int) -> void:
	_card_ids = p_card_ids
	_tokens = p_tokens
	layer = 12  # above DraftUI (11); shown before the draft


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

	var title := Label.new()
	title.text = "Rare Candy! Evolve a card  (×%d in bag)" % _tokens
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for card_id in _card_ids:
		row.add_child(_evolve_choice(String(card_id)))

	var skip := Button.new()
	skip.text = "Save it for later"
	skip.custom_minimum_size = Vector2(0, 38)
	skip.pressed.connect(func(): done.emit(""))
	vbox.add_child(skip)


## A tappable from -> to preview; pressing anywhere in it picks that card.
func _evolve_choice(card_id: String) -> Control:
	var to_id := String(Balance.cards[card_id].get("evolves_to", ""))

	var button := Button.new()
	button.flat = true
	button.pressed.connect(func(): done.emit(card_id))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	row.add_child(_card_preview(card_id))

	var arrow := Label.new()
	arrow.text = ">"
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.add_theme_font_size_override("font_size", 36)
	arrow.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	row.add_child(arrow)

	row.add_child(_card_preview(to_id))
	return button


func _card_preview(card_id: String) -> Control:
	var card := CardWidget.build(card_id, "", Run.starter_id, false, "")
	card.disabled = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card
