extends Node2D
## Sprite-based rendering; each model object owns a Y-sorted VisualEntity.
## No model, battle-rule, or pathfinding data is changed by this layer.

const ART_PATHS := {
	"town_hall": "res://assets/buildings/town_hall_sprite.png",
	"barracks": "res://assets/buildings/barracks_sprite.png",
	"cannon": "res://assets/buildings/cannon_sprite.png",
	"archer_tower": "res://assets/buildings/archer_tower_sprite.png",
	"clan_castle": "res://assets/buildings/clan_castle_sprite.png",
	"gold_mine": "res://assets/buildings/gold_mine_sprite.png",
	"elixir_pump": "res://assets/buildings/elixir_pump_sprite.png",
	"wall": "res://assets/generated/stone_wall.png",
	"warrior": "res://assets/troops/warrior_sprite.png",
	"archer": "res://assets/troops/archer_sprite.png",
	"mage": "res://assets/troops/mage_sprite.png",
	"goblin": "res://assets/troops/goblin_sprite.png",
	"tank": "res://assets/generated/siege_wagon.png",
}
const DIMENSIONS := {
	"town_hall": Vector2(235, 211),
	"barracks": Vector2(228, 153),
	"cannon": Vector2(106, 91),
	"archer_tower": Vector2(142, 201),
	"clan_castle": Vector2(253, 192),
	"gold_mine": Vector2(133, 147),
	"elixir_pump": Vector2(131, 164),
	"wall": Vector2(45, 47),
	"warrior": Vector2(55, 68),
	"archer": Vector2(54, 68),
	"mage": Vector2(53, 72),
	"goblin": Vector2(51, 64),
	"tank": Vector2(78, 66),
}
const FALLBACK_ART := {
	"wall": "res://assets/buildings/wall_sprite.png",
	"tank": "res://assets/troops/tank_sprite.png",
}

var village: VillageModel
var battle_mode := false
var selected_id: String = "":
	set(value):
		selected_id = value
		_sync_selection()
var building_aims: Dictionary = {}
var _entities: Dictionary = {}
var _unit_positions: Dictionary = {}
var _art_cache: Dictionary = {}
var _frames_cache: Dictionary = {}


func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_village(model: VillageModel) -> void:
	village = model
	building_aims.clear()
	for child in get_children():
		if child is VisualEntity:
			child.queue_free()
	_entities.clear()
	_unit_positions.clear()
	refresh()


func refresh() -> void:
	if village == null:
		return
	var present: Dictionary = {}
	for structure in village.structures:
		var id := str(structure["id"])
		present[id] = true
		var entity: VisualEntity = _entities.get(id)
		if entity == null or not is_instance_valid(entity):
			entity = _create_structure(structure)
			_entities[id] = entity
		else:
			entity.position = _structure_anchor(structure)
		entity.set_selected(selected_id == id)
		if battle_mode:
			entity.show_health_bar = false
			entity.set_health(int(structure["hp"]), int(structure["max_hp"]))
	for unit in village.units:
		var id := str(unit["id"])
		present[id] = true
		var entity: VisualEntity = _entities.get(id)
		if entity == null or not is_instance_valid(entity):
			entity = _create_village_unit(unit)
			_entities[id] = entity
		entity.set_selected(selected_id == id)
	for id in _entities.keys():
		if not present.has(id):
			var old: VisualEntity = _entities[id]
			if is_instance_valid(old):
				old.queue_free()
			_entities.erase(id)
			_unit_positions.erase(id)


func preview_art(type: String) -> Texture2D:
	return _texture(type)


func preview_size(type: String) -> Vector2:
	return DIMENSIONS.get(type, Vector2(110, 115))


func play_place(id: String) -> void:
	var entity: VisualEntity = _entities.get(id)
	if is_instance_valid(entity):
		entity.play_placement()


func flash_structure(id: String) -> void:
	var entity: VisualEntity = _entities.get(id)
	if is_instance_valid(entity):
		entity.flash_hit()


func set_building_aim(building_id: String, direction: Vector2) -> void:
	if direction.length_squared() < 0.001:
		return
	building_aims[building_id] = direction.normalized()
	var entity: VisualEntity = _entities.get(building_id)
	if is_instance_valid(entity):
		entity.set_cannon_aim(building_aims[building_id])


func _process(delta: float) -> void:
	if village == null:
		return
	for unit in village.units:
		var id := str(unit["id"])
		var entity: VisualEntity = _entities.get(id)
		if not is_instance_valid(entity):
			continue
		var destination := village.grid.cell_to_world(Vector2(unit["cell"]))
		var difference := destination - entity.position
		var moving := difference.length_squared() > 1.0
		if moving:
			entity.position = entity.position.move_toward(destination, 420.0 * delta)
		entity.set_walking(moving, difference.x < -0.5)


func _create_structure(structure: Dictionary) -> VisualEntity:
	var id := str(structure["id"])
	var type := str(structure["type"])
	var footprint: Vector2i = structure["footprint"]
	var sprite_size: Vector2 = DIMENSIONS.get(type, Vector2(100, 110))
	var shadow_half_width := float(footprint.x + footprint.y) * VillageGrid.TILE_SIZE.x * 0.23
	var shadow_half_height := float(footprint.x + footprint.y) * VillageGrid.TILE_SIZE.y * 0.20
	var shadow_offset := Vector2(0.0, -float(footprint.x + footprint.y) * VillageGrid.TILE_SIZE.y * 0.25)
	var entity := VisualEntity.new()
	entity.name = "Building_" + id
	entity.position = _structure_anchor(structure)
	if type == "wall":
		entity.position.y -= 0.25  # At equal depth, the low wall sorts first.
	add_child(entity)
	entity.configure_structure(
		id,
		type,
		_texture(type),
		sprite_size,
		Vector2(shadow_half_width, shadow_half_height),
		shadow_offset,
		battle_mode and type == "cannon"
	)
	return entity


func _create_village_unit(unit: Dictionary) -> VisualEntity:
	var id := str(unit["id"])
	var type := str(unit["type"])
	var entity := VisualEntity.new()
	entity.name = "Unit_" + id
	entity.position = village.grid.cell_to_world(Vector2(unit["cell"]))
	add_child(entity)
	var frames: SpriteFrames = _frames_for(type)
	entity.configure_troop(id, type, _texture(type), DIMENSIONS.get(type, Vector2(53, 68)), frames)
	return entity


func _structure_anchor(structure: Dictionary) -> Vector2:
	var footprint: Vector2i = structure["footprint"]
	var cell: Vector2i = structure["cell"]
	var center_cell := Vector2(cell) + (Vector2(footprint) - Vector2.ONE) * 0.5
	var center := village.grid.cell_to_world(center_cell)
	var half_height := float(footprint.x + footprint.y) * VillageGrid.TILE_SIZE.y * 0.25
	return center + Vector2(0.0, half_height)


func _texture(type: String) -> Texture2D:
	if _art_cache.has(type):
		return _art_cache[type]
	var path := str(ART_PATHS.get(type, ""))
	var texture: Texture2D
	# Imported texture on normal runs / export; raw PNG as first-import fallback.
	if ResourceLoader.exists(path):
		texture = load(path)
	if texture == null and path.begins_with("res://assets/generated/"):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture == null and FALLBACK_ART.has(type):
		texture = load(FALLBACK_ART[type])
	_art_cache[type] = texture
	return texture


func _frames_for(type: String) -> SpriteFrames:
	if not TroopSpriteFrames.SHEETS.has(type):
		return null
	if _frames_cache.has(type):
		return _frames_cache[type]
	var frames := SpriteFrames.new()
	var sprite_sheet: Texture2D = TroopSpriteFrames.texture_for(type)
	for animation in ["idle", "walk", "attack", "death"]:
		frames.add_animation(animation)
		frames.set_animation_speed(animation, 9.0)
		frames.set_animation_loop(animation, animation != "death")
		var data: Array = TroopSpriteFrames.ROWS[type][animation]
		for index in range(int(data[1])):
			var atlas := AtlasTexture.new()
			atlas.atlas = sprite_sheet
			atlas.region = TroopSpriteFrames.region_for(type, animation, index)
			frames.add_frame(animation, atlas)
	_frames_cache[type] = frames
	return frames


func _sync_selection() -> void:
	for id in _entities:
		var entity: VisualEntity = _entities[id]
		if is_instance_valid(entity):
			entity.set_selected(id == selected_id)
