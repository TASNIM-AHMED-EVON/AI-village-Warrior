extends SceneTree

const BATTLE_SEARCH := preload("res://scripts/ai/battle_search_ai.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var village := VillageModel.new()
	village.grid.clear()
	village.structures.clear()
	village.units.clear()
	_add_structure(village, "hall", "town_hall", Vector2i(30, 28), Vector2i(3, 3))
	for y in range(village.grid.height):
		_add_structure(village, "wall_%d" % y, "wall", Vector2i(25, y), Vector2i.ONE)

	var actors := Node2D.new()
	var targets := Node2D.new()
	root.add_child(actors)
	root.add_child(targets)
	var battle := BattleManager.new()
	root.add_child(battle)
	battle.begin_battle(village, actors, targets)
	_check(not battle.is_valid_deployment_cell(Vector2i(26, 29)), "deployment is blocked within five tiles of a structure")
	_check(battle.is_valid_deployment_cell(Vector2i(20, 30)), "deployment is allowed at the five-tile boundary")
	_check(battle.deploy("warrior", Vector2i(20, 30)), "legal troop deployment starts the active battle")
	_check(battle.attacker_units.size() == 1, "battle manager creates the deployed troop")
	battle.settle_planning()  # Planning is spread over a few frames; let it finish.
	if not battle.attacker_units.is_empty():
		var actor := battle.attacker_units[0]
		_check(is_instance_valid(actor.target) and actor.target is BattleBuildingTarget, "attacker receives a live building target")
		_check(actor.target.building_type == "wall", "attacker targets the blocking wall before the Town Hall")
		_check(not actor.movement_path.is_empty(), "attacker receives a path to the wall for breaching")
		_check(battle.last_ai_decision.get("algorithm", "") == BATTLE_SEARCH.MINIMAX, "Minimax makes the default strategic target decision")
	var starting_time := battle.time_remaining
	battle.set_paused(true)
	battle._process(2.0)
	_check(battle.time_remaining == starting_time, "paused battle stops the authoritative simulation clock")
	battle.set_paused(false)
	battle.set_speed(2.0)
	battle._process(1.0)
	_check(is_equal_approx(battle.time_remaining, starting_time - 2.0), "battle speed scales the single simulation clock")
	battle._finish(BattleManager.Phase.DEFEAT)
	battle.free()
	actors.free()
	targets.free()
	if failures == 0:
		print("Battle rule checks passed.")
		quit(0)
	else:
		push_error("%d battle rule check(s) failed." % failures)
		quit(1)


func _add_structure(village: VillageModel, object_id: String, building_id: String, cell: Vector2i, footprint: Vector2i) -> void:
	var definition := BuildingCatalog.get_definition(building_id)
	if not village.grid.occupy(cell, footprint, object_id):
		push_error("Test fixture structure overlaps at %s." % str(cell))
		return
	village.structures.append({
		"id": object_id,
		"type": building_id,
		"name": str(definition.get("name", building_id)),
		"cell": cell,
		"footprint": footprint,
		"hp": int(definition.get("hp", 250)),
		"max_hp": int(definition.get("hp", 250)),
		"level": 1,
	})


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
