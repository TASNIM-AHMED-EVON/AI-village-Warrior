extends SceneTree
## Ground troops that attack the same building fan out around it instead of piling onto one spot.

var failures := 0
const STEP := 0.05


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var village := TrialVillage.build()
	var units_root := Node2D.new()
	var targets_root := Node2D.new()
	root.add_child(units_root)
	root.add_child(targets_root)
	var battle := BattleManager.new()
	root.add_child(battle)
	battle.begin_battle(village, units_root, targets_root)
	battle.set_process(false)  # Stepped by hand below, so the test is fast and exact.

	# 1) Two troops dropped on exactly the same spot are pushed apart.
	var cell := Vector2i(17, 14)
	_check(battle.is_valid_deployment_cell(cell), "the test deploy cell is valid")
	_check(battle.deploy("warrior", cell) and battle.deploy("warrior", cell), "two warriors deploy on the same cell")
	for unit in battle.attacker_units:
		unit.set_process(false)
	var first := battle.attacker_units[0]
	var second := battle.attacker_units[1]
	first.global_position = second.global_position
	for _i in range(40):
		battle._separate_troops(STEP)
	_check(first.global_position.distance_to(second.global_position) >= 15.0, "overlapping troops are pushed apart (%.1f px)" % first.global_position.distance_to(second.global_position))

	# 2) A whole squad attacking: how often do troops that fight the same building stand on top of each other?
	for _i in range(5):
		battle.deploy("warrior", cell + Vector2i(_i % 3, _i / 3))
	battle.deploy("tank", cell + Vector2i(1, 0))
	for unit in battle.attacker_units:
		unit.set_process(false)
	var close_pairs := 0
	var all_pairs := 0
	var best_group := 0
	for step in range(1600):
		battle._process(STEP)
		for unit in battle.attacker_units:
			if is_instance_valid(unit):
				unit.step(STEP * battle.speed_multiplier)
		for defender in battle._living_defenders():
			defender.step(STEP * battle.speed_multiplier)
		if step % 10 != 0:
			continue
		var groups := {}
		for unit in battle.attacker_units:
			if is_instance_valid(unit) and unit.state in [TroopActor.State.ATTACK, TroopActor.State.RECOVER] and unit.target is BattleBuildingTarget:
				if not groups.has(unit.target):
					groups[unit.target] = []
				groups[unit.target].append(unit)
		for target in groups:
			var members: Array = groups[target]
			best_group = maxi(best_group, members.size())
			for i in range(members.size()):
				for j in range(i + 1, members.size()):
					all_pairs += 1
					if members[i].global_position.distance_to(members[j].global_position) < 10.0:
						close_pairs += 1
	_check(best_group >= 3, "at least three troops attacked the same building at once (best group %d)" % best_group)
	var share := float(close_pairs) / float(maxi(all_pairs, 1))
	_check(share < 0.05, "fewer than 5%% of troop pairs on the same building overlap (%.1f%%)" % (share * 100.0))

	if failures == 0:
		print("Troop spreading checks passed.")
		quit(0)
	else:
		quit(1)
