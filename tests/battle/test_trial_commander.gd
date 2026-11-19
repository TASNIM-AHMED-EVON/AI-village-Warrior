extends SceneTree
## AI Trial: the fixed fortress village and the attack commander that deploys on its own.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_test_trial_village()
	await _test_commander()
	if failures == 0:
		print("Trial commander checks passed.")
		quit(0)
	else:
		quit(1)


func _test_trial_village() -> void:
	var village := TrialVillage.build()
	var buildings := 0
	var cannons := 0
	var towers := 0
	var wizards := 0
	var castle: Dictionary = {}
	for structure in village.structures:
		if str(structure["type"]) == "wall":
			continue
		buildings += 1
		if str(structure["type"]) == "cannon": cannons += 1
		if str(structure["type"]) == "archer_tower": towers += 1
		if str(structure["type"]) == "wizard_tower": wizards += 1
		if str(structure["type"]) == "clan_castle": castle = structure
	_check(buildings == 15, "the trial fortress has 15 buildings to destroy (got %d)" % buildings)
	_check(cannons == 3 and towers == 3 and wizards == 1, "the fortress has three cannons, three archer towers and a wizard tower")
	_check(not castle.is_empty() and ClanCastle.housing_used(ClanCastle.sanitize(castle.get("garrison", null))) > 0, "the Clan Castle holds a garrison")
	_check(village.army["dragon"] > 0 and village.army["tank"] > 0, "the trial army includes dragons and tanks")
	var again := TrialVillage.build()
	_check(again.structures.size() == village.structures.size(), "the trial village is identical every time")
	_check(TrialVillage.build() != village, "each build is a fresh model that can be damaged freely")


func _test_commander() -> void:
	var village := TrialVillage.build()
	var units_root := Node2D.new()
	var targets_root := Node2D.new()
	root.add_child(units_root)
	root.add_child(targets_root)
	var battle := BattleManager.new()
	root.add_child(battle)
	battle.begin_battle(village, units_root, targets_root)
	var commander := AttackCommander.new()
	commander.setup(battle)
	_check(commander.briefing.size() >= 5, "the commander writes a layout briefing")
	_check(not commander.heatmap.is_empty(), "the commander produces an exposure heatmap")
	var decision := ""
	for line in commander.briefing:
		if line.begins_with("• Decision"):
			decision = line
	_check(decision != "", "the briefing states which side it will attack")
	# Skip the opening pause, then let it play ten battle seconds of deployment.
	commander.tick(AttackCommander.OPENING_DELAY + 0.1)
	for _frame in range(240):
		commander.tick(0.05)
		await process_frame
	_check(not commander.deployments.is_empty(), "the commander deployed troops without any input")
	_check(battle.total_deployed == commander.deployments.size(), "every deployment really reached the battle")
	for entry in commander.deployments:
		_check(village.grid.contains_cell(entry["cell"]), "deployment cells are inside the map")
	# The ground push stays on one stretch of the map: every tank, warrior, archer and mage drop is within 70 degrees
	# of the average direction (dragons fly in where fewer defenses can hit air, goblins are reserves).
	var centre := commander._base_centre()
	var mean := Vector2.ZERO
	var drops: Array[Vector2] = []
	for entry in commander.deployments:
		if str(entry["troop"]) != "goblin" and str(entry["troop"]) != "dragon":
			var direction := (village.grid.cell_to_world(Vector2(entry["cell"])) - centre).normalized()
			drops.append(direction)
			mean += direction
	mean = mean.normalized()
	var widest := 0.0
	for direction in drops:
		widest = maxf(widest, rad_to_deg(absf(mean.angle_to(direction))))
	_check(widest <= 70.0, "the main push stays on one stretch of the map (widest %.0f degrees from the average)" % widest)
	_check(commander.log_lines.size() > 2, "the commander explains its decisions")
	units_root.queue_free()
	targets_root.queue_free()
	battle.queue_free()
