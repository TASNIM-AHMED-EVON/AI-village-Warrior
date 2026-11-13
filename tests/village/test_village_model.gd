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
