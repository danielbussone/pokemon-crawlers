extends Node3D
## Game flow: starter pick → 3D exploration → combat overlays → draft/shop →
## Boulder Badge or defeat. The world and all UI are generated in code.

const LearnsetUI = preload("res://scripts/ui/learnset_ui.gd")

var world: WorldMapBuilder
var player: PlayerController
var hud: GameHUD
var combat_ui: CombatUI
var current_marker: EncounterMarker
var _shop_open := false
var _shop_cooldown_end_ms := 0
var _shop_entry_cell := Vector2i.ZERO
var _starting := false


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--simcheck"):
		var engage := SimCheck.DEFAULT_ENGAGEMENT
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--engage="):
				engage = clampf(float(a.substr("--engage=".length())), 0.0, 1.0)
		SimCheck.run_batch(300, Run, Balance, engage)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--visualcheck"):
		await _run_visualcheck()
		get_tree().quit()
		return
	_build_environment()
	var starter_ui := StarterUI.new()
	add_child(starter_ui)
	starter_ui.picked.connect(_on_starter_picked.bind(starter_ui))


func _process(_delta: float) -> void:
	if hud != null and player != null and world != null:
		hud.set_zone(world.zone_name_for_cell(player.grid_pos))


# --- Setup ---

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_material.sky_horizon_color = Color(0.75, 0.82, 0.88)
	sky_material.ground_bottom_color = Color(0.3, 0.35, 0.3)
	sky_material.ground_horizon_color = Color(0.68, 0.72, 0.68)
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.8, 0.85)
	env.fog_density = 0.004
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)


func _on_starter_picked(starter_id: String, appearance_id: String, starter_ui: StarterUI) -> void:
	if _starting:
		return
	_starting = true
	starter_ui.visible = false
	starter_ui.queue_free()
	await get_tree().process_frame
	_boot_game(starter_id, appearance_id)


func _boot_game(starter_id: String, appearance_id: String) -> void:
	Run.start_run(starter_id, appearance_id)

	world = WorldMapBuilder.new()
	add_child(world)
	world.build(Run.encounters)
	world.encounter_triggered.connect(_on_encounter_triggered)
	world.shop_entered.connect(_on_shop_entered)

	player = PlayerController.new()
	add_child(player)
	player.setup(CreatureFactory.type_color(Run.player.ptype))
	player.grid = world.grid
	player.tile_entered.connect(world._on_tile_entered)
	world.set_encounter_triggers_enabled(false)
	player.warp_to(world.spawn_cell, WorldGrid.Facing.NORTH)
	world.set_encounter_triggers_enabled(true)

	hud = GameHUD.new()
	add_child(hud)
	hud.minimap.grid = world.grid
	player.tile_entered.connect(hud.minimap.mark_visited)
	hud.minimap.mark_visited(player.grid_pos, player.facing)
	hud.toast("Defeat all 13 encounters on the road to Brock!")

	world.set_active_marker(Run.active_marker_index())


# --- Combat flow ---

func _on_encounter_triggered(marker: EncounterMarker) -> void:
	if combat_ui != null or Run.run_over:
		return
	current_marker = marker
	_snap_player_toward_marker(marker)
	player.frozen = true
	hud.set_minimap_visible(false)
	hud.set_party_above_combat(true)
	player.set_combat_view(true)
	var ctx := Run.begin_combat_at(current_marker.encounter_index)
	combat_ui = CombatUI.new(ctx, marker)
	add_child(combat_ui)
	combat_ui.finished.connect(_on_combat_finished)


func _snap_player_toward_marker(marker: EncounterMarker) -> void:
	var enc_cell := world.encounter_cell(marker.encounter_index)
	var delta := enc_cell - player.grid_pos
	if delta == Vector2i.ZERO:
		return
	var facing := WorldGrid.Facing.NORTH
	if abs(delta.x) > abs(delta.y):
		facing = WorldGrid.Facing.EAST if delta.x > 0 else WorldGrid.Facing.WEST
	elif delta.y != 0:
		facing = WorldGrid.Facing.SOUTH if delta.y > 0 else WorldGrid.Facing.NORTH
	player.facing = facing
	player.rotation.y = WorldGrid.yaw_for_facing(facing)


func _on_combat_finished(win: bool) -> void:
	combat_ui.queue_free()
	combat_ui = null
	player.set_combat_view(false)
	hud.set_party_above_combat(false)

	if not win:
		Run.after_loss()
		add_child(EndUI.new(false))
		return

	world.clear_marker(current_marker.encounter_index)
	var result := Run.after_win()
	hud.refresh()

	if int(result["gold"]) > 0:
		hud.toast("+%dg" % int(result["gold"]))
	if int(result["xp_gained"]) > 0:
		hud.toast("+%d XP" % int(result["xp_gained"]))
	if int(result["shop_window"]) > 0:
		hud.toast("Shops unlocked — step up to a door to browse.")

	_after_win_learn(result)


## Chain: combat win -> learnset (add/replace) -> draft -> post-fight.
func _after_win_learn(result: Dictionary) -> void:
	var learn_events: Array = result.get("learn_events", [])
	if learn_events.is_empty():
		_offer_draft(result)
		return
	var learn_ui := LearnsetUI.new(learn_events)
	add_child(learn_ui)
	learn_ui.done.connect(_on_learn_done.bind(learn_ui, result))


func _on_learn_done(learn_ui: LearnsetUI, result: Dictionary) -> void:
	learn_ui.queue_free()
	hud.refresh()
	_offer_draft(result)


func _offer_draft(result: Dictionary) -> void:
	var options: Array[String] = result["draft_options"]
	if not options.is_empty():
		var draft := DraftUI.new(options)
		add_child(draft)
		draft.done.connect(_on_draft_done.bind(draft, result))
	else:
		_post_fight(result)


func _on_draft_done(pick: String, draft: DraftUI, result: Dictionary) -> void:
	draft.queue_free()
	if pick != "":
		Rewards.apply_draft_pick(Run.player, pick)
		hud.toast("Added %s to your deck." % String(Balance.cards[pick]["name"]))
	hud.refresh()
	_post_fight(result)


func _post_fight(result: Dictionary) -> void:
	if bool(result["run_complete"]):
		add_child(EndUI.new(true))
		return
	hud.set_minimap_visible(true)
	world.set_active_marker(Run.active_marker_index())
	player.frozen = false


# --- Shops ---

func _on_shop_entered(window: int, kind: String) -> void:
	if _shop_open or combat_ui != null or Run.run_over or player.frozen:
		return
	if Time.get_ticks_msec() < _shop_cooldown_end_ms:
		return
	if Run.unlocked_shop_window < window:
		_shop_cooldown_end_ms = Time.get_ticks_msec() + 2000
		hud.toast("Closed — beat this stage's trainer first.")
		return

	_shop_open = true
	_shop_entry_cell = player.grid_pos
	player.frozen = true
	world.visible = false
	hud.set_minimap_visible(false)
	var shop := ShopUI.new(window, kind)
	add_child(shop)
	shop.closed.connect(_on_shop_closed.bind(shop))


func _on_shop_closed(shop: ShopUI) -> void:
	shop.queue_free()
	_shop_open = false
	_shop_cooldown_end_ms = Time.get_ticks_msec() + 1500
	world.visible = true
	hud.set_minimap_visible(true)
	var approach := world.shop_approach_facing(_shop_entry_cell)
	player.warp_to(_shop_entry_cell, approach)
	player.frozen = false
	hud.refresh()


## Internal-screenshot dev harness — captures real rendered frames via
## Viewport.get_texture() from inside the process, so visual regressions can
## be checked without relying on OS-level screen capture (unreliable/blocked
## in some remote-desktop sessions). See godot/README.md "Visual smoke test".
const SHOT_DIR := "res://.debug_screenshots/"


func _run_visualcheck() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_build_environment()

	var starter_probe := StarterUI.new()
	add_child(starter_probe)
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("00_starter_select.png")
	starter_probe.queue_free()
	await get_tree().process_frame

	var args := OS.get_cmdline_user_args()
	var starter_id := "squirtle"
	var appearance_id := "boy"
	for a in args:
		if a.begins_with("--starter="):
			starter_id = a.substr("--starter=".length())
		elif a.begins_with("--appearance="):
			appearance_id = a.substr("--appearance=".length())
	Run.start_run(starter_id, appearance_id)

	world = WorldMapBuilder.new()
	add_child(world)
	world.build(Run.encounters)
	world.encounter_triggered.connect(_on_encounter_triggered)
	world.shop_entered.connect(_on_shop_entered)

	player = PlayerController.new()
	add_child(player)
	player.setup(CreatureFactory.type_color(Run.player.ptype))
	player.grid = world.grid
	player.tile_entered.connect(world._on_tile_entered)
	world.set_encounter_triggers_enabled(false)
	player.warp_to(world.spawn_cell, WorldGrid.Facing.NORTH)
	world.set_encounter_triggers_enabled(true)

	hud = GameHUD.new()
	add_child(hud)
	hud.minimap.grid = world.grid
	player.tile_entered.connect(hud.minimap.mark_visited)
	world.set_active_marker(Run.active_marker_index())

	for _i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_save_screenshot("01_explore.png")

	# Trainer sprites (Brock/Bug Catcher/Rival) don't appear until several
	# fights deep — force-place one directly in view to check the imported
	# art renders correctly as an in-world billboard (alpha cutout, sizing).
	for trainer_id in ["brock", "bug_catcher_butterfree", "rival_squirtle"]:
		var probe := EncounterMarker.new()
		add_child(probe)
		probe.position = WorldGrid.world_pos(player.grid_pos) + Vector3(0, 0, -3.0)
		probe.setup(999, trainer_id, trainer_id)
		await get_tree().create_timer(0.2).timeout
		_save_screenshot("00_trainer_%s.png" % trainer_id)
		probe.queue_free()
		await get_tree().process_frame

	player._handle_action("turn_right")
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("02_turn.png")
	player._handle_action("turn_left")
	await get_tree().create_timer(0.3).timeout

	player._handle_action("move_forward")
	await get_tree().create_timer(1.2).timeout
	_save_screenshot("03_combat_start.png")

	# Auto-play the fight to completion (win or loss) via CombatUI's own
	# handlers, same as a real button press would.
	var safety := 0
	var captured_player_fx := false
	var captured_enemy_fx := false
	while combat_ui != null and safety < 300:
		safety += 1
		if combat_ui.busy:
			await get_tree().create_timer(0.05).timeout
			continue
		var played := false
		for i in combat_ui.ctx.player.hand.size():
			if combat_ui.ctx.can_play_card(i)["ok"]:
				combat_ui._on_card_pressed(i)
				played = true
				if not captured_player_fx:
					await get_tree().create_timer(0.1).timeout
					_save_screenshot("03b_player_attack_fx.png")
					captured_player_fx = true
				break
		if not played:
			combat_ui._on_end_turn_pressed()
			if not captured_enemy_fx:
				await get_tree().create_timer(0.1).timeout
				_save_screenshot("03c_enemy_attack_fx.png")
				captured_enemy_fx = true
		await get_tree().create_timer(0.15).timeout
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("04_after_combat.png")

	for child in get_children():
		if child is DraftUI:
			var opts: Array[String] = child.options
			child.done.emit(opts[0] if not opts.is_empty() else "")
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("05_post_fight.png")

	# Force-test Shop/End screens directly — reaching them for real requires
	# clearing several fights first, but their layout doesn't depend on how
	# the run got there.
	var shop := ShopUI.new(1, "center")
	add_child(shop)
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("06_shop_center.png")
	shop.queue_free()
	await get_tree().process_frame

	var mart := ShopUI.new(1, "mart")
	add_child(mart)
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("06b_shop_mart.png")
	mart.queue_free()
	await get_tree().process_frame

	var end_win := EndUI.new(true)
	add_child(end_win)
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("07_end_win.png")
	end_win.queue_free()
	await get_tree().process_frame

	var end_loss := EndUI.new(false)
	add_child(end_loss)
	await get_tree().create_timer(0.3).timeout
	_save_screenshot("08_end_loss.png")
	end_loss.queue_free()


func _save_screenshot(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := SHOT_DIR + filename
	var err := img.save_png(path)
	print("Saved %s -> %s" % [path, err])
