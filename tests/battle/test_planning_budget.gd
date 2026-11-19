extends SceneTree
## A big attack must not stall frames: planning is spread over frames with a time budget.
## (This is the regression test for the lag when many troops were deployed at once.)

var failures := 0
const LIMIT_MS := 40.0  # Generous on purpose: slow machines must not make this flaky. The old code needed 60-190 ms.


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
	battle.set_process(false)
	battle.troop_stock = {"warrior": 12, "archer": 10, "mage": 5, "goblin": 10, "tank": 4, "dragon": 3}
	var deploy_started := Time.get_ticks_usec()
	var cells := [Vector2i(17, 14), Vector2i(18, 14), Vector2i(17, 15), Vector2i(18, 15), Vector2i(19, 14), Vector2i(16, 14)]
	var count := 0
	for troop_id in ["tank", "warrior", "archer", "mage", "goblin", "warrior", "archer", "goblin", "tank", "warrior", "archer", "goblin"]:
		for cell in cells:
			if battle.deploy(troop_id, cell):
				count += 1
				break
	var deploy_ms := float(Time.get_ticks_usec() - deploy_started) / 1000.0 / float(maxi(count, 1))
	_check(count >= 10, "a dozen troops deploy (%d)" % count)
	_check(deploy_ms < 5.0, "dropping a troop does not plan inside the click (%.1f ms each)" % deploy_ms)
	for unit in battle.attacker_units:
		unit.set_process(false)

	var worst_ms := 0.0
	var frames := 0
	while (not battle._replan_queue.is_empty() or not battle._plan_job.is_empty()) and frames < 4000:
		var started := Time.get_ticks_usec()
		battle._process_replan_queue()
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - started) / 1000.0)
		frames += 1
	_check(frames < 4000, "all queued plans finish")
	_check(worst_ms < LIMIT_MS, "no single frame of planning takes long (worst %.1f ms over %d frames)" % [worst_ms, frames])
	var planned := 0
	for unit in battle.attacker_units:
		if is_instance_valid(unit.target):
			planned += 1
	_check(planned == battle.attacker_units.size(), "every troop ends up with a target (%d of %d)" % [planned, battle.attacker_units.size()])
	print("planning: %d troops, %d frames, worst frame %.1f ms" % [battle.attacker_units.size(), frames, worst_ms])

	if failures == 0:
		print("Planning budget checks passed.")
		quit(0)
	else:
		quit(1)
