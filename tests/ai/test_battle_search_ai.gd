extends SceneTree

const BATTLE_SEARCH := preload("res://scripts/ai/battle_search_ai.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := VillageGrid.new(20, 20)
	var attacker := TroopActor.new()
	root.add_child(attacker)
	_check(attacker.configure("warrior"), "search attacker configures")
	attacker.global_position = grid.cell_to_world(Vector2(8, 8))
	var structures: Array[Dictionary] = [
		_structure("hall", "town_hall", Vector2i(10, 10), Vector2i(3, 3), 800),
		_structure("cannon", "cannon", Vector2i(8, 9), Vector2i.ONE, 300),
		_structure("mine", "gold_mine", Vector2i(14, 10), Vector2i(2, 2), 180),
	]
	var targets: Array[BattleBuildingTarget] = []
	for structure in structures:
		var target := BattleBuildingTarget.new()
		root.add_child(target)
		target.configure(structure, grid)
		targets.append(target)
	var defense_actions: Array[Dictionary] = [{"id": "cannon", "damage": 42, "range": 330.0, "hit_probability": 0.85}]
	var original_hp := attacker.hp
	var result := BATTLE_SEARCH.select_target(attacker, targets, structures, defense_actions, BATTLE_SEARCH.MINIMAX)
	_check(["hall", "cannon", "mine"].has(str(result.get("target_id", ""))), "Minimax selects a legal target")
	_check(int(result.get("nodes", 0)) > 0, "Minimax reports visited search nodes")
	_check(int(result.get("nodes", 999999)) <= BATTLE_SEARCH.MAX_NODES, "search respects node budget")
	_check(attacker.hp == original_hp, "search does not mutate the live troop")
	_check(int(structures[0].hp) == 800, "search does not mutate live building data")
	var alpha_beta := BATTLE_SEARCH.select_target(attacker, targets, structures, defense_actions, BATTLE_SEARCH.ALPHA_BETA)
	_check(str(alpha_beta.get("target_id", "")).length() > 0, "Alpha-Beta returns a legal action")
	_check(int(alpha_beta.get("pruned", 0)) >= 0, "Alpha-Beta reports pruning metrics")
	var expectimax := BATTLE_SEARCH.select_target(attacker, targets, structures, defense_actions, BATTLE_SEARCH.EXPECTIMAX)
	_check(str(expectimax.get("target_id", "")).length() > 0, "Expectimax returns a legal action")
	_check(float(expectimax.get("time_ms", 999.0)) < 500.0, "bounded searches finish within the test watchdog")
	for target in targets:
		target.free()
	attacker.free()
	if failures == 0:
		print("Battle AI search checks passed.")
		quit(0)
	else:
		push_error("%d AI search check(s) failed." % failures)
		quit(1)


func _structure(id: String, type: String, cell: Vector2i, footprint: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "type": type, "cell": cell, "footprint": footprint, "hp": hp, "max_hp": hp}


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
