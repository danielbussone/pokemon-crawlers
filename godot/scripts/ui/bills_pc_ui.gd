class_name BillsPcUI
extends CanvasLayer
## Bill's PC (Phase 4): deposit active-deck cards into storage and withdraw them
## back, at a Pokémon Center after the first badge. Each deposit/withdraw is a
## paid, limited "swap" (see PcOps). Opens on top of the Center shop panel.

signal closed

const PcOps = preload("res://scripts/core/pc_ops.gd")
const PC_CARD_SIZE := Vector2(104, 146)

var _status: Label
var _feedback: Label
var _deck_col: VBoxContainer
var _box_col: VBoxContainer


func _init() -> void:
	layer = 12  # above ShopUI (11)


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.94)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(760, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "BILL'S PC"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status)

	_feedback = Label.new()
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_feedback)

	vbox.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	vbox.add_child(columns)
	_deck_col = _make_column(columns, "Active Deck")
	var divider := VSeparator.new()
	columns.add_child(divider)
	_box_col = _make_column(columns, "Box")

	var leave := Button.new()
	leave.text = "Close"
	leave.custom_minimum_size = Vector2(0, 40)
	leave.pressed.connect(func(): closed.emit())
	vbox.add_child(leave)

	_refresh()


## A titled, fixed-size scrolling area for a card flow; returns the inner flow
## container that _refresh repopulates.
func _make_column(parent: HBoxContainer, header: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 6)
	parent.add_child(wrap)

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 18)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.name = "Header"
	wrap.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(360, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wrap.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	flow.name = "Flow"
	scroll.add_child(flow)

	# Stash header text prefix so _refresh can update the count.
	wrap.set_meta("header", header)
	return wrap


func _refresh() -> void:
	var player := Run.player
	var remaining := PcOps.swaps_remaining(player, Balance)
	var fee := PcOps.swap_fee(Balance)
	var limit := PcOps.swap_limit(Balance)
	_status.text = "Swaps left: %d/%d    Fee: %dg/swap    Gold: %dg    (deck min %d)" % [
		remaining, limit, fee, player.gold, PcOps.min_deck_size(Balance)]

	var deck_cards := PcOps.active_deck_cards(player)
	var can_deposit := remaining > 0 and player.gold >= fee \
			and PcOps.active_deck_size(player) > PcOps.min_deck_size(Balance)
	_fill_column(_deck_col, deck_cards, can_deposit, _on_deposit,
			"Deposit into Box", "No swaps / gold, or at min deck size")

	var can_withdraw := remaining > 0 and player.gold >= fee
	_fill_column(_box_col, player.pc_box, can_withdraw, _on_withdraw,
			"Withdraw to Deck", "No swaps left or not enough gold")


func _fill_column(wrap: VBoxContainer, cards: Array, enabled: bool,
		on_click: Callable, action_tip: String, blocked_tip: String) -> void:
	var head: Label = wrap.get_node("Header")
	head.text = "%s (%d)" % [String(wrap.get_meta("header")), cards.size()]

	var flow: HFlowContainer = wrap.get_node("Scroll/Flow")
	for child in flow.get_children():
		child.queue_free()

	if cards.is_empty():
		var empty := Label.new()
		empty.text = "— empty —"
		empty.modulate = Color(1, 1, 1, 0.5)
		flow.add_child(empty)
		return

	for card_id in cards:
		var cid := String(card_id)
		var tip := action_tip if enabled else blocked_tip
		var card := CardWidget.build(cid, "", Run.starter_id, not enabled, tip, PC_CARD_SIZE)
		if enabled:
			card.pressed.connect(func(): on_click.call(cid))
		flow.add_child(card)


func _on_deposit(card_id: String) -> void:
	var result := PcOps.deposit(Run.player, card_id, Balance)
	_feedback.text = "Stored %s." % String(Balance.cards[card_id]["name"]) if result["ok"] \
			else String(result["reason"])
	_refresh()


func _on_withdraw(card_id: String) -> void:
	var result := PcOps.withdraw(Run.player, card_id, Balance)
	_feedback.text = "Withdrew %s." % String(Balance.cards[card_id]["name"]) if result["ok"] \
			else String(result["reason"])
	_refresh()
