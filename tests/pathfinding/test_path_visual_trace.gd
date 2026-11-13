extends SceneTree
## Verifies optional instrumentation is observational and contains real expansions.

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := VillageGrid.new(12, 12)
	for y in range(2, 9):
		grid.occupy(Vector2i(5, y), Vector2i.ONE, "block_%d" % y)
	var goals: Array[Vector2i] = [Vector2i(9, 8)]
	for algorithm in GridPathfinder.ALGORITHMS:
		var untraced := GridPathfinder.find_path_to_any(grid, Vector2i(2, 2), goals, algorithm)
		var trace := {"record": true}
		var traced := GridPathfinder.find_path_to_any(grid, Vector2i(2, 2), goals, algorithm, trace)
		_check(untraced == traced, "%s trace does not alter path" % algorithm)
		_check(not traced.is_empty(), "%s finds a path" % algorithm)
		_check(int(trace.get("nodes_expanded", 0)) > 0, "%s reports actual expanded cells" % algorithm)
		_check(not traced.is_empty() and trace.get("visited", []).has(traced[0]), "%s visit trace includes start" % algorithm)
		_check(trace.get("path", []) == traced, "%s returns chosen path as-is" % algorithm)
	if failures == 0:
		print("Path visualization trace checks passed.")
		quit(0)
	else:
		push_error("%d trace checks failed." % failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
