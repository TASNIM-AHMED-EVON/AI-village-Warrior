extends SceneTree
## The optimised GridPathfinder must return exactly the routes and exploration order of the original
## implementation (kept as reference_grid_pathfinder.gd) for every algorithm.

const REFERENCE := preload("res://tests/pathfinding/reference_grid_pathfinder.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261111
	var cases := 0
	var mismatches := 0
	for trial in range(120):
		var size := rng.randi_range(8, 30)
		var grid := VillageGrid.new(size, size)
		var density := rng.randf_range(0.0, 0.38)
		for y in range(size):
			for x in range(size):
				if rng.randf() < density:
					grid.occupy(Vector2i(x, y), Vector2i.ONE, "o_%d_%d" % [x, y])
		var start := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		var goals: Array[Vector2i] = []
		for _g in range(rng.randi_range(1, 6)):
			goals.append(Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1)))
		for algorithm in GridPathfinder.ALGORITHMS:
			var reference_trace := {"record": true}
			var trace := {"record": true}
			var expected: Array[Vector2i] = REFERENCE.find_path_to_any(grid, start, goals, algorithm, reference_trace)
			var actual: Array[Vector2i] = GridPathfinder.find_path_to_any(grid, start, goals, algorithm, trace)
			cases += 1
			if expected != actual or reference_trace.get("visited", []) != trace.get("visited", []):
				mismatches += 1
	_check(cases == 480, "ran %d randomized path searches" % cases)
	_check(mismatches == 0, "optimised pathfinder matches the reference on every route and exploration order (%d mismatches)" % mismatches)
	if failures == 0:
		print("Pathfinder equivalence checks passed.")
		quit(0)
	else:
		push_error("%d pathfinder equivalence check(s) failed." % failures)
		quit(1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: %s" % description)
	else:
		failures += 1
		push_error("FAIL: %s" % description)
