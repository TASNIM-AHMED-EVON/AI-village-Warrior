extends SceneTree
## Ground troops can walk in every direction: routes use diagonal steps, never cut a corner between two buildings,
## and the troop that walks one covers little more ground than the straight line to where it is going.

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
	battle.set_process(false)
	_check(battle.deploy("warrior", Vector2i(17, 14)), "a warrior deploys")
	var warrior: TroopActor = battle.attacker_units[0]
	warrior.set_process(false)

	# 1) The route to a building uses diagonal steps and is shorter than the old up/down/left/right staircase.
	var mine: BattleBuildingTarget
	for target in battle.building_targets.values():
		if target.building_type == "gold_mine" and target.global_position.x < 100.0:
			mine = target
	_check(mine != null, "found the north-west Gold Mine")
	var route := battle._find_attack_path(warrior, mine)
	_check(not route.is_empty(), "a route to the Gold Mine exists")
	var diagonal_steps := 0
	var straight_only_length := 0
	for index in range(1, route.size()):
		var step := route[index] - route[index - 1]
		if step.x != 0 and step.y != 0:
			diagonal_steps += 1
		straight_only_length += absi(step.x) + absi(step.y)
	_check(diagonal_steps >= 1, "the route uses diagonal steps (%d of %d)" % [diagonal_steps, route.size() - 1])
	_check(route.size() - 1 < straight_only_length, "diagonals make the route shorter than walking along the grid axes (%d moves instead of %d)" % [route.size() - 1, straight_only_length])

	# 2) No diagonal step in any route squeezes between two blocked cells.
	var squeezed := 0
	for target in battle.building_targets.values():
		var candidate_route := battle._find_attack_path(warrior, target)
		for index in range(1, candidate_route.size()):
			var from_cell := candidate_route[index - 1]
			var to_cell := candidate_route[index]
			if to_cell.x != from_cell.x and to_cell.y != from_cell.y:
				if village.grid.occupied.has(Vector2i(to_cell.x, from_cell.y)) or village.grid.occupied.has(Vector2i(from_cell.x, to_cell.y)):
					squeezed += 1
	_check(squeezed == 0, "no route cuts a corner between two blocked cells (%d found)" % squeezed)

	# 3) Walking it: the troop heads toward the target in a nearly straight line over open ground.
	var start_position := warrior.global_position
	var walked := 0.0
	var previous := start_position
	var free_heading_samples := 0
	var axes := [Vector2(24, 12).normalized(), Vector2(-24, 12).normalized()]
	for _step in range(100):
		battle._process(STEP)
		warrior.step(STEP * battle.speed_multiplier)
		var moved := warrior.global_position - previous
		if moved.length() > 0.2:
			walked += moved.length()
			var heading := moved.normalized()
			var near_axis := false
			for axis in axes:
				if absf(rad_to_deg(axis.angle_to(heading))) < 6.0 or absf(rad_to_deg((-axis).angle_to(heading))) < 6.0:
					near_axis = true
			if not near_axis:
				free_heading_samples += 1
		previous = warrior.global_position
	var displacement := warrior.global_position.distance_to(start_position)
	_check(displacement > 60.0, "the troop covered real ground (%.0f px)" % displacement)
	_check(walked / maxf(displacement, 1.0) < 1.25, "the troop walks almost straight (%.2f x the straight-line distance)" % (walked / maxf(displacement, 1.0)))
	_check(free_heading_samples > 10, "the troop walks in directions that are not along the grid axes")

	if failures == 0:
		print("Diagonal movement checks passed.")
		quit(0)
	else:
		quit(1)
