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
	# Trained troops survive the inventory top-up that runs when a scene opens.
	var trainer := VillageModel.new()
	trainer.create_starter_layout()
	_check(trainer.train_troop("warrior")["ok"], "training a troop works with a Barracks")
	trainer.refill_player_inventory()
	_check(int(trainer.army["warrior"]) == 9, "refill keeps the extra trained warrior (got %d)" % int(trainer.army["warrior"]))
	_check(int(trainer.army["mage"]) == 3, "refill still tops other troops up to the starting army")
	# Laboratory: researching troop levels.
	_check(not trainer.upgrade_troop("warrior")["ok"], "research needs a Laboratory")
	var lab_result: Dictionary = trainer.try_place("laboratory", Vector2i(5, 40))
	_check(lab_result["ok"], "a Laboratory can be placed")
	_check(trainer.max_troop_level() == 3, "a level 1 Laboratory allows troop level 3")
	var base_damage := int(TroopCatalog.get_definition("warrior")["damage"])
	_check(trainer.troop_level("warrior") == 1, "troops start at level 1")
	_check(trainer.upgrade_troop("warrior")["ok"], "first research succeeds")
	_check(trainer.upgrade_troop("warrior")["ok"], "second research succeeds")
	_check(trainer.troop_level("warrior") == 3, "warrior reached level 3")
	_check(not trainer.upgrade_troop("warrior")["ok"], "level cap stops research until the Laboratory is upgraded")
	_check(TroopCatalog.damage_at_level("warrior", 3) > base_damage, "a higher level deals more damage per hit")
	_check(TroopCatalog.hp_at_level("warrior", 3) > int(TroopCatalog.get_definition("warrior")["hp"]), "a higher level has more hit points")
	var lab_id: String = lab_result["object"]["id"]
	_check(trainer.upgrade_structure(lab_id)["ok"], "the Laboratory can be upgraded")
	_check(trainer.max_troop_level() == 4, "an upgraded Laboratory raises the troop level cap")
	var research_copy := VillageModel.new()
	_check(research_copy.deserialize(JSON.parse_string(JSON.stringify(trainer.serialize()))), "researched village round-trips")
	_check(research_copy.troop_level("warrior") == 3, "troop levels survive save and load")
	_check(int(research_copy.army["warrior"]) == 9, "trained troop count survives save and load")
	var actor := TroopActor.new()
	_check(actor.configure("warrior", 3), "a levelled troop can be configured")
	_check(actor.damage == TroopCatalog.damage_at_level("warrior", 3) and actor.max_hp == TroopCatalog.hp_at_level("warrior", 3), "levelled troop uses scaled stats")
	actor.free()
	# Bulk training and the dragon.
	var bulk := VillageModel.new()
	bulk.create_starter_layout()
	bulk.refill_player_inventory()
	var elixir_before := bulk.elixir
	var batch: Dictionary = bulk.train_troops("archer", 10)
	_check(batch["ok"] and int(batch["added"]) == 10, "ten archers can be trained in one batch")
	_check(int(bulk.army["archer"]) == 18, "bulk training adds the whole batch to the army")
	_check(bulk.elixir == elixir_before - 10 * int(TroopCatalog.get_definition("archer")["cost"]), "bulk training charges for every troop")
	_check(not bulk.train_troops("archer", 0)["ok"], "training zero troops is rejected")
	_check(bulk.train_troops("dragon", 3)["ok"] and int(bulk.army["dragon"]) == 3, "dragons can be trained at the Barracks")
	bulk.elixir = 100
	var broke: Dictionary = bulk.train_troops("dragon", 5)
	_check(not broke["ok"] and int(bulk.army["dragon"]) == 3 and bulk.elixir == 100, "an unaffordable batch changes nothing")
	var dragon_copy := VillageModel.new()
	_check(dragon_copy.deserialize(JSON.parse_string(JSON.stringify(bulk.serialize()))) and int(dragon_copy.army["dragon"]) == 3, "dragon count survives save and load")
	dragon_copy.refill_player_inventory()
	_check(int(dragon_copy.army["dragon"]) == 3, "refill keeps trained dragons")
	var dragon := TroopActor.new()
	_check(dragon.configure("dragon") and dragon.is_flying and dragon.projectile_kind == "fire", "dragon configures as a flying fire breather")
	_check(dragon.attack_interval < 0.5, "dragon breath ticks continuously")
	dragon.free()
	# Resetting every level back to 1.
	var resetter := VillageModel.new()
	resetter.create_starter_layout()
	resetter.refill_player_inventory()
	var base_hp := {}
	for structure in resetter.structures:
		base_hp[structure["id"]] = int(structure["max_hp"])
	for structure in resetter.structures:
		resetter.upgrade_structure(structure["id"])
		resetter.upgrade_structure(structure["id"])
	resetter.try_place("laboratory", Vector2i(5, 40))
	resetter.upgrade_troop("warrior")
	var cells_before := resetter.structures.size()
	_check(resetter.reset_all_levels() > 0, "reset reports what it changed")
	var all_level_one := true
	var all_base_hp := true
	for structure in resetter.structures:
		if int(structure["level"]) != 1: all_level_one = false
		if base_hp.has(structure["id"]) and int(structure["max_hp"]) != int(base_hp[structure["id"]]): all_base_hp = false
		if int(structure["hp"]) != int(structure["max_hp"]): all_base_hp = false
	_check(all_level_one, "every building is level 1 after a reset")
	_check(all_base_hp, "every building is back to its base hit points")
	_check(resetter.troop_level("warrior") == 1, "troop levels are reset")
	_check(resetter.structures.size() == cells_before, "reset keeps the village layout")
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
