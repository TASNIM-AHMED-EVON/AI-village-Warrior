extends SceneTree
## PathSmoother: shortcuts the staircase route, never clips an obstacle, never moves the destination.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _world_route(grid: VillageGrid, cells: Array[Vector2i]) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for cell in cells:
		points.append(grid.cell_to_world(Vector2(cell)))
	return points


func _run() -> void:
	var grid := VillageGrid.new(30, 30)
	var goals: Array[Vector2i] = [Vector2i(14, 9)]
	var cells := GridPathfinder.find_path_to_any(grid, Vector2i(2, 2), goals)
	var raw := _world_route(grid, cells)
	var start := raw[0]
	var open_route := PathSmoother.smooth(start, raw.slice(1), grid)
	_check(open_route.size() <= 3, "an open field needs at most a couple of waypoints (got %d of %d)" % [open_route.size(), raw.size()])
	_check(open_route.back().is_equal_approx(raw.back()), "the destination is never moved")

	# A wall with a gap: the smoothed route must go through the gap, not through the wall.
	grid.clear()
	for y in range(0, 20):
		if y != 14:
			grid.occupy(Vector2i(8, y), Vector2i.ONE, "wall_%d" % y)
	var around := GridPathfinder.find_path_to_any(grid, Vector2i(2, 5), [Vector2i(14, 5)])
	_check(not around.is_empty(), "the router finds the way through the gap")
	var around_raw := _world_route(grid, around)
	var around_smooth := PathSmoother.smooth(around_raw[0], around_raw.slice(1), grid)
	_check(around_smooth.size() < around_raw.size() - 1, "the route around a wall is simplified")
	_check(around_smooth.back().is_equal_approx(around_raw.back()), "the destination survives smoothing around a wall")
	var clipped := false
	var previous := around_raw[0]
	for point in around_smooth:
		var steps := maxi(1, ceili(previous.distance_to(point) / 6.0))
		for step in range(steps + 1):
			var sample := previous.lerp(point, float(step) / float(steps))
			if grid.occupied.has(grid.world_to_cell(sample)):
				clipped = true
		previous = point
	_check(not clipped, "a smoothed route never passes through a wall")
	_check(not PathSmoother.is_clear(grid.cell_to_world(Vector2(2, 5)), grid.cell_to_world(Vector2(14, 5)), grid), "a straight line through a wall is not clear")
	_check(PathSmoother.is_clear(grid.cell_to_world(Vector2(2, 5)), grid.cell_to_world(Vector2(6, 9)), grid), "a straight line in the open is clear")

	# The switch used for comparisons returns the route untouched.
	PathSmoother.enabled = false
	var untouched := PathSmoother.smooth(around_raw[0], around_raw.slice(1), grid)
	PathSmoother.enabled = true
	_check(untouched.size() == around_raw.size() - 1, "smoothing can be switched off")

	if failures == 0:
		print("Path smoother checks passed.")
		quit(0)
	else:
		quit(1)
