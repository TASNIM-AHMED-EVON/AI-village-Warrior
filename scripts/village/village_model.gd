extends RefCounted
class_name VillageModel
## Data-only village layout. No Nodes, drawing, or scene references live here.

var grid := VillageGrid.new(60, 60)
var structures: Array[Dictionary] = []
var units: Array[Dictionary] = []
var gold := 1250
var elixir := 840
var gems := 100
var army: Dictionary = {"warrior": 8, "mage": 3, "goblin": 8, "archer": 8, "tank": 2, "dragon": 0}
var troop_levels: Dictionary = {}  # troop_id -> level researched in the Laboratory (missing = level 1)
var _next_id := 1

const FULL_RESOURCE_AMOUNT := 999999
const MAX_TRAIN_BATCH := 99
const FULL_ARMY := {"warrior": 8, "mage": 3, "goblin": 8, "archer": 8, "tank": 2, "dragon": 0}


func refill_player_inventory() -> void:
	gold = FULL_RESOURCE_AMOUNT
	elixir = FULL_RESOURCE_AMOUNT
	gems = FULL_RESOURCE_AMOUNT
	# Top up to the starting army but keep any extra troops the player trained.
	for troop_id in FULL_ARMY:
		army[troop_id] = maxi(int(army.get(troop_id, 0)), int(FULL_ARMY[troop_id]))


func create_starter_layout() -> void:
	grid.clear()
	structures.clear()
	units.clear()
	gold = 1250
	elixir = 840
	gems = 100
	army = {"warrior": 8, "mage": 3, "goblin": 8, "archer": 8, "tank": 2, "dragon": 0}
	_next_id = 1
	_add_structure("town_hall", Vector2i(29, 28))
	_add_structure("cannon", Vector2i(20, 28))
	_add_structure("archer_tower", Vector2i(39, 28))
	_add_structure("gold_mine", Vector2i(34, 38))
	_add_structure("elixir_pump", Vector2i(24, 39))
	_add_structure("barracks", Vector2i(19, 39))
	for x in range(26, 36):
		_add_structure("wall", Vector2i(x, 25))
		_add_structure("wall", Vector2i(x, 35))
	for y in range(26, 35):
		_add_structure("wall", Vector2i(25, y))
		_add_structure("wall", Vector2i(35, y))
	_add_structure("clan_castle", Vector2i(28, 39))
	_add_unit("warrior", Vector2i(31, 31))


func repair_playable_state() -> bool:
	# Recover saves left without a village or an army so the player can continue.
	var saved_gold := gold
	var saved_elixir := elixir
	var saved_gems := gems
	var saved_army := army.duplicate(true)
	var saved_levels := troop_levels.duplicate(true)
	var has_town_hall := false
	for structure in structures:
		if structure.get("type", "") == "town_hall":
			has_town_hall = true
			break
	var repaired := false
	if structures.is_empty() or not has_town_hall:
		create_starter_layout()
		gold = saved_gold
		elixir = saved_elixir
		gems = saved_gems
		army = saved_army
		troop_levels = saved_levels
		repaired = true
	var total_troops := 0
	for troop_id in TroopCatalog.all_ids():
		total_troops += maxi(0, int(army.get(troop_id, 0)))
	if total_troops == 0:
		army = {"warrior": 8, "mage": 3, "goblin": 8, "archer": 8, "tank": 2, "dragon": 0}
		repaired = true
	return repaired


func try_place(building_id: String, cell: Vector2i) -> Dictionary:
	var definition := BuildingCatalog.get_definition(building_id)
	if definition.is_empty():
		return {"ok": false, "reason": "Unknown building."}
	var cost := int(definition.get("cost", 0))
	if gold < cost:
		return {"ok": false, "reason": "Not enough gold. Collect from your mines or choose a cheaper building."}
	var footprint: Vector2i = definition["footprint"]
	var object_id := "structure_%d" % _next_id
	if not grid.occupy(cell, footprint, object_id):
		return {"ok": false, "reason": "That space is outside the village or already occupied."}
	var entry := _make_structure(building_id, cell, definition, object_id)
	structures.append(entry)
	gold -= cost
	_next_id += 1
	return {"ok": true, "object": entry}


func can_move_structure(object_id: String, new_cell: Vector2i) -> bool:
	for structure in structures:
		if structure["id"] != object_id:
			continue
		var old_cell: Vector2i = structure["cell"]
		var footprint: Vector2i = structure["footprint"]
		# Free the building's own tiles first so it may overlap its old position.
		grid.release(old_cell, footprint, object_id)
		var clear := grid.is_footprint_clear(new_cell, footprint)
		grid.occupy(old_cell, footprint, object_id)
		return clear
	return false


func move_structure(object_id: String, new_cell: Vector2i) -> Dictionary:
	for structure in structures:
		if structure["id"] != object_id:
			continue
		var old_cell: Vector2i = structure["cell"]
		var footprint: Vector2i = structure["footprint"]
		if new_cell == old_cell:
			return {"ok": false, "reason": "The building is already there."}
		grid.release(old_cell, footprint, object_id)
		if not grid.occupy(new_cell, footprint, object_id):
			grid.occupy(old_cell, footprint, object_id)
			return {"ok": false, "reason": "That space is outside the village or already occupied."}
		structure["cell"] = new_cell
		return {"ok": true, "structure": structure}
	return {"ok": false, "reason": "Building no longer exists."}


func collect_from_structure(object_id: String) -> Dictionary:
	for structure in structures:
		if structure["id"] != object_id:
			continue
		var amount := 0
		if structure["type"] == "gold_mine":
			amount = 120 * int(structure.get("level", 1))
			gold += amount
		elif structure["type"] == "elixir_pump":
			amount = 120 * int(structure.get("level", 1))
			elixir += amount
		else:
			return {"ok": false, "reason": "This building has nothing to collect."}
		return {"ok": true, "amount": amount, "resource": "gold" if structure["type"] == "gold_mine" else "elixir"}
	return {"ok": false, "reason": "Building no longer exists."}


func upgrade_structure(object_id: String) -> Dictionary:
	for structure in structures:
		if structure["id"] != object_id:
			continue
		var cost := 400 * int(structure.get("level", 1))
		if gold < cost:
			return {"ok": false, "reason": "Upgrade needs %d gold." % cost}
		gold -= cost
		structure["level"] = int(structure.get("level", 1)) + 1
		structure["max_hp"] = int(structure["max_hp"]) + maxi(60, int(int(structure["max_hp"]) / 5.0))
		structure["hp"] = structure["max_hp"]
		return {"ok": true, "cost": cost, "structure": structure}
	return {"ok": false, "reason": "Building no longer exists."}


func set_castle_garrison(object_id: String, preset_index: int) -> Dictionary:
	for structure in structures:
		if structure["id"] != object_id:
			continue
		if str(structure["type"]) != ClanCastle.BUILDING_ID:
			return {"ok": false, "reason": "Only a Clan Castle holds a garrison."}
		structure["garrison"] = ClanCastle.preset_garrison(preset_index)
		return {"ok": true, "garrison": structure["garrison"], "preset": ClanCastle.preset_name(preset_index)}
	return {"ok": false, "reason": "Building no longer exists."}


func cycle_castle_garrison(object_id: String) -> Dictionary:
	for structure in structures:
		if structure["id"] != object_id:
			continue
		var current := ClanCastle.preset_index_of(structure.get("garrison", {}))
		return set_castle_garrison(object_id, current + 1)
	return {"ok": false, "reason": "Building no longer exists."}


func train_troop(troop_id: String) -> Dictionary:
	return train_troops(troop_id, 1)


## Trains `count` troops of one type at once, paid for in a single purchase.
func train_troops(troop_id: String, count: int) -> Dictionary:
	var definition := TroopCatalog.get_definition(troop_id)
	if definition.is_empty():
		return {"ok": false, "reason": "Unknown troop type."}
	var barracks_count := 0
	for structure in structures:
		if structure["type"] == "barracks":
			barracks_count += 1
	if barracks_count == 0:
		return {"ok": false, "reason": "Build a Barracks before training troops."}
	if count < 1:
		return {"ok": false, "reason": "Choose at least one troop to train."}
	count = mini(count, MAX_TRAIN_BATCH)
	var cost := int(definition["cost"]) * count
	if elixir < cost:
		return {"ok": false, "reason": "Not enough elixir. %d %s need %d." % [count, definition["name"], cost]}
	elixir -= cost
	army[troop_id] = int(army.get(troop_id, 0)) + count
	return {"ok": true, "troop": definition, "count": army[troop_id], "added": count, "cost": cost}


func troop_level(troop_id: String) -> int:
	return clampi(int(troop_levels.get(troop_id, 1)), 1, TroopCatalog.MAX_LEVEL)


func laboratory_level() -> int:
	var best := 0
	for structure in structures:
		if structure["type"] == "laboratory":
			best = maxi(best, int(structure.get("level", 1)))
	return best


## Highest troop level the current Laboratory can research (0 when there is no Laboratory).
func max_troop_level() -> int:
	var lab_level := laboratory_level()
	if lab_level == 0:
		return 0
	return mini(TroopCatalog.MAX_LEVEL, lab_level + 2)


func upgrade_troop(troop_id: String) -> Dictionary:
	var definition := TroopCatalog.get_definition(troop_id)
	if definition.is_empty():
		return {"ok": false, "reason": "Unknown troop type."}
	if laboratory_level() == 0:
		return {"ok": false, "reason": "Build a Laboratory before researching troops."}
	var level := troop_level(troop_id)
	if level >= TroopCatalog.MAX_LEVEL:
		return {"ok": false, "reason": "%s is already at the maximum level." % definition["name"]}
	if level >= max_troop_level():
		return {"ok": false, "reason": "Upgrade the Laboratory to research %s beyond level %d." % [definition["name"], level]}
	var cost := TroopCatalog.upgrade_cost(troop_id, level)
	if elixir < cost:
		return {"ok": false, "reason": "Research needs %d elixir." % cost}
	elixir -= cost
	troop_levels[troop_id] = level + 1
	return {"ok": true, "troop": definition, "level": level + 1, "cost": cost}


func move_unit(unit_id: String, destination: Vector2i) -> Dictionary:
	if not grid.contains_cell(destination):
		return {"ok": false, "reason": "That destination is outside the village."}
	if grid.occupied.has(destination):
		return {"ok": false, "reason": "That tile is occupied by a building."}
	for unit in units:
		if unit["id"] == unit_id:
			for other in units:
				if other["id"] != unit_id and other["cell"] == destination:
					return {"ok": false, "reason": "Another troop is already there."}
			unit["cell"] = destination
			return {"ok": true, "unit": unit}
	return {"ok": false, "reason": "That troop is no longer in the village."}


func get_structure_at(cell: Vector2i) -> Dictionary:
	var object_id := grid.get_object_id_at(cell)
	if object_id.is_empty():
		return {}
	for structure in structures:
		if structure["id"] == object_id:
			return structure
	return {}


func damage_structure(object_id: String, damage: int) -> bool:
	for index in range(structures.size()):
		if structures[index]["id"] != object_id:
			continue
		structures[index]["hp"] = maxi(0, int(structures[index]["hp"]) - maxi(0, damage))
		if structures[index]["hp"] == 0:
			var structure: Dictionary = structures[index]
			grid.release(structure["cell"], structure["footprint"], object_id)
			structures.remove_at(index)
		return true
	return false


func serialize() -> Dictionary:
	var serialized_structures: Array[Dictionary] = []
	for structure in structures:
		serialized_structures.append(_serialize_object(structure))
	var serialized_units: Array[Dictionary] = []
	for unit in units:
		serialized_units.append(_serialize_object(unit))
	return {
		"version": 1,
		"resources": {"gold": gold, "elixir": elixir, "gems": gems},
		"army": army.duplicate(true),
		"troop_levels": troop_levels.duplicate(true),
		"grid": grid.to_dict(),
		"structures": serialized_structures,
		"units": serialized_units,
	}


func deserialize(source: Dictionary) -> bool:
	if not source.has("grid") or not source.has("structures") or not source.has("units"):
		return false
	var grid_data: Dictionary = source["grid"]
	var next_grid := VillageGrid.new(int(grid_data.get("width", 0)), int(grid_data.get("height", 0)))
	if next_grid.width <= 0 or next_grid.height <= 0:
		return false
	var next_structures: Array[Dictionary] = []
	var max_id := 0
	for raw_structure in source["structures"]:
		if not raw_structure is Dictionary:
			return false
		var building_id := str(raw_structure.get("type", ""))
		var definition := BuildingCatalog.get_definition(building_id)
		var cell_data: Variant = raw_structure.get("cell", {})
		if definition.is_empty() or not cell_data is Dictionary:
			return false
		var cell := Vector2i(int(cell_data.get("x", -1)), int(cell_data.get("y", -1)))
		var object_id := str(raw_structure.get("id", ""))
		var footprint: Vector2i = definition["footprint"]
		if object_id.is_empty() or not next_grid.occupy(cell, footprint, object_id):
			return false
		var entry := _make_structure(building_id, cell, definition, object_id)
		var level := maxi(1, int(raw_structure.get("level", 1)))
		var max_hp := int(definition["hp"])
		for _upgrade_index in range(1, level):
			max_hp += maxi(60, int(max_hp / 5.0))
		entry["hp"] = clampi(int(raw_structure.get("hp", max_hp)), 0, max_hp)
		entry["max_hp"] = max_hp
		entry["level"] = level
		if building_id == ClanCastle.BUILDING_ID:
			entry["garrison"] = ClanCastle.sanitize(raw_structure.get("garrison", null))
		next_structures.append(entry)
		max_id = maxi(max_id, _numeric_id(object_id))
	var next_units: Array[Dictionary] = []
	for raw_unit in source["units"]:
		if not raw_unit is Dictionary:
			return false
		var troop_id := str(raw_unit.get("type", ""))
		var definition := TroopCatalog.get_definition(troop_id)
		var cell_data: Variant = raw_unit.get("cell", {})
		if definition.is_empty() or not cell_data is Dictionary:
			return false
		var cell := Vector2i(int(cell_data.get("x", -1)), int(cell_data.get("y", -1)))
		if not next_grid.contains_cell(cell):
			return false
		var unit_id := str(raw_unit.get("id", ""))
		if unit_id.is_empty():
			return false
		next_units.append({
			"id": unit_id, "type": troop_id, "name": definition["name"], "cell": cell,
			"hp": clampi(int(raw_unit.get("hp", definition["hp"])), 0, int(definition["hp"])),
			"max_hp": int(definition["hp"]),
		})
		max_id = maxi(max_id, _numeric_id(unit_id))
	grid = next_grid
	structures = next_structures
	units = next_units
	var resources: Dictionary = source.get("resources", {})
	gold = maxi(0, int(resources.get("gold", 1250)))
	elixir = maxi(0, int(resources.get("elixir", 840)))
	gems = maxi(0, int(resources.get("gems", 100)))
	army = {"warrior": 8, "mage": 3, "goblin": 8, "archer": 8, "tank": 2, "dragon": 0}
	var saved_army: Dictionary = source.get("army", {})
	for troop_id in TroopCatalog.all_ids():
		army[troop_id] = maxi(0, int(saved_army.get(troop_id, int(army.get(troop_id, 0)))))
	troop_levels = {}
	var saved_levels: Variant = source.get("troop_levels", {})
	if saved_levels is Dictionary:
		for troop_id in TroopCatalog.all_ids():
			var saved_level := clampi(int(saved_levels.get(troop_id, 1)), 1, TroopCatalog.MAX_LEVEL)
			if saved_level > 1:
				troop_levels[troop_id] = saved_level
	_next_id = max_id + 1
	return true


func _add_structure(building_id: String, cell: Vector2i) -> void:
	var definition := BuildingCatalog.get_definition(building_id)
	var object_id := "structure_%d" % _next_id
	var footprint: Vector2i = definition["footprint"]
	assert(grid.occupy(cell, footprint, object_id), "Invalid starter structure placement: %s" % building_id)
	structures.append(_make_structure(building_id, cell, definition, object_id))
	_next_id += 1


func _make_structure(building_id: String, cell: Vector2i, definition: Dictionary, object_id: String = "") -> Dictionary:
	if object_id.is_empty():
		object_id = "structure_%d" % _next_id
		_next_id += 1
	var entry := {
		"id": object_id,
		"type": building_id,
		"name": definition["name"],
		"cell": cell,
		"footprint": definition["footprint"],
		"hp": definition["hp"],
		"max_hp": definition["hp"],
		"level": 1,
	}
	if building_id == ClanCastle.BUILDING_ID:
		entry["garrison"] = ClanCastle.default_garrison()
	return entry


func _add_unit(troop_id: String, cell: Vector2i) -> void:
	var definition := TroopCatalog.get_definition(troop_id)
	units.append({
		"id": "unit_%d" % _next_id,
		"type": troop_id,
		"name": definition["name"],
		"cell": cell,
		"hp": definition["hp"],
		"max_hp": definition["hp"],
	})
	_next_id += 1


func _serialize_object(entry: Dictionary) -> Dictionary:
	var saved := entry.duplicate(true)
	var cell: Vector2i = entry["cell"]
	saved["cell"] = {"x": cell.x, "y": cell.y}
	if entry.has("footprint"):
		var footprint: Vector2i = entry["footprint"]
		saved["footprint"] = {"x": footprint.x, "y": footprint.y}
	return saved


func _numeric_id(object_id: String) -> int:
	var pieces := object_id.split("_")
	return int(pieces[pieces.size() - 1]) if pieces.size() > 1 else 0
