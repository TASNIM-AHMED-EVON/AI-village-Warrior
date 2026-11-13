extends SceneTree
## Real-frame regression test. Dead troops are FREED by the engine a moment after they die, so lists that
## still hold them contain freed objects. Unit tests that never yield a frame cannot see that, which is how a
## "previously freed" runtime error slipped through once. Any SCRIPT ERROR printed here fails the runner.

const DT := 0.05

var failures := 0
var _keep: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_release_after_a_troop_was_freed()
	await _test_soak_with_deaths_switches_and_pauses()
	for node in _keep:
		if is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("Battle frame checks passed.")
		quit(0)
	else:
		push_error("%d battle frame check(s) failed." % failures)
		quit(1)


func _test_release_after_a_troop_was_freed() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	var castle_pos: Vector2 = setup["castle_pos"]
	_check(battle.deploy("warrior", _find_cell(battle, castle_pos, false, 0)), "first far attacker deployed")
	_check(battle.deploy("warrior", _find_cell(battle, castle_pos, false, 1)), "second far attacker deployed")
	var doomed: TroopActor = battle.attacker_units[0]
	var survivor: TroopActor = battle.attacker_units[1]
	doomed.apply_damage(99999)
	for _i in range(120):
		await _frame(battle)
		if not is_instance_valid(doomed):
			break
	_check(not is_instance_valid(doomed), "the dead attacker was freed by the engine")
	_check(battle.attacker_units.size() == 2, "the unit list still holds the freed attacker")
	# Triggering the castle now re-plans every attacker, including the stale list entry.
	_check(battle.deploy("warrior", _find_cell(battle, castle_pos, true, 0)), "attacker deployed inside the trigger radius")
	for _i in range(12):
		await _frame(battle)
	_check(battle.defenders_released > 0, "the garrison was released after a troop had been freed")
	_check(is_instance_valid(survivor) and is_instance_valid(survivor.target), "surviving attackers were re-planned")
	battle.set_path_algorithm(GridPathfinder.BFS)
	battle.set_strategy_algorithm(BattleSearchAI.EXPECTIMAX)
	for _i in range(30):
		await _frame(battle)
	_check(battle._replan_queue.is_empty(), "switching algorithms with a freed troop in the list still drains the queue")


func _test_soak_with_deaths_switches_and_pauses() -> void:
	var setup := _new_battle()
	var battle: BattleManager = setup["battle"]
	var castle_pos: Vector2 = setup["castle_pos"]
	var roster := ["warrior", "archer", "goblin", "tank", "mage", "warrior", "archer", "goblin", "warrior", "archer", "mage", "goblin", "warrior", "archer"]
	var deployed := 0
	var freed_seen := false
	var frames := 0
	var finished := false
	while frames < 1800 and not finished:
		frames += 1
		if frames % 12 == 1 and deployed < roster.size():
			var inside := deployed % 3 == 0
			var cell := _find_cell(battle, castle_pos, inside, deployed / 3)
			if cell.x >= 0 and battle.deploy(roster[deployed], cell):
				deployed += 1
			else:
				deployed += 1
		if frames == 200:
			battle.set_path_algorithm(GridPathfinder.GREEDY_BFS)
		if frames == 320:
			battle.set_strategy_algorithm(BattleSearchAI.MINIMAX)
		if frames == 400:
			battle.set_speed(3.0)
		if frames == 500:
			battle.set_paused(true)
		if frames == 506:
			battle.set_paused(false)
		if frames == 650:
			battle.set_path_algorithm(GridPathfinder.ASTAR)
			battle.set_strategy_algorithm(BattleSearchAI.ALPHA_BETA)
		await _frame(battle)
		for index in range(battle.attacker_units.size()):
			var entry: Variant = battle.attacker_units[index]
			if not is_instance_valid(entry):
				freed_seen = true
		finished = battle.phase != BattleManager.Phase.ACTIVE and battle.phase != BattleManager.Phase.PAUSED and battle.phase != BattleManager.Phase.DEPLOYMENT
	_check(freed_seen, "the soak test exercised freed troops in the unit list")
	_check(battle.defenders_released > 0, "the soak test released the Clan Castle garrison")
	var sane := true
	for troop in battle._all_troops():
		sane = sane and not is_nan(troop.global_position.x) and not is_nan(troop.global_position.y)
	_check(sane, "no troop ended up at an invalid position")
	_check(frames > 100, "the battle ran for %d frames" % frames)


# ----------------------------------------------------------------------------------------------
func _new_battle() -> Dictionary:
	var village := VillageModel.new()
	village.create_starter_layout()
	var castle := {}
	for structure in village.structures:
		if structure["type"] == "clan_castle":
			castle = structure
	var actors := Node2D.new()
	var targets := Node2D.new()
	root.add_child(actors)
	root.add_child(targets)
	var battle := BattleManager.new()
	root.add_child(battle)
	_keep.append_array([actors, targets, battle])
	battle.begin_battle(village, actors, targets)
	battle.set_process(false)  # The test drives the simulation by hand, one step per real frame.
	var castle_target: BattleBuildingTarget = battle.building_targets[castle["id"]]
	return {"battle": battle, "castle_pos": castle_target.global_position}


## One simulation step followed by a real engine frame, so queue_free() on dead troops really happens.
func _frame(battle: BattleManager) -> void:
	for troop in battle._all_troops():
		troop.set_process(false)
		troop.step(DT)
	battle._process(DT)
	await process_frame


func _find_cell(battle: BattleManager, castle_pos: Vector2, inside: bool, skip: int = 0) -> Vector2i:
	var found := 0
	for y in range(battle.village.grid.height):
		for x in range(battle.village.grid.width):
			var cell := Vector2i(x, y)
			if not battle.is_valid_deployment_cell(cell):
				continue
			var distance := battle.village.grid.cell_to_world(Vector2(cell)).distance_to(castle_pos)
			if (inside and distance <= 230.0) or (not inside and distance >= 700.0):
				if found == skip:
					return cell
				found += 1
	return Vector2i(-1, -1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
