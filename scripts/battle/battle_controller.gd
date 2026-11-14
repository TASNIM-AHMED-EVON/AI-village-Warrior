extends Node2D
const UI_THEME := preload("res://themes/medieval_ui.tres")
const AI_OVERLAY := preload("res://scripts/battle/ai_path_overlay.gd")
const COMBAT_EFFECTS := preload("res://scripts/battle/combat_fx.gd")
const BATTLE_SEARCH := preload("res://scripts/ai/battle_search_ai.gd")
const TROOPS := ["warrior", "archer", "mage", "goblin", "tank"]
const TROOP_ART := {
	"warrior": "res://assets/troops/warrior_sprite.png",
	"archer": "res://assets/troops/archer_sprite.png",
	"mage": "res://assets/troops/mage_sprite.png",
	"goblin": "res://assets/troops/goblin_sprite.png",
	"tank": "res://assets/generated/siege_wagon.png",
}
const TILE := VillageGrid.TILE_SIZE
@onready var terrain = $Terrain
@onready var objects = $Objects
@onready var camera = $Camera2D
@onready var units = $Units
@onready var targets = $Targets
var village := VillageModel.new()  # Throwaway copy that the battle is allowed to damage.
var home_village := VillageModel.new()  # The player's real layout; never damaged by a battle.
var battle: BattleManager
var selected := "warrior"
var _stats: Label
var _status: Label
var _cards := {}
var _card_counts := {}
var _card_icons := {}
var _result: PanelContainer
var _preview := Vector2i(-1, -1)
var _path_choice: OptionButton
var _strategy_choice: OptionButton
var _debug_panel: PanelContainer
var _debug_text: Label
var _overlay
var _effects
## Set by a ranged attack just before its damage event: how long (battle seconds) the shot is still in flight.
var _pending_hit_delay := 0.0
var _pending_hit_kind := ""
var _last_hud_frame := -100

func _ready() -> void:
	var saved: Variant = SaveManager.load_village()
	if saved is VillageModel: home_village = saved
	else: home_village.create_starter_layout()
	var recovered_save := home_village.repair_playable_state()
	# Tops resources and the starting army back up; troops the player trained are kept.
	home_village.refill_player_inventory()
	SaveManager.save_village(home_village)
	# The battle damages and deletes buildings, so it runs on a copy of the saved layout.
	village = VillageModel.new()
	if not village.deserialize(home_village.serialize()):
		village = home_village
	objects.battle_mode = true
	objects.set_village(village)
	terrain.set_village(village)
	# Place attackers under the same Y-sort parent as buildings.
	# The node tree still owns actors; battle rules do not depend on parent names.
	camera.set_battle_view(village.grid.cell_to_world(Vector2(30, 30)))
	battle = BattleManager.new()
	add_child(battle)
	battle.begin_battle(village, objects, targets)
	battle.battle_updated.connect(_update_hud)
	battle.battle_finished.connect(_finish)
	battle.status_message.connect(_set_status)
	battle.projectile_event.connect(_on_projectile_event)
	battle.damage_event.connect(_on_damage_event)
	battle.destruction_event.connect(_on_destruction_event)
	_overlay = AI_OVERLAY.new()
	_overlay.name = "AIPathOverlay"
	_overlay.visible = false
	add_child(_overlay)
	_overlay.set_battle(battle)
	_effects = COMBAT_EFFECTS.new()
	_effects.name = "CombatEffects"
	add_child(_effects)
	GameManager.set_state(GameManager.GameState.BATTLE_DEPLOYMENT)
	_build_hud()
	if recovered_save:
		_set_status("Your saved village was empty or out of troops, so it has been restored for this battle.")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		_debug_panel.visible = not _debug_panel.visible
		_update_debug_panel()
	elif event.is_action_pressed("ai_show_paths"):
		_toggle_path_visualization()
	elif event is InputEventMouseMotion:
		_preview = village.grid.world_to_cell(get_global_mouse_position())
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _result.visible:
		var cell := village.grid.world_to_cell(get_global_mouse_position())
		if battle.deploy(selected, cell):
			AudioManager.play_sfx("troop_deploy")
			if _overlay != null and _overlay.visible:
				_overlay.refresh()
			_set_status("%s deployed. Deploy more troops or let them attack." % selected.capitalize())
	elif event.is_action_pressed("ui_cancel") and battle.phase == BattleManager.Phase.ACTIVE:
		battle.set_paused(true)
		AudioManager.play_sfx("ui_click")
		_set_status("Battle paused. Press Resume to continue.")

func _draw() -> void:
	if _preview.x < 0 or not village.grid.contains_cell(_preview): return
	var p := village.grid.cell_to_world(Vector2(_preview))
	var shape := PackedVector2Array([p + Vector2(0,-12), p + Vector2(24,0), p + Vector2(0,12), p + Vector2(-24,0)])
	var valid := battle != null and battle.is_valid_deployment_cell(_preview)
	draw_colored_polygon(shape, Color(0.2,0.95,0.35,0.42) if valid else Color(0.95,0.12,0.08,0.5))
	if not valid:
		draw_line(p + Vector2(-8, -5), p + Vector2(8, 5), Color("ffe6db"), 2.0, true)
		draw_line(p + Vector2(8, -5), p + Vector2(-8, 5), Color("ffe6db"), 2.0, true)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var hud := Control.new()
	hud.theme = UI_THEME
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(hud)
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_left = 16
	top.offset_top = 14
	top.offset_right = -16
	top.offset_bottom = 72
	hud.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	row.add_child(_label("AI VILLAGE WARS - ATTACK", 18, Color("a6e7a9")))
	_stats = _label("", 16, Color("f3e5bb"))
	row.add_child(_stats)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_button("PAUSE", _pause))
	row.add_child(_button("1x", func(): battle.set_speed(1.0)))
	row.add_child(_button("2x", func(): battle.set_speed(2.0)))
	row.add_child(_button("3x", func(): battle.set_speed(3.0)))
	row.add_child(_button("5x", func(): battle.set_speed(5.0)))
	row.add_child(_button("RETREAT", _retreat))
	_debug_panel = PanelContainer.new()
	_debug_panel.anchor_left = 1.0
	_debug_panel.anchor_right = 1.0
	_debug_panel.offset_left = -330
	_debug_panel.offset_top = 82
	_debug_panel.offset_right = -16
	_debug_panel.offset_bottom = 470
	_debug_panel.visible = false
	hud.add_child(_debug_panel)
	var debug_box := VBoxContainer.new()
	debug_box.add_theme_constant_override("separation", 6)
	_debug_panel.add_child(debug_box)
	_debug_text = _label("DEBUG", 13, Color("b7ffc4"))
	debug_box.add_child(_debug_text)
	var helper := _label("F4  ·  SHOW/HIDE SEARCH PATHS", 12, Color("f1ce85"))
	debug_box.add_child(helper)
	_path_choice = OptionButton.new()
	for algorithm in GridPathfinder.ALGORITHMS:
		_path_choice.add_item(algorithm)
	_path_choice.item_selected.connect(_on_path_algorithm_selected)
	debug_box.add_child(_path_choice)
	_strategy_choice = OptionButton.new()
	for algorithm in BATTLE_SEARCH.ALGORITHMS:
		_strategy_choice.add_item(algorithm)
	_strategy_choice.item_selected.connect(_on_strategy_algorithm_selected)
	_strategy_choice.select(BATTLE_SEARCH.ALGORITHMS.find(BATTLE_SEARCH.MINIMAX))
	debug_box.add_child(_strategy_choice)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 1.0
	panel.anchor_right = 0.5
	panel.anchor_bottom = 1.0
	panel.offset_left = -365
	panel.offset_right = 365
	panel.offset_top = -146
	panel.offset_bottom = -12
	hud.add_child(panel)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	panel.add_child(cards)
	for id in TROOPS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(132, 116)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
		b.pressed.connect(_select.bind(id))
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 4
		content.offset_top = 2
		content.offset_right = -4
		content.offset_bottom = -2
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 0)
		b.add_child(content)
		var icon := TextureRect.new()
		icon.texture = _troop_card_texture(id)
		icon.custom_minimum_size = Vector2(64, 66)
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content.add_child(icon)
		var name_label := _label(id.capitalize(), 13, Color("fff2d0"))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(name_label)
		var count_label := _label("0 left", 12, Color("e3d7b6"))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(count_label)
		_cards[id] = b
		_card_counts[id] = count_label
		_card_icons[id] = icon
		cards.add_child(b)
	_status = _label("Choose a troop. Deploy anywhere at least 5 tiles from buildings; red tiles are blocked.", 14, Color("edf4df"))
	_status.anchor_left = 0.5
	_status.anchor_top = 1.0
	_status.anchor_right = 0.5
	_status.anchor_bottom = 1.0
	_status.offset_left = -450
	_status.offset_right = 450
	_status.offset_top = -174
	_status.offset_bottom = -150
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_status)
	_result = PanelContainer.new()
	_result.anchor_left = 0.5
	_result.anchor_top = 0.5
	_result.anchor_right = 0.5
	_result.anchor_bottom = 0.5
	_result.offset_left = -190
	_result.offset_top = -85
	_result.offset_right = 190
	_result.offset_bottom = 85
	_result.visible = false
	hud.add_child(_result)
	_update_hud()

func _update_hud() -> void:
	if _stats == null: return
	if Engine.get_process_frames() - _last_hud_frame < 9:
		return
	_last_hud_frame = Engine.get_process_frames()
	if battle.phase == BattleManager.Phase.ACTIVE:
		GameManager.set_state(GameManager.GameState.BATTLE_ACTIVE)
	elif battle.phase == BattleManager.Phase.PAUSED:
		GameManager.set_state(GameManager.GameState.BATTLE_PAUSED)
	_update_stats()
	for id in TROOPS:
		var b: Button = _cards[id]
		var stock := int(battle.troop_stock.get(id, 0))
		b.disabled = stock <= 0 or battle.phase >= BattleManager.Phase.VICTORY
		b.button_pressed = id == selected
		_card_counts[id].text = "%d available  Lv %d" % [stock, village.troop_level(id)]
		_card_icons[id].modulate = Color.WHITE if stock > 0 else Color(0.62, 0.62, 0.62, 0.78)

func _update_stats() -> void:
	var sec := int(ceil(battle.time_remaining))
	_stats.text = "%s   %02d:%02d   %d%%   %d stars" % ["DEPLOY" if battle.phase == BattleManager.Phase.DEPLOYMENT else "BATTLE", floori(sec / 60.0), sec % 60, battle.get_destruction_percent(), battle.get_stars()]
	if _debug_panel.visible:
		_update_debug_panel()

func _select(id: String) -> void:
	selected = id
	_update_hud()
	_set_status("%s selected. Click an open tile at least 5 tiles from every building." % id.capitalize())


func _on_path_algorithm_selected(index: int) -> void:
	if index < 0 or index >= GridPathfinder.ALGORITHMS.size():
		return
	battle.set_path_algorithm(GridPathfinder.ALGORITHMS[index])
	_set_status("Attacker paths now use %s search." % GridPathfinder.ALGORITHMS[index])
	if _overlay != null:
		_overlay.refresh()


func _on_strategy_algorithm_selected(index: int) -> void:
	if index < 0 or index >= BATTLE_SEARCH.ALGORITHMS.size():
		return
	battle.set_strategy_algorithm(BATTLE_SEARCH.ALGORITHMS[index])
	_set_status("Tactical search now uses %s." % BATTLE_SEARCH.ALGORITHMS[index])
	if _overlay != null:
		_overlay.refresh()


func _update_debug_panel() -> void:
	if _debug_text == null or battle == null:
		return
	var decision := battle.last_ai_decision
	var defender_decision := battle.last_defender_decision
	var released_castles := 0
	for castle_info in battle.castles.values():
		if bool(castle_info.get("released", false)):
			released_castles += 1
	var castle_text := "none" if battle.castles.is_empty() else "%d / %d released" % [released_castles, battle.castles.size()]
	var defender_text := "waiting"
	if not defender_decision.is_empty():
		defender_text = "%s -> %s  (depth %d, nodes %d)" % [str(defender_decision.get("algorithm", "")), str(defender_decision.get("target_name", "none")), int(defender_decision.get("depth", 0)), int(defender_decision.get("nodes", 0))]
	_debug_text.text = "AI INSPECTOR  (F3)\nBattle: %s  ·  Troops: %d\nSearch: %s\nTarget: %s\nDepth: %d  Nodes: %d  Pruned: %d\nDecision: %.2f ms  ·  Budget: %s\nPathfinder: %s\nRoute cost: %d  ·  Explored: %d\nClan Castle: %s  ·  Defenders alive: %d\nDefender AI: %s" % [
		BattleManager.Phase.keys()[battle.phase],
		_count_living(battle.attacker_units),
		str(decision.get("algorithm", battle.strategy_algorithm)),
		str(decision.get("target_name", decision.get("target_id", "waiting"))),
		int(decision.get("depth", 0)),
		int(decision.get("nodes", 0)),
		int(decision.get("pruned", 0)),
		float(decision.get("time_ms", 0.0)),
		str(bool(decision.get("budget_hit", false))),
		battle.path_algorithm,
		int(decision.get("path_cost", 0)),
		_get_last_trace_nodes(),
		castle_text,
		_count_living(battle.defender_units),
		defender_text,
	]

## Counts troops that are still alive. Dead troops are freed after their fade-out, so entries can be
## freed objects; a typed lambda over them throws, which is why this reads each entry as a Variant.
func _count_living(troops: Array) -> int:
	var count := 0
	for index in range(troops.size()):
		var entry: Variant = troops[index]
		if is_instance_valid(entry) and entry.state != TroopActor.State.DEAD:
			count += 1
	return count


func _pause() -> void:
	if battle.phase == BattleManager.Phase.ACTIVE:
		battle.set_paused(true)
		_set_status("Battle paused. Press Resume to continue.")
	elif battle.phase == BattleManager.Phase.PAUSED:
		battle.set_paused(false)
		_set_status("Battle resumed.")

func _set_status(message: String) -> void:
	if _status != null: _status.text = message

func _finish(result: Dictionary) -> void:
	GameManager.set_state(GameManager.GameState.BATTLE_RESULT)
	# Keep the undamaged home layout; only the loot carries back to the village.
	home_village.gold += int(result.get("loot_gold", 0))
	home_village.elixir += int(result.get("loot_elixir", 0))
	SaveManager.save_village(home_village)
	var box := VBoxContainer.new()
	_result.add_child(box)
	var title := "VICTORY" if result.phase == "VICTORY" else ("TIME UP" if result.phase == "TIMEOUT" else "DEFEAT")
	box.add_child(_label(title, 28, Color("f3d782")))
	box.add_child(_label("%d / 3 STARS  •  %d%% destruction" % [result["stars"], result["destruction_percent"]], 17, Color("edf4df")))
	box.add_child(_label("+%d gold     +%d elixir" % [result["loot_gold"], result["loot_elixir"]], 16, Color("f3d782")))
	if int(result.get("defenders_released", 0)) > 0:
		box.add_child(_label("Clan Castle defenders beaten: %d / %d" % [result["defenders_defeated"], result["defenders_released"]], 15, Color("c7d8ff")))
	box.add_child(_button("RETURN TO VILLAGE", _retreat))
	_result.visible = true
	_result.modulate.a = 0.0
	_result.scale = Vector2(0.88, 0.88)
	var reveal := create_tween()
	reveal.set_parallel(true)
	reveal.tween_property(_result, "modulate:a", 1.0, 0.34)
	reveal.tween_property(_result, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("victory" if result.phase == "VICTORY" else "defeat")
	_update_hud()

func _retreat() -> void:
	SaveManager.save_village(home_village)
	SceneManager.change_to(SceneManager.VILLAGE, GameManager.GameState.VILLAGE)

func _label(text_value: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size",size)
	l.add_theme_color_override("font_color",color)
	return l

func _button(text_value: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text_value
	b.custom_minimum_size = Vector2(74,38)
	b.add_theme_font_size_override("font_size",13)
	b.add_theme_color_override("font_color", Color("fff2d0"))
	b.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	b.pressed.connect(action)
	return b

func _style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("765b3b",0.96)
	s.border_color = Color("f0d58a",0.85)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color("f3d782",0.9)
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	return s


func _troop_card_texture(id: String) -> Texture2D:
	var path: String = TROOP_ART[id]
	if ResourceLoader.exists(path):
		return load(path)
	if id == "tank":
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			return ImageTexture.create_from_image(image)
		return load("res://assets/troops/tank_sprite.png")
	return load(path)


func _get_last_trace_nodes() -> int:
	var highest := 0
	for trace in battle.path_traces.values():
		highest = maxi(highest, int(trace.get("nodes", 0)))
	return highest


func _toggle_path_visualization() -> void:
	if battle == null:
		return
	battle.set_visualization_enabled(not battle.visualization_enabled)
	_overlay.visible = battle.visualization_enabled
	_overlay.refresh()
	_set_status("F4  ·  Search paths %s. F3 opens AI details." % ("ON" if battle.visualization_enabled else "OFF"))
	_update_debug_panel()


func _process(_delta: float) -> void:
	# Projectiles slow down, speed up and freeze together with the battle.
	if _effects != null and battle != null:
		_effects.time_scale = battle.visual_time_scale()


func _on_projectile_event(kind: String, from_position: Vector2, to_position: Vector2, flight_time: float) -> void:
	if _effects != null:
		_effects.fire_projectile(kind, from_position, to_position, flight_time)
	# The damage_event for this same attack follows immediately; its feedback waits until the shot lands.
	_pending_hit_delay = flight_time
	_pending_hit_kind = kind


func _on_damage_event(world_position: Vector2, amount: int, heavy: bool) -> void:
	var delay := _pending_hit_delay
	var kind := _pending_hit_kind
	_pending_hit_delay = 0.0
	_pending_hit_kind = ""
	if delay > 0.0:
		var real_delay := delay / maxf(battle.visual_time_scale(), 0.05)
		get_tree().create_timer(real_delay).timeout.connect(_show_hit_feedback.bind(world_position, amount, heavy, kind))
	else:
		_show_hit_feedback(world_position, amount, heavy, kind)


func _show_hit_feedback(world_position: Vector2, amount: int, heavy: bool, kind: String) -> void:
	if _effects != null:
		_effects.damage_number(world_position, amount, heavy)
	objects.refresh()  # Updates the structure sprites' hit flash.
	if _overlay != null and _overlay.visible:
		_overlay.refresh()
	if kind == "arrow":
		AudioManager.play_sfx("arrow")
	else:
		AudioManager.play_sfx("cannon" if heavy else "sword_hit")


func _on_destruction_event(world_position: Vector2) -> void:
	if _effects != null:
		_effects.crumble(world_position)
	objects.refresh()  # Removes the destroyed building sprite, leaves logic untouched.
	terrain.set_village(village)
	if _overlay != null and _overlay.visible:
		call_deferred("_refresh_path_overlay")
	AudioManager.play_sfx("destroy")


func _refresh_path_overlay() -> void:
	if _overlay != null and _overlay.visible:
		_overlay.refresh()
