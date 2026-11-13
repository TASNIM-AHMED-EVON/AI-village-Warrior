extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var village := VillageModel.new()
	village.create_starter_layout()
	_check(village.grid.width == 60 and village.grid.height == 60, "starter grid is 60 by 60")
	_check(village.structures.size() == 45, "starter village has buildings, a Clan Castle and wall segments")
	_check(village.units.size() == 1 and village.units[0]["type"] == "warrior", "starter village has one Warrior")
	_check(not village.grid.is_footprint_clear(Vector2i(29, 28), Vector2i(1, 1)), "occupied building cells reject placement")
	_check(not village.grid.is_footprint_clear(Vector2i(59, 59), Vector2i(2, 2)), "out-of-bounds footprints reject placement")
	var placement := village.try_place("cannon", Vector2i(5, 5))
	_check(placement["ok"], "valid building placement succeeds")
	_check(village.get_structure_at(Vector2i(6, 6))["id"] == placement["object"]["id"], "placed footprint resolves back to building")
	_check(not village.try_place("cannon", Vector2i(6, 6))["ok"], "overlapping building placement fails")

	var json_text := JSON.stringify(village.serialize())
	var parsed: Variant = JSON.parse_string(json_text)
	_check(parsed is Dictionary, "village serializes to valid JSON")
	var restored := VillageModel.new()
	_check(restored.deserialize(parsed), "village JSON round-trips")
	_check(restored.structures.size() == village.structures.size(), "round-trip keeps all structures")
	_check(restored.units.size() == 1 and restored.units[0]["cell"] == village.units[0]["cell"], "round-trip keeps troop position")
	_check(restored.get_structure_at(Vector2i(6, 6))["id"] == placement["object"]["id"], "round-trip restores occupancy")
	_check(not restored.deserialize({"grid": {}, "structures": [], "units": []}), "malformed grid dimensions are rejected")
	# Moving a building after it has been placed.
	var mover: Dictionary = village.try_place("archer_tower", Vector2i(10, 10))["object"]
	var mover_id: String = mover["id"]
	_check(village.can_move_structure(mover_id, Vector2i(11, 10)), "a building may move onto tiles that overlap its old spot")
	_check(not village.can_move_structure(mover_id, Vector2i(29, 28)), "a building cannot move onto another building")
	_check(not village.move_structure(mover_id, Vector2i(29, 28))["ok"], "blocked move is rejected")
	_check(village.get_structure_at(Vector2i(10, 10))["id"] == mover_id, "blocked move leaves the building where it was")
	_check(village.move_structure(mover_id, Vector2i(15, 15))["ok"], "move to a clear spot succeeds")
	_check(village.get_structure_at(Vector2i(10, 10)).is_empty(), "old tiles are freed after a move")
	_check(village.get_structure_at(Vector2i(15, 15))["id"] == mover_id, "new tiles are occupied after a move")
	var moved_copy := VillageModel.new()
	_check(moved_copy.deserialize(JSON.parse_string(JSON.stringify(village.serialize()))), "moved layout round-trips")
	_check(moved_copy.get_structure_at(Vector2i(15, 15))["id"] == mover_id, "moved building keeps its new position when saved and loaded")
	# A battle copy must not touch the home layout.
	var battle_copy := VillageModel.new()
	_check(battle_copy.deserialize(village.serialize()), "battle copy builds from the home layout")
	battle_copy.damage_structure(mover_id, 999999)
	_check(village.get_structure_at(Vector2i(15, 15))["id"] == mover_id, "destroying a building in the copy leaves the home layout intact")
	if failures == 0:
		print("Village model checks passed.")
		quit(0)
	else:
		push_error("%d village model check(s) failed." % failures)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
