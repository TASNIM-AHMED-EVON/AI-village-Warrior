extends Node2D

const UI_THEME := preload("res://themes/medieval_ui.tres")
const BUILD_OPTIONS := ["cannon", "archer_tower", "clan_castle", "gold_mine", "elixir_pump", "barracks", "laboratory", "wall"]
const BUILDING_ART := {
	"town_hall": "res://assets/buildings/town_hall_sprite.png",
	"barracks": "res://assets/buildings/barracks_sprite.png",
	"cannon": "res://assets/buildings/cannon_sprite.png",
	"wall": "res://assets/generated/stone_wall.png",
	"archer_tower": "res://assets/buildings/archer_tower_sprite.png",
	"clan_castle": "res://assets/buildings/clan_castle_sprite.png",
	"laboratory": "res://assets/generated/laboratory_sprite.png",
	"gold_mine": "res://assets/buildings/gold_mine_sprite.png",
	"elixir_pump": "res://assets/buildings/elixir_pump_sprite.png",
}

@onready var terrain = $Terrain
@onready var objects = $Objects
@onready var grid_overlay = $GridOverlay
@onready var strategy_camera: Camera2D = $Camera2D

var village := VillageModel.new()
var build_mode := false
var selected_building_id := ""
var selected_object: Dictionary = {}
var moving_object_id := ""
var _loaded_saved_layout := false
var _status_label: Label
var _selection_panel: PanelContainer
var _selection_text: Label
var _selection_art: TextureRect
var _selection_actions: HFlowContainer
var _build_panel: PanelContainer
var _build_buttons: HBoxContainer
var _debug_label: Label
var _gold_label: Label
var _elixir_label: Label
var _gems_label: Label
var _training_panel: PanelContainer
var _train_rows: Dictionary = {}
var _train_elixir_label: Label
var _lab_menu: PopupMenu


func _ready() -> void:
	var saved_village: Variant = SaveManager.load_village()
	if saved_village is VillageModel:
		village = saved_village
		_loaded_saved_layout = true
	else:
		village.create_starter_layout()
	if village.repair_playable_state():
		_loaded_saved_layout = true
	# Refill the player's village stock whenever this scene is entered.
	village.refill_player_inventory()
	SaveManager.save_village(village)
	objects.set_village(village)
	terrain.set_village(village)
	strategy_camera.set_home_position(village.grid.cell_to_world(Vector2(30, 30)))
	_build_hud()
	GameManager.set_state(GameManager.GameState.VILLAGE)
	if _loaded_saved_layout:
		_status_label.text = "Saved village layout loaded."
	_update_selection_panel()
	_update_resources()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build_mode"):
		_toggle_build_mode()
	elif event.is_action_pressed("debug_overlay"):
		_debug_label.visible = not _debug_label.visible
		_update_debug_overlay()
	elif event.is_action_pressed("ui_cancel"):
		if _training_panel != null and _training_panel.visible:
			_close_training_panel()
		elif not moving_object_id.is_empty():
			_end_move()
			_status_label.text = "Move cancelled."
		elif build_mode:
			_set_build_mode(false)
		else:
			_deselect()
	elif event is InputEventMouseMotion:
		_update_hover()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_world_click()


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
	top.offset_left = 18
	top.offset_top = 16
	top.offset_right = -18
	top.offset_bottom = 76
	hud.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	top.add_child(top_row)
	var brand := _new_label("CHIEF  •  LEVEL 1", 18, Color("f2d078"))
	top_row.add_child(brand)
	top_row.add_child(_new_label("🏆  0", 15, Color("f1d477")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	_gold_label = _resource_chip(top_row, "gold", Color("f1d477"))
	_elixir_label = _resource_chip(top_row, "elixir", Color("f08bce"))
	_gems_label = _resource_chip(top_row, "gems", Color("8be4c8"))
	top_row.add_child(_new_button("SAVE", _save_village))
	var menu_button := _new_button("MENU", _return_to_menu)
	top_row.add_child(menu_button)

	var actions := HBoxContainer.new()
	actions.anchor_left = 1.0
	actions.anchor_top = 1.0
	actions.anchor_right = 1.0
	actions.anchor_bottom = 1.0
	actions.offset_left = -330
	actions.offset_top = -74
	actions.offset_right = -18
	actions.offset_bottom = -14
	actions.add_theme_constant_override("separation", 8)
	hud.add_child(actions)
	var build_button := _new_button("BUILD", _toggle_build_mode)
	build_button.custom_minimum_size = Vector2(112, 54)
	actions.add_child(build_button)
	actions.add_child(_new_button("FOCUS", _focus_town_hall))
	actions.add_child(_new_button("SHOP", _open_shop))
	var attack_actions := HBoxContainer.new()
	attack_actions.anchor_top = 1.0
	attack_actions.anchor_bottom = 1.0
	attack_actions.offset_left = 18
	attack_actions.offset_top = -74
	attack_actions.offset_right = 188
	attack_actions.offset_bottom = -14
	hud.add_child(attack_actions)
	var attack_button := _new_button("ATTACK!", _start_battle)
	attack_button.custom_minimum_size = Vector2(170, 54)
	attack_button.add_theme_color_override("font_color", Color("fff1bd"))
	attack_button.add_theme_stylebox_override("normal", _button_style(Color("a84430")))
	attack_button.add_theme_stylebox_override("hover", _button_style(Color("c85b3c")))
	attack_actions.add_child(attack_button)

	_build_panel = PanelContainer.new()
	_build_panel.anchor_left = 0.5
	_build_panel.anchor_top = 1.0
	_build_panel.anchor_right = 0.5
	_build_panel.anchor_bottom = 1.0
	_build_panel.offset_left = -520
	_build_panel.offset_right = 520
	_build_panel.offset_top = -178
	_build_panel.offset_bottom = -92
	_build_panel.visible = false
	hud.add_child(_build_panel)
	_build_buttons = HBoxContainer.new()
	_build_buttons.add_theme_constant_override("separation", 8)
	_build_panel.add_child(_build_buttons)
	for building_id in BUILD_OPTIONS:
		var definition := BuildingCatalog.get_definition(building_id)
		var button := _new_button("+  %s\n%d gold" % [definition["name"], definition["cost"]], _select_building.bind(building_id))
		button.custom_minimum_size = Vector2(116, 62)
		button.icon = objects.preview_art(building_id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 44)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 11)
		_build_buttons.add_child(button)

	_status_label = _new_label("Click the warrior, then an open tile to move • WASD or middle-drag to pan • B to build", 14, Color("edf4df"))
	_status_label.anchor_left = 0.5
	_status_label.anchor_top = 1.0
	_status_label.anchor_right = 0.5
	_status_label.anchor_bottom = 1.0
	_status_label.offset_left = -330
	_status_label.offset_right = 330
	_status_label.offset_top = -206
	_status_label.offset_bottom = -178
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_status_label)

	_selection_panel = PanelContainer.new()
	_selection_panel.anchor_left = 1.0
	_selection_panel.anchor_right = 1.0
	_selection_panel.offset_left = -282
	_selection_panel.offset_top = 94
	_selection_panel.offset_right = -18
	_selection_panel.offset_bottom = 260
	_selection_panel.visible = false
	hud.add_child(_selection_panel)
	_selection_text = _new_label("", 14, Color("edf4df"))
	_selection_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var selection_content := VBoxContainer.new()
	selection_content.add_theme_constant_override("separation", 10)
	_selection_panel.add_child(selection_content)
	_selection_art = TextureRect.new()
	_selection_art.custom_minimum_size = Vector2(220, 100)
	_selection_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_selection_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selection_content.add_child(_selection_art)
	selection_content.add_child(_selection_text)
	_selection_actions = HFlowContainer.new()
	_selection_actions.add_theme_constant_override("h_separation", 8)
	_selection_actions.add_theme_constant_override("v_separation", 6)
	selection_content.add_child(_selection_actions)
	_build_training_panel(hud)
	_lab_menu = PopupMenu.new()
	_lab_menu.id_pressed.connect(_research_troop_from_menu)
	hud.add_child(_lab_menu)

	_debug_label = _new_label("", 13, Color("b7ffc4"))
	_debug_label.position = Vector2(18, 90)
	_debug_label.visible = false
	_debug_label.add_theme_stylebox_override("normal", _panel_style(Color("101b20"), 0.92))
	hud.add_child(_debug_label)


func _handle_world_click() -> void:
	var cell := village.grid.world_to_cell(get_global_mouse_position())
	if not village.grid.contains_cell(cell):
		_deselect()
		return
	if not moving_object_id.is_empty():
		_try_move_to(cell)
		return
	if build_mode and not selected_building_id.is_empty():
		var result := village.try_place(selected_building_id, cell)
		if result["ok"]:
			objects.refresh()
			objects.play_place(str(result["object"]["id"]))
			terrain.set_village(village)
			AudioManager.play_sfx("build_place")
			_update_resources()
			_status_label.text = "%s placed at %d, %d." % [result["object"]["name"], cell.x, cell.y]
			_update_hover()
			SaveManager.save_village(village)
		else:
			_status_label.text = result["reason"]
		return
	var structure := village.get_structure_at(cell)
	if not structure.is_empty():
		selected_object = structure
		objects.selected_id = structure["id"]
		objects.refresh()
		_update_selection_panel()
		return
	var unit := _get_unit_at(cell)
	if not unit.is_empty():
		selected_object = unit
		objects.selected_id = unit["id"]
		objects.refresh()
		_update_selection_panel()
		return
	if not selected_object.is_empty() and str(selected_object.get("id", "")).begins_with("unit_"):
		var moved := village.move_unit(str(selected_object["id"]), cell)
		if moved["ok"]:
			selected_object = moved["unit"]
			objects.refresh()
			_update_selection_panel()
			_status_label.text = "%s moved to tile %d, %d." % [selected_object["name"], cell.x, cell.y]
		else:
			_status_label.text = moved["reason"]
		return
	_deselect()


func _get_unit_at(_cell: Vector2i) -> Dictionary:
	var click_position := get_global_mouse_position()
	var nearest: Dictionary = {}
	var nearest_distance := 58.0
	for unit in village.units:
		var unit_position: Vector2 = village.grid.cell_to_world(Vector2(unit["cell"]))
		var distance := click_position.distance_to(unit_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = unit
	return nearest


func _update_hover() -> void:
	if not moving_object_id.is_empty():
		var moving_cell := village.grid.world_to_cell(get_global_mouse_position())
		var move_footprint: Vector2i = selected_object.get("footprint", Vector2i.ONE)
		grid_overlay.set_preview(moving_cell, move_footprint, village.can_move_structure(moving_object_id, moving_cell))
		return
	if not build_mode or selected_building_id.is_empty():
		return
	var cell := village.grid.world_to_cell(get_global_mouse_position())
	var definition := BuildingCatalog.get_definition(selected_building_id)
	var footprint: Vector2i = definition["footprint"]
	grid_overlay.set_preview(cell, footprint, village.grid.is_footprint_clear(cell, footprint) and village.gold >= int(definition["cost"]))


func _toggle_build_mode() -> void:
	_set_build_mode(not build_mode)


func _set_build_mode(enabled: bool) -> void:
	_end_move()
	build_mode = enabled
	_build_panel.visible = build_mode
	grid_overlay.set_grid_visible(build_mode)
	grid_overlay.set_preview_art(null)
	grid_overlay.set_preview(Vector2i(-1, -1), Vector2i.ONE, false)
	selected_building_id = ""
	selected_object = {}  # Never .clear(): this dictionary is the live building data.
	objects.selected_id = ""
	objects.refresh()
	if build_mode:
		GameManager.set_state(GameManager.GameState.BUILD_MODE)
		_status_label.text = "Choose a building, then place it on a clear green tile."
	else:
		GameManager.set_state(GameManager.GameState.VILLAGE)
		_status_label.text = "Click the warrior, then an open tile to move • WASD or middle-drag to pan • B to build"
	_update_selection_panel()
	_update_debug_overlay()


func _select_building(building_id: String) -> void:
	selected_building_id = building_id
	grid_overlay.set_preview_art(objects.preview_art(building_id), objects.preview_size(building_id))
	var definition := BuildingCatalog.get_definition(building_id)
	_status_label.text = "Place %s (%d × %d tiles). Escape cancels build mode." % [definition["name"], definition["footprint"].x, definition["footprint"].y]
	_update_selection_panel()
	_update_hover()


func _deselect() -> void:
	_close_training_panel()
	if not moving_object_id.is_empty():
		_end_move()
	selected_object = {}  # Never .clear(): this dictionary is the live building data.
	objects.selected_id = ""
	objects.refresh()
	_update_selection_panel()


func _update_selection_panel() -> void:
	for child in _selection_actions.get_children():
		child.queue_free()
	if not selected_building_id.is_empty():
		var definition := BuildingCatalog.get_definition(selected_building_id)
		_selection_panel.visible = true
		_selection_art.visible = BUILDING_ART.has(selected_building_id)
		if _selection_art.visible:
			_selection_art.texture = objects.preview_art(selected_building_id)
		_selection_text.text = "%s  •  %s\nCost  %d gold\nFootprint  %d × %d tiles\n\n%s" % [
			definition["name"], definition["category"], definition["cost"],
			definition["footprint"].x, definition["footprint"].y, definition["description"],
		]
		return
	if selected_object.is_empty():
		_selection_panel.visible = false
		return
	_selection_panel.visible = true
	var selected_type := str(selected_object.get("type", ""))
	_selection_art.visible = BUILDING_ART.has(selected_type)
	if _selection_art.visible:
		_selection_art.texture = objects.preview_art(selected_type)
	_selection_text.text = "%s\nLevel %d\nHP  %d / %d\n\n%s" % [
		selected_object["name"], selected_object.get("level", 1), selected_object["hp"],
		selected_object["max_hp"],
		BuildingCatalog.get_definition(selected_object.get("type", "")).get("description", "A village warrior."),
	]
	if str(selected_object.get("id", "")).begins_with("unit_"):
		_selection_text.text = "%s\nHP  %d / %d\n\nClick an open tile to move this troop." % [
			selected_object["name"], selected_object["hp"], selected_object["max_hp"],
		]
	var structure_type := str(selected_object.get("type", ""))
	var selected_id := str(selected_object.get("id", ""))
	if not BuildingCatalog.get_definition(structure_type).is_empty():
		var current_max_hp := int(selected_object.get("max_hp", 0))
		_selection_text.text += "\nNext level (%d)  HP %d" % [
			int(selected_object.get("level", 1)) + 1, current_max_hp + maxi(60, int(current_max_hp / 5.0)),
		]
		_selection_actions.add_child(_new_button("UPGRADE  •  %d gold" % (400 * int(selected_object.get("level", 1))), _upgrade_selected.bind(selected_id)))
		_selection_actions.add_child(_new_button("MOVE", _start_move.bind(selected_id)))
		if structure_type == "gold_mine" or structure_type == "elixir_pump":
			_selection_actions.add_child(_new_button("COLLECT", _collect_selected.bind(selected_id)))
		elif structure_type == "barracks":
			_selection_actions.add_child(_new_button("TRAIN TROOPS", _open_training_panel))
		elif structure_type == "laboratory":
			_selection_text.text += "\n\nTroops can be researched up to level %d." % village.max_troop_level()
			_selection_actions.add_child(_new_button("RESEARCH TROOPS", _open_lab_menu))
		elif structure_type == ClanCastle.BUILDING_ID:
			var garrison: Dictionary = selected_object.get("garrison", {})
			var preset_index := ClanCastle.preset_index_of(garrison)
			_selection_text.text += "\n\nGarrison (%d / %d housing)\n%s" % [ClanCastle.housing_used(garrison), ClanCastle.capacity(), ClanCastle.describe(garrison)]
			var preset_label := ClanCastle.preset_name(preset_index) if preset_index >= 0 else "Custom"
			_selection_actions.add_child(_new_button("GARRISON  •  %s" % preset_label, _cycle_castle_garrison.bind(selected_id)))


func _start_move(object_id: String) -> void:
	if selected_object.is_empty() or str(selected_object.get("id", "")) != object_id:
		return
	moving_object_id = object_id
	var building_type := str(selected_object.get("type", ""))
	grid_overlay.set_grid_visible(true)
	grid_overlay.set_preview_art(objects.preview_art(building_type), objects.preview_size(building_type))
	_status_label.text = "Moving %s: click a clear tile to place it. Escape cancels." % selected_object["name"]
	_update_hover()


func _end_move() -> void:
	if moving_object_id.is_empty():
		return
	moving_object_id = ""
	grid_overlay.set_preview_art(null)
	grid_overlay.set_preview(Vector2i(-1, -1), Vector2i.ONE, false)
	grid_overlay.set_grid_visible(build_mode)


func _try_move_to(cell: Vector2i) -> void:
	var result := village.move_structure(moving_object_id, cell)
	if not result["ok"]:
		_status_label.text = result["reason"]
		return
	var moved_id := moving_object_id
	_end_move()
	selected_object = result["structure"]
	objects.refresh()
	objects.play_place(moved_id)
	terrain.set_village(village)
	AudioManager.play_sfx("build_place")
	_update_selection_panel()
	SaveManager.save_village(village)
	_status_label.text = "%s moved to %d, %d." % [selected_object["name"], cell.x, cell.y]


func _focus_town_hall() -> void:
	for structure in village.structures:
		if structure["type"] == "town_hall":
			var center_cell: Vector2 = Vector2(structure["cell"]) + (Vector2(structure["footprint"]) - Vector2.ONE) * 0.5
			strategy_camera.target_position = village.grid.cell_to_world(center_cell)
			strategy_camera.zoom = Vector2.ONE * 0.95
			return


func _return_to_menu() -> void:
	SaveManager.save_village(village)
	SceneManager.change_to(SceneManager.MAIN_MENU, GameManager.GameState.MAIN_MENU)


func _start_battle() -> void:
	SaveManager.save_village(village)
	SceneManager.change_to(SceneManager.BATTLE, GameManager.GameState.BATTLE_DEPLOYMENT)


func _open_shop() -> void:
	_set_build_mode(true)
	_status_label.text = "Choose a building from the shop, then place it on an open tile."


func _save_village() -> void:
	if SaveManager.save_village(village):
		_status_label.text = "Village saved to %s" % SaveManager.get_village_save_path()


func _upgrade_selected(object_id: String) -> void:
	var result := village.upgrade_structure(object_id)
	if not result["ok"]:
		_status_label.text = result["reason"]
		return
	selected_object = result["structure"]
	objects.refresh()
	AudioManager.play_sfx("build_place")
	_update_selection_panel()
	_update_resources()
	SaveManager.save_village(village)
	_status_label.text = "%s upgraded to level %d." % [selected_object["name"], selected_object["level"]]


func _cycle_castle_garrison(object_id: String) -> void:
	var result := village.cycle_castle_garrison(object_id)
	if not result["ok"]:
		_status_label.text = result["reason"]
		return
	AudioManager.play_sfx("build_place")
	_update_selection_panel()
	_status_label.text = "Clan Castle garrison: %s (%s)." % [result["preset"], ClanCastle.describe(result["garrison"])]


func _collect_selected(object_id: String) -> void:
	var result := village.collect_from_structure(object_id)
	if not result["ok"]:
		_status_label.text = result["reason"]
		return
	_update_resources()
	_status_label.text = "+%d %s collected." % [result["amount"], str(result["resource"]).capitalize()]


func _build_training_panel(hud: Control) -> void:
	_training_panel = PanelContainer.new()
	_training_panel.visible = false
	_training_panel.anchor_left = 0.5
	_training_panel.anchor_right = 0.5
	_training_panel.anchor_top = 0.5
	_training_panel.anchor_bottom = 0.5
	_training_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_training_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_training_panel.offset_left = -80  # Sits left of the building panel so neither hides the other.
	_training_panel.offset_right = -80
	_training_panel.z_index = 20
	hud.add_child(_training_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_training_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _new_label("BARRACKS  •  TRAIN TROOPS", 18, Color("f2d078"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_train_elixir_label = _new_label("", 14, Color("efa9db"))
	header.add_child(_train_elixir_label)
	header.add_child(_new_button("X", _close_training_panel))
	column.add_child(_new_label("Pick how many of each troop to train, then press TRAIN.", 12, Color("c9d6c4")))
	for troop_id in TroopCatalog.all_ids():
		column.add_child(_build_training_row(troop_id))


func _build_training_row(troop_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = objects.preview_art(troop_id)
	icon.custom_minimum_size = Vector2(46, 46)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(230, 0)
	info.add_theme_constant_override("separation", 0)
	var name_label := _new_label("", 15, Color("fff2d0"))
	var detail_label := _new_label("", 11, Color("c9d6c4"))
	info.add_child(name_label)
	info.add_child(detail_label)
	row.add_child(info)
	var owned_label := _new_label("", 12, Color("e3d7b6"))
	owned_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(owned_label)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = VillageModel.MAX_TRAIN_BATCH
	spin.step = 1
	spin.value = 1
	spin.custom_minimum_size = Vector2(92, 34)
	row.add_child(spin)
	var max_button := _new_button("MAX", _train_set_max.bind(troop_id))
	max_button.custom_minimum_size = Vector2(52, 34)
	row.add_child(max_button)
	var train_button := _new_button("TRAIN", _train_batch.bind(troop_id))
	train_button.custom_minimum_size = Vector2(150, 34)
	row.add_child(train_button)
	spin.value_changed.connect(func(_value: float) -> void: _refresh_training_row(troop_id))
	_train_rows[troop_id] = {
		"name": name_label, "detail": detail_label, "owned": owned_label,
		"spin": spin, "button": train_button,
	}
	return row


func _open_training_panel() -> void:
	_refresh_training_panel()
	_training_panel.visible = true


func _close_training_panel() -> void:
	if _training_panel != null:
		_training_panel.visible = false


func _refresh_training_panel() -> void:
	_train_elixir_label.text = "ELIXIR  %s" % _format_number(village.elixir)
	for troop_id in _train_rows:
		_refresh_training_row(troop_id)


func _refresh_training_row(troop_id: String) -> void:
	var row: Dictionary = _train_rows[troop_id]
	var definition := TroopCatalog.get_definition(troop_id)
	var level := village.troop_level(troop_id)
	var count := int((row["spin"] as SpinBox).value)
	var total := int(definition["cost"]) * count
	(row["name"] as Label).text = "%s  Lv %d%s" % [definition["name"], level, "  (flying)" if bool(definition.get("flying", false)) else ""]
	(row["detail"] as Label).text = "HP %d  •  DMG %d  •  %d elixir each" % [
		TroopCatalog.hp_at_level(troop_id, level), TroopCatalog.damage_at_level(troop_id, level), definition["cost"],
	]
	(row["owned"] as Label).text = "In army: %d" % int(village.army.get(troop_id, 0))
	var button := row["button"] as Button
	button.text = "TRAIN %d  •  %s" % [count, _format_number(total)]
	button.disabled = village.elixir < total


func _train_set_max(troop_id: String) -> void:
	var cost := int(TroopCatalog.get_definition(troop_id)["cost"])
	var affordable := clampi(int(village.elixir / maxi(cost, 1)), 1, VillageModel.MAX_TRAIN_BATCH)
	(_train_rows[troop_id]["spin"] as SpinBox).value = affordable
	_refresh_training_row(troop_id)


func _train_batch(troop_id: String) -> void:
	var count := int((_train_rows[troop_id]["spin"] as SpinBox).value)
	var result := village.train_troops(troop_id, count)
	if not result["ok"]:
		_status_label.text = result["reason"]
		_refresh_training_panel()
		return
	_update_resources()
	SaveManager.save_village(village)
	_refresh_training_panel()
	_status_label.text = "Trained %d %s. You now have %d." % [result["added"], result["troop"]["name"], result["count"]]


func _open_lab_menu() -> void:
	_lab_menu.clear()
	var troop_ids := TroopCatalog.all_ids()
	for index in range(troop_ids.size()):
		var troop_id := troop_ids[index]
		var definition := TroopCatalog.get_definition(troop_id)
		var level := village.troop_level(troop_id)
		if level >= TroopCatalog.MAX_LEVEL:
			_lab_menu.add_item("%s  Lv %d  (MAX)" % [definition["name"], level], index)
			_lab_menu.set_item_disabled(index, true)
			continue
		_lab_menu.add_item("%s  Lv %d → %d   HP %d → %d   DMG %d → %d  •  %d elixir" % [
			definition["name"], level, level + 1,
			TroopCatalog.hp_at_level(troop_id, level), TroopCatalog.hp_at_level(troop_id, level + 1),
			TroopCatalog.damage_at_level(troop_id, level), TroopCatalog.damage_at_level(troop_id, level + 1),
			TroopCatalog.upgrade_cost(troop_id, level),
		], index)
		_lab_menu.set_item_disabled(index, level >= village.max_troop_level())
	_lab_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_lab_menu.popup()


func _research_troop_from_menu(item_id: int) -> void:
	var troop_ids := TroopCatalog.all_ids()
	if item_id < 0 or item_id >= troop_ids.size():
		return
	var result := village.upgrade_troop(troop_ids[item_id])
	if not result["ok"]:
		_status_label.text = result["reason"]
		return
	_update_resources()
	_update_selection_panel()
	SaveManager.save_village(village)
	_status_label.text = "%s upgraded to level %d: more hit points and damage in battle." % [result["troop"]["name"], result["level"]]


func _update_resources() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "GOLD  %s" % _format_number(village.gold)
	_elixir_label.text = "ELIXIR  %s" % _format_number(village.elixir)
	_gems_label.text = "GEMS  %s" % _format_number(village.gems)


func _format_number(value: int) -> String:
	var remaining := str(value)
	var groups: Array[String] = []
	while remaining.length() > 3:
		groups.push_front(remaining.substr(remaining.length() - 3, 3))
		remaining = remaining.substr(0, remaining.length() - 3)
	groups.push_front(remaining)
	return ",".join(groups)


func _load_village() -> void:
	var loaded_village: Variant = SaveManager.load_village()
	if not loaded_village is VillageModel:
		_status_label.text = "No valid saved village found yet."
		return
	village = loaded_village
	selected_object = {}  # Never .clear(): this dictionary is the live building data.
	selected_building_id = ""
	objects.selected_id = ""
	objects.set_village(village)
	terrain.set_village(village)
	grid_overlay.grid_data = village.grid
	_update_selection_panel()
	_status_label.text = "Village layout loaded."


func _update_debug_overlay() -> void:
	if _debug_label == null:
		return
	_debug_label.text = "DEBUG\nState: %s\nGrid: %d × %d\nStructures: %d\nUnits: %d\nBuild Mode: %s" % [
		GameManager.GameState.keys()[GameManager.current_state], village.grid.width,
		village.grid.height, village.structures.size(), village.units.size(), str(build_mode),
	]


func _resource_chip(parent: HBoxContainer, icon_id: String, color: Color) -> Label:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	parent.add_child(chip)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(25, 25)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var path := "res://assets/generated/%s_icon.png" % icon_id
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	else:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			icon.texture = ImageTexture.create_from_image(image)
	chip.add_child(icon)
	var label := _new_label("", 15, color)
	chip.add_child(label)
	return label


func _new_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _new_button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(92, 38)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("fff0c7"))
	button.pressed.connect(func() -> void: AudioManager.play_sfx("ui_click"))
	button.pressed.connect(action)
	return button


func _panel_style(color: Color, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, alpha)
	style.border_color = Color("f0d58a", 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("f3d782", 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	return style
