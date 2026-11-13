extends SceneTree
## Proves the tactical search is genuinely adversarial: the defenders' reply depends on WHICH target
## the acting troop chooses, for both the attacker-side and the Clan Castle defender-side search.

const BATTLE_SEARCH := preload("res://scripts/ai/battle_search_ai.gd")

var failures := 0
var grid := VillageGrid.new(60, 60)
var _nodes: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_reply_depends_on_target()
	_test_castle_garrison_exposure()
	_test_attackers_hunt_squishy_defenders()
	_test_no_free_escape_when_under_fire()
	_test_defender_side_search()
	_test_algorithms_agree_and_prune()
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	if failures == 0:
		print("Adversarial search checks passed.")
		quit(0)
	else:
		push_error("%d adversarial search check(s) failed." % failures)
		quit(1)


func _test_reply_depends_on_target() -> void:
	var attacker := _troop("warrior", Vector2i(52, 5))  # Approaching from far away, outside every defense's reach.
	var structures: Array[Dictionary] = [
		_structure("mine_near_cannon", "gold_mine", Vector2i(10, 10), Vector2i(2, 2), 300),
		_structure("mine_far", "gold_mine", Vector2i(40, 40), Vector2i(2, 2), 300),
	]
	var targets := _targets(structures)
	# The near mine is cheaper to reach, so a plain value-per-route ranking prefers it.
	var costs := {"mine_near_cannon": 5, "mine_far": 40}
	var cannon_pos := grid.cell_to_world(Vector2(11, 11))
	var positional: Array[Dictionary] = [{"id": "cannon", "damage": 42, "range": 330.0, "hit_probability": 0.85, "position": cannon_pos}]
	var legacy: Array[Dictionary] = [{"id": "cannon", "damage": 42, "range": 330.0, "hit_probability": 0.85}]
	for algorithm in BATTLE_SEARCH.ALGORITHMS:
		var result := BATTLE_SEARCH.select_target(attacker, targets, structures, positional, algorithm, costs)
		_check(str(result["target_id"]) == "mine_far", "%s avoids the target the cannon covers" % algorithm)
	var legacy_result := BATTLE_SEARCH.select_target(attacker, targets, structures, legacy, BATTLE_SEARCH.MINIMAX, costs)
	_check(str(legacy_result["target_id"]) == "mine_near_cannon", "a defense without a position answers every target, so route cost decides")
	var no_defense: Array[Dictionary] = []
	var undefended := BATTLE_SEARCH.select_target(attacker, targets, structures, no_defense, BATTLE_SEARCH.MINIMAX, costs)
	_check(str(undefended["target_id"]) == "mine_near_cannon", "without defenders the cheaper target wins")


func _test_castle_garrison_exposure() -> void:
	var castle_pos := grid.cell_to_world(Vector2(20, 20))
	var structures: Array[Dictionary] = [
		_structure("tower_by_castle", "archer_tower", Vector2i(21, 21), Vector2i.ONE, 360),
		_structure("barracks_away", "barracks", Vector2i(50, 50), Vector2i(3, 2), 500),
	]
	var targets := _targets(structures)
	var garrison: Array[Dictionary] = [{"id": "garrison", "hit_probability": 0.85, "members": [
		{"target_id": "", "damage": 28.0, "position": castle_pos, "range": ClanCastle.TRIGGER_RADIUS},
	]}]
	var warrior := _troop("warrior", Vector2i(52, 5))
	var tank := _troop("tank", Vector2i(52, 6))
	var warrior_pick := BATTLE_SEARCH.select_target(warrior, targets, structures, garrison, BATTLE_SEARCH.MINIMAX)
	var tank_pick := BATTLE_SEARCH.select_target(tank, targets, structures, garrison, BATTLE_SEARCH.MINIMAX)
	_check(str(warrior_pick["target_id"]) == "barracks_away", "a fragile Warrior stays out of the Clan Castle's reach")
	_check(str(tank_pick["target_id"]) == "tower_by_castle", "a Tank can afford to dive into the Clan Castle's reach")
	var no_garrison: Array[Dictionary] = []
	var free_pick := BATTLE_SEARCH.select_target(warrior, targets, structures, no_garrison, BATTLE_SEARCH.MINIMAX)
	_check(str(free_pick["target_id"]) == "tower_by_castle", "with no garrison the Warrior takes the Archer Tower")


func _test_attackers_hunt_squishy_defenders() -> void:
	var structures: Array[Dictionary] = [_structure("tower", "archer_tower", Vector2i(30, 30), Vector2i.ONE, 360)]
	var targets := _targets(structures)
	var attacker := _troop("warrior", Vector2i(20, 30))
	var archer_defender := _troop("archer", Vector2i(24, 30))
	archer_defender.team = TroopActor.Team.DEFENDER
	var tank_defender := _troop("tank", Vector2i(24, 31))
	tank_defender.team = TroopActor.Team.DEFENDER
	var no_defense: Array[Dictionary] = []
	var squishy: Array[TroopActor] = [archer_defender]
	var pick_archer := BATTLE_SEARCH.select_target(attacker, targets, structures, no_defense, BATTLE_SEARCH.ALPHA_BETA, {}, squishy)
	_check(str(pick_archer["target_id"]) == BATTLE_SEARCH.defender_target_id(archer_defender), "attackers prioritise a squishy defending Archer over a tower")
	var tanky: Array[TroopActor] = [tank_defender]
	var pick_tank := BATTLE_SEARCH.select_target(attacker, targets, structures, no_defense, BATTLE_SEARCH.ALPHA_BETA, {}, tanky)
	_check(str(pick_tank["target_id"]) == "tower", "attackers ignore a defending Tank and keep hitting the tower")
	# Killing a defender removes its damage from later volleys.
	var garrison: Array[Dictionary] = [{"id": "garrison", "hit_probability": 0.85, "members": [
		{"target_id": BATTLE_SEARCH.defender_target_id(archer_defender), "damage": 60.0, "position": archer_defender.global_position, "range": 400.0},
	]}]
	var with_threat := BATTLE_SEARCH.select_target(attacker, targets, structures, garrison, BATTLE_SEARCH.MINIMAX, {}, squishy)
	_check(str(with_threat["target_id"]) == BATTLE_SEARCH.defender_target_id(archer_defender), "attackers kill the defender that is shooting them")
	_check(float(archer_defender.hp) == float(archer_defender.max_hp), "searching never damages the live defender")


func _test_no_free_escape_when_under_fire() -> void:
	var castle_pos := grid.cell_to_world(Vector2(20, 20))
	var structures: Array[Dictionary] = [_structure("far_cannon", "cannon", Vector2i(52, 52), Vector2i.ONE, 420)]
	var targets := _targets(structures)
	var warrior := _troop("warrior", Vector2i(21, 21))  # Standing right at the castle, already in reach.
	var archer := _troop("archer", Vector2i(22, 21))
	archer.team = TroopActor.Team.DEFENDER
	var archer_key := BATTLE_SEARCH.defender_target_id(archer)
	var garrison: Array[Dictionary] = [{"id": "garrison", "hit_probability": 0.85, "members": [
		{"target_id": archer_key, "damage": 60.0, "position": castle_pos, "range": ClanCastle.LEASH_RADIUS},
	]}]
	var squishy: Array[TroopActor] = [archer]
	var under_fire := BATTLE_SEARCH.select_target(warrior, targets, structures, garrison, BATTLE_SEARCH.MINIMAX, {}, squishy)
	_check(str(under_fire["target_id"]) == archer_key, "a troop already under fire fights the shooter instead of running to a far target")
	var approaching := _troop("warrior", Vector2i(55, 52))
	var approaching_pick := BATTLE_SEARCH.select_target(approaching, targets, structures, garrison, BATTLE_SEARCH.MINIMAX, {}, squishy)
	_check(str(approaching_pick["target_id"]) == "far_cannon", "a troop that is still out of reach keeps to the safe far target")


func _test_defender_side_search() -> void:
	var defender := _troop("warrior", Vector2i(14, 30))
	defender.team = TroopActor.Team.DEFENDER
	# Squishy, dangerous Mage versus a Tank at the same distance.
	var mage := _troop("mage", Vector2i(17, 30))
	var tank := _troop("tank", Vector2i(17, 31))
	var both: Array[TroopActor] = [tank, mage]
	for algorithm in BATTLE_SEARCH.ALGORITHMS:
		var result := BATTLE_SEARCH.select_defender_target(defender, both, algorithm)
		_check(str(result["target_id"]) == BATTLE_SEARCH.attacker_target_id(mage), "%s defender picks the Mage over the Tank" % algorithm)
	# Crowd avoidance: a lone Warrior far away versus an identical Warrior inside a pack of Archers.
	var crowded := _troop("warrior", Vector2i(34, 30))
	var lone := _troop("warrior", Vector2i(10, 10))
	var pack: Array[TroopActor] = [crowded, lone]
	for i in range(5):
		pack.append(_troop("archer", Vector2i(35 + i % 2, 30 + i % 3)))
	for algorithm in BATTLE_SEARCH.ALGORITHMS:
		var result := BATTLE_SEARCH.select_defender_target(defender, pack, algorithm)
		_check(str(result["target_id"]) == BATTLE_SEARCH.attacker_target_id(lone), "%s defender avoids diving into a pack of Archers" % algorithm)
	var none: Array[TroopActor] = []
	var empty := BATTLE_SEARCH.select_defender_target(defender, none)
	_check(str(empty["target_id"]) == "", "defender search with no attackers returns no target")
	_check(defender.hp == defender.max_hp and mage.hp == mage.max_hp, "defender search never mutates live troops")


func _test_algorithms_agree_and_prune() -> void:
	var attacker := _troop("warrior", Vector2i(52, 5))
	var structures: Array[Dictionary] = []
	for i in range(6):
		structures.append(_structure("s%d" % i, "gold_mine" if i % 2 == 0 else "cannon", Vector2i(12 + i * 4, 12), Vector2i(2, 2), 300 + i * 20))
	var targets := _targets(structures)
	var defenses: Array[Dictionary] = []
	for i in range(3):
		defenses.append({"id": "d%d" % i, "damage": 30, "range": 600.0, "hit_probability": 0.85, "position": grid.cell_to_world(Vector2(14 + i * 6, 14))})
	var minimax := BATTLE_SEARCH.select_target(attacker, targets, structures, defenses, BATTLE_SEARCH.MINIMAX)
	var alpha_beta := BATTLE_SEARCH.select_target(attacker, targets, structures, defenses, BATTLE_SEARCH.ALPHA_BETA)
	var expectimax := BATTLE_SEARCH.select_target(attacker, targets, structures, defenses, BATTLE_SEARCH.EXPECTIMAX)
	_check(str(minimax["target_id"]) == str(alpha_beta["target_id"]), "Alpha-Beta chooses exactly what Minimax chooses")
	_check(int(alpha_beta["depth"]) >= int(minimax["depth"]), "Alpha-Beta searches at least as deep as Minimax in the same budget")
	_check(int(alpha_beta["pruned"]) > 0, "Alpha-Beta prunes branches when several defenders can answer")
	_check(int(minimax["pruned"]) == 0, "plain Minimax never prunes")
	_check(str(expectimax["target_id"]) != "", "Expectimax returns a target")
	for result in [minimax, alpha_beta, expectimax]:
		_check(int(result["nodes"]) <= BATTLE_SEARCH.MAX_NODES + 8, "%s stays inside the node budget" % result["algorithm"])


func _troop(troop_id: String, cell: Vector2i) -> TroopActor:
	var actor := TroopActor.new()
	root.add_child(actor)
	_nodes.append(actor)
	actor.configure(troop_id)
	actor.global_position = grid.cell_to_world(Vector2(cell))
	return actor


func _targets(structures: Array[Dictionary]) -> Array[BattleBuildingTarget]:
	var targets: Array[BattleBuildingTarget] = []
	for structure in structures:
		var target := BattleBuildingTarget.new()
		root.add_child(target)
		_nodes.append(target)
		target.configure(structure, grid)
		targets.append(target)
	return targets


func _structure(id: String, type: String, cell: Vector2i, footprint: Vector2i, hp: int) -> Dictionary:
	return {"id": id, "type": type, "cell": cell, "footprint": footprint, "hp": hp, "max_hp": hp}


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
