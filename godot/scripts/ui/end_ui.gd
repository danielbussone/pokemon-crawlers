class_name EndUI
extends CanvasLayer
## Run-over screen: Boulder Badge victory or defeat, with run stats and restart.

var win := false


func _init(p_win: bool) -> void:
	win = p_win
	layer = 15


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.1, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "BOULDER BADGE EARNED!" if win else "You blacked out..."
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.35) if win else Color(0.9, 0.4, 0.4))
	vbox.add_child(title)

	var subtitle := Label.new()
	if win:
		subtitle.text = "Brock is defeated — Rock Slide added to your deck.\nThe Kanto opening arc is complete."
	else:
		subtitle.text = "The run ends here. Pewter City will still be waiting."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	vbox.add_child(subtitle)

	var player := Run.player
	var stats := Label.new()
	stats.text = "Starter: %s    HP: %d/%d    Gold: %dg    Deck: %d cards    Center visits: %d" % [
		String(Balance.starters[Run.starter_id]["name"]),
		player.hp, player.max_hp, player.gold, Run.deck_size(), player.center_visits,
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 15)
	stats.modulate = Color(1, 1, 1, 0.8)
	vbox.add_child(stats)

	var again := Button.new()
	again.text = "Play Again"
	again.custom_minimum_size = Vector2(220, 48)
	again.add_theme_font_size_override("font_size", 20)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	var button_wrap := CenterContainer.new()
	button_wrap.add_child(again)
	vbox.add_child(button_wrap)
