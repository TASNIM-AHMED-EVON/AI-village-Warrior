extends SceneTree

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := VillageGrid.new(8, 8)
	var goals: Array[Vector2i] = [Vector2i(6, 6)]
	var path := GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals)
	_check(not path.is_empty(), "A* finds an open route")
	_check(path.front() == Vector2i.ZERO and path.back() == goals[0], "path includes start and goal")
	_check(path.size() == 13, "A* returns a shortest Manhattan route")

	grid.occupy(Vector2i(1, 0), Vector2i(1, 1), "wall")
	path = GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals)
	_check(not path.is_empty(), "A* routes around a wall")
	_check(not path.has(Vector2i(1, 0)), "A* does not cross occupied cells")

	grid.clear()
	for cell in [Vector2i(1, 0), Vector2i(0, 1)]:
		grid.occupy(cell, Vector2i.ONE, "wall_%d_%d" % [cell.x, cell.y])
	path = GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals)
	_check(path.is_empty(), "A* reports an unreachable start")

	grid.clear()
	var bfs_path := GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals, GridPathfinder.BFS)
	_check(bfs_path.size() == 13, "BFS returns a shortest route")
	var greedy_path := GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals, GridPathfinder.GREEDY_BFS)
	_check(not greedy_path.is_empty() and greedy_path.back() == goals[0], "Greedy best-first reaches the goal")

	grid.occupy(Vector2i(1, 0), Vector2i.ONE, "new_wall")
	var recalculated := GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals)
	_check(not recalculated.has(Vector2i(1, 0)), "a new obstacle is respected after path recalculation")

	if failures == 0:
		print("Pathfinding checks passed.")
		quit(0)
	else:
		push_error("%d pathfinding check(s) failed." % failures)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
