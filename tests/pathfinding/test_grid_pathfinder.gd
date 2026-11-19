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
	_check(path.size() == 7, "A* walks the straight diagonal across open ground (7 cells, not a 13-cell staircase)")
	_check(is_equal_approx(GridPathfinder.path_length(path), 6.0 * 24.0 / 26.83), "the diagonal route's length is the distance actually walked (24 px per step)")

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
	_check(bfs_path.size() == 7, "BFS finds the route with the fewest moves, using diagonals")
	var greedy_path := GridPathfinder.find_path_to_any(grid, Vector2i.ZERO, goals, GridPathfinder.GREEDY_BFS)
	_check(not greedy_path.is_empty() and greedy_path.back() == goals[0], "Greedy best-first reaches the goal")

	grid.occupy(Vector2i(1, 0), Vector2i.ONE, "new_wall")
	grid.clear()
	# Troops head straight for the goal in any direction, not only along the grid axes.
	var shallow := GridPathfinder.find_path_to_any(grid, Vector2i(0, 0), [Vector2i(5, 2)] as Array[Vector2i])
	var diagonal_steps := 0
	for index in range(1, shallow.size()):
		var step := shallow[index] - shallow[index - 1]
		if step.x != 0 and step.y != 0:
			diagonal_steps += 1
	_check(shallow.size() == 6 and diagonal_steps == 2, "a route to (5, 2) is 2 diagonal steps and 3 straight ones (%d diagonal, %d cells)" % [diagonal_steps, shallow.size()])

	# No squeezing through the gap where two blocked cells touch at a corner.
	grid.occupy(Vector2i(3, 2), Vector2i.ONE, "a")
	grid.occupy(Vector2i(2, 3), Vector2i.ONE, "b")
	var around_corner := GridPathfinder.find_path_to_any(grid, Vector2i(2, 2), [Vector2i(3, 3)] as Array[Vector2i])
	_check(not around_corner.is_empty() and around_corner.size() > 2, "a route does not cut the corner between two touching obstacles")
	var cut := false
	for index in range(1, around_corner.size()):
		var from_cell := around_corner[index - 1]
		var to_cell := around_corner[index]
		if to_cell.x != from_cell.x and to_cell.y != from_cell.y:
			if grid.occupied.has(Vector2i(to_cell.x, from_cell.y)) or grid.occupied.has(Vector2i(from_cell.x, to_cell.y)):
				cut = true
	_check(not cut, "no diagonal step passes between two blocked cells")

	grid.clear()
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
