extends SceneTree
## The one-sweep route finder (used by the AI to compare every building at once) must agree with plain A*.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _route_cost(route: Array[Vector2i]) -> int:
	var total := 0
	for index in range(1, route.size()):
		var step := route[index] - route[index - 1]
		if step.x != 0 and step.y != 0:
			total += 24 if step.x == step.y else 48
		else:
			total += 27
	return total


func _goal_ring(center: Vector2i, grid: VillageGrid) -> Array[Vector2i]:
	var goals: Array[Vector2i] = []
	for y in range(center.y - 2, center.y + 3):
		for x in range(center.x - 2, center.x + 3):
			var cell := Vector2i(x, y)
			if grid.contains_cell(cell) and not grid.occupied.has(cell):
				goals.append(cell)
	return goals


func _run() -> void:
	var grid := VillageGrid.new(40, 40)
	# Three solid "buildings" and a wall with a gap.
	for center in [Vector2i(20, 8), Vector2i(30, 25), Vector2i(8, 30)]:
		grid.occupy(center, Vector2i(2, 2), "b_%d_%d" % [center.x, center.y])
	for y in range(0, 36):
		if y != 18:
			grid.occupy(Vector2i(15, y), Vector2i.ONE, "wall_%d" % y)
	var goal_sets := {}
	for center in [Vector2i(20, 8), Vector2i(30, 25), Vector2i(8, 30)]:
		goal_sets["b_%d_%d" % [center.x, center.y]] = _goal_ring(center, grid)
	var start := Vector2i(3, 3)
	var swept := GridPathfinder.find_paths_to_many(grid, start, goal_sets)
	_check(swept.size() == 3, "a route is found to every reachable building (%d of 3)" % swept.size())
	for id in goal_sets:
		var single := GridPathfinder.find_path_to_any(grid, start, goal_sets[id])
		_check(swept.has(id) and _route_cost(swept[id]) == _route_cost(single), "the sweep's route to %s costs the same as A* (%d vs %d)" % [id, _route_cost(swept[id]), _route_cost(single)])
		_check(swept[id][0] == start and goal_sets[id].has(swept[id][swept[id].size() - 1]), "the route to %s starts at the troop and ends on a goal cell" % id)

	# A building sealed off from the troop is simply left out.
	for y in range(0, 40):
		if not grid.occupied.has(Vector2i(15, y)):
			grid.occupy(Vector2i(15, y), Vector2i.ONE, "seal_%d" % y)
	var sealed := GridPathfinder.find_paths_to_many(grid, start, goal_sets)
	_check(not sealed.has("b_30_25") and not sealed.has("b_20_8"), "buildings behind a sealed wall get no route")
	_check(sealed.has("b_8_30"), "a building on the troop's own side of the wall still gets a route")

	# Pausing and resuming gives exactly the same answer as running straight through.
	grid.clear()
	for y in range(0, 36):
		if y != 18:
			grid.occupy(Vector2i(15, y), Vector2i.ONE, "wall_%d" % y)
	var sets_again := {"far": _goal_ring(Vector2i(30, 25), grid), "near": _goal_ring(Vector2i(8, 12), grid)}
	var whole := GridPathfinder.find_paths_to_many(grid, start, sets_again)
	var sweep := GridPathfinder.ManySweep.new(grid, start, sets_again)
	var rounds := 0
	while not sweep.step(150) and rounds < 100000:
		rounds += 1
	_check(rounds > 1, "a small time budget really does pause the sweep (%d pauses)" % rounds)
	_check(sweep.results.size() == whole.size(), "a paused sweep finds as many routes")
	for id in whole:
		_check(sweep.results.has(id) and _route_cost(sweep.results[id]) == _route_cost(whole[id]), "the resumed sweep's route to %s costs the same" % id)

	if failures == 0:
		print("Path sweep checks passed.")
		quit(0)
	else:
		quit(1)
