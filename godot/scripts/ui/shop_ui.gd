class_name ShopUI
extends CanvasLayer
## Pokémon Center OR Poké Mart window — which one depends on which door the
## player walked through (opens from shop-plaza doors once unlocked). The two
## buildings are separate in the world, so they're separate choices here too.

signal closed

const CENTER_SPLASH := "res://art/ui/pokemon_center_splash.jpg"
const MART_SPLASH := "res://art/ui/pokemart_splash.jpg"

var window: int = 1
var kind: String = "center"  # "center" or "mart"

var _gold_label: Label
var _inventory_label: Label
var _center_button: Button
var _item_buttons: Dictionary = {}  # item_id -> Button
var _feedback: Label


func _init(p_window: int, p_kind: String = "center") -> void:
	window = p_window
	kind = p_kind
	layer = 11


func _ready() -> void:
	_build_background()
	_build_shop_panel()
	_refresh()


func _load_interior_texture(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	# Fallback for dev runs before Godot has imported the JPEG.
	var img := Image.new()
	var err := img.load(path)
	if err != OK or img.is_empty():
		push_warning("ShopUI: could not load interior art at %s (err %s)" % [path, err])
		return null
	return ImageTexture.create_from_image(img)


func _build_background() -> void:
	var tex_path := CENTER_SPLASH if kind == "center" else MART_SPLASH
	var tex := _load_interior_texture(tex_path)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.08, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	if tex == null:
		return

	var img := TextureRect.new()
	img.texture = tex
	img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(img)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)


func _build_shop_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(420, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "POKéMON CENTER" if kind == "center" else "POKé MART"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if kind == "center":
		title.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45))
	else:
		title.add_theme_color_override("font_color", Color(0.5, 0.65, 0.95))
	vbox.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_gold_label)

	vbox.add_child(HSeparator.new())

	if kind == "center":
		var center_cfg: Dictionary = Balance.economy["center"]
		_center_button = Button.new()
		_center_button.text = "Nurse Joy: Full heal +%d Max HP — %dg" % [
			int(center_cfg["max_hp_bonus"]), int(center_cfg["cost"])]
		_center_button.custom_minimum_size = Vector2(0, 42)
		_center_button.pressed.connect(_on_center_pressed)
		vbox.add_child(_center_button)
	else:
		for item in ShopOps.items_for_shop_window(Balance, window):
			var item_id := String(item["id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var buy := Button.new()
			buy.text = "Buy — %dg" % int(item["cost"])
			buy.custom_minimum_size = Vector2(120, 34)
			buy.pressed.connect(_on_item_pressed.bind(item_id))
			row.add_child(buy)
			var desc := Label.new()
			desc.text = "%s — %s" % [String(item["name"]), CardText.item_description(item)]
			row.add_child(desc)
			vbox.add_child(row)
			_item_buttons[item_id] = buy

	vbox.add_child(HSeparator.new())

	_inventory_label = Label.new()
	vbox.add_child(_inventory_label)

	_feedback = Label.new()
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	vbox.add_child(_feedback)

	var leave := Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(0, 40)
	leave.pressed.connect(func(): closed.emit())
	vbox.add_child(leave)


func _on_center_pressed() -> void:
	if ShopOps.purchase_center(Run.player, Balance):
		_feedback.text = "Fully healed! Max HP is now %d." % Run.player.max_hp
	else:
		_feedback.text = "Not enough gold."
	_refresh()


func _on_item_pressed(item_id: String) -> void:
	var result := ShopOps.purchase_item(Run.player, item_id, Balance)
	if result["ok"]:
		_feedback.text = "Bought %s." % String(Balance.items[item_id]["name"])
	else:
		_feedback.text = String(result["reason"])
	_refresh()


func _refresh() -> void:
	var player := Run.player
	_gold_label.text = "Gold: %dg    HP: %d/%d" % [player.gold, player.hp, player.max_hp]

	var slots := int(Balance.economy["inventory"]["max_slots"])
	var names: Array[String] = []
	for item_id in player.inventory:
		names.append(String(Balance.items[item_id]["name"]))
	var bag_text := ", ".join(names)
	if names.is_empty():
		bag_text = "empty"
	_inventory_label.text = "Bag (%d/%d): %s" % [player.inventory.size(), slots, bag_text]

	if _center_button != null:
		_center_button.disabled = not ShopOps.can_afford(player, int(Balance.economy["center"]["cost"]))
	for item_id in _item_buttons:
		var item: Dictionary = Balance.items[item_id]
		var affordable := ShopOps.can_afford(player, int(item["cost"]))
		var has_room := Items.inventory_has_room(player, item_id, Balance)
		var button: Button = _item_buttons[item_id]
		button.disabled = not (affordable and has_room)
		if not has_room:
			button.tooltip_text = "No inventory room (max %d each, %d slots)" % [
				int(Balance.economy["inventory"]["max_per_item"]), slots]
		elif not affordable:
			button.tooltip_text = "Not enough gold"
		else:
			button.tooltip_text = ""
