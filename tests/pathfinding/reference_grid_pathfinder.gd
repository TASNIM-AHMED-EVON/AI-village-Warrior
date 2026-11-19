# Reference (original, unoptimised) pathfinder kept only so tests can prove GridPathfinder returns identical routes.
extends RefCounted

## Eight-direction grid search used by attacking troops (steps cost their screen distance in pixels, no corner cutting).

const ASTAR := "A* Search"
const BFS := "BFS"
const GREEDY_BFS := "Greedy BFS"
const BEST_FIRST := "Weighted Best-First Search"
const ALGORITHMS := [ASTAR, BFS, GREEDY_BFS, BEST_FIRST]


static func find_path_to_any(grid: VillageGrid, start: Vector2i, goals: Array[Vector2i], algorithm: String = ASTAR, trace: Dictionary = {}) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	var record_trace := bool(trace.get("record", false))
	var explored: Array[Vector2i] = []
	if not grid.contains_cell(start) or goals.is_empty():
		return empty_path
	var goal_lookup: Dictionary = {}
	for goal in goals:
		if grid.contains_cell(goal) and (not grid.occupied.has(goal) or goal == start):
			goal_lookup[goal] = true
	if goal_lookup.is_empty():
		return empty_path
	if goal_lookup.has(start):
		if record_trace:
			trace["visited"] = [start]
			trace["nodes_expanded"] = 1
			trace["path"] = [start]
		return [start]

	var frontier: Array[Vector2i] = [start]
	var open_lookup: Dictionary = {start: true}
	var came_from: Dictionary = {}
	var cost_so_far: Dictionary = {start: 0}
	var found := Vector2i(-1, -1)
	while not frontier.is_empty():
		var current_index := _best_frontier_index(frontier, cost_so_far, goal_lookup, algorithm)
		var current := frontier[current_index]
		frontier.remove_at(current_index)
		open_lookup.erase(current)
		if record_trace:
			explored.append(current)
		if goal_lookup.has(current):
			found = current
			break
		for neighbor in _neighbors(current):
			if not grid.contains_cell(neighbor):
				continue
			if grid.occupied.has(neighbor) and not goal_lookup.has(neighbor):
				continue
			var is_diagonal := neighbor.x != current.x and neighbor.y != current.y
			if is_diagonal and (grid.occupied.has(Vector2i(neighbor.x, current.y)) or grid.occupied.has(Vector2i(current.x, neighbor.y))):
				continue
			# BFS counts moves (every move is 1); the scored searches use the screen distance of the step.
			var step_cost := 1
			if algorithm != BFS:
				step_cost = 27
				if is_diagonal:
					step_cost = 24 if neighbor.x - current.x == neighbor.y - current.y else 48
			var next_cost := int(cost_so_far[current]) + step_cost
			if cost_so_far.has(neighbor) and next_cost >= int(cost_so_far[neighbor]):
				continue
			cost_so_far[neighbor] = next_cost
			came_from[neighbor] = current
			if not open_lookup.has(neighbor):
				frontier.append(neighbor)
				open_lookup[neighbor] = true
	if record_trace:
		trace["visited"] = explored
		trace["nodes_expanded"] = explored.size()
	if found.x < 0:
		return empty_path

	var path: Array[Vector2i] = [found]
	var cursor := found
	while cursor != start:
		cursor = came_from[cursor]
		path.push_front(cursor)
	if record_trace:
		trace["path"] = path
	return path


static func _best_frontier_index(frontier: Array[Vector2i], costs: Dictionary, goals: Dictionary, algorithm: String) -> int:
	if algorithm == BFS:
		return 0
	var selected_algorithm := algorithm if ALGORITHMS.has(algorithm) else ASTAR
	var best_index := 0
	var best_score := INF
	for index in range(frontier.size()):
		var cell := frontier[index]
		var heuristic := _nearest_goal_distance(cell, goals)
		var path_cost := float(costs[cell])
		var score := path_cost + heuristic
		match selected_algorithm:
			GREEDY_BFS:
				# Greedy Best-First uses h only; g is a stable tie breaker, not its objective.
				score = heuristic + path_cost * 0.001
			BEST_FIRST:
				# Weighted Best-First (w=1.5) trades some path optimality for stronger goal direction.
				score = path_cost + heuristic * 1.5
		if score < best_score:
			best_score = score
			best_index = index
	return best_index


static func _nearest_goal_distance(cell: Vector2i, goals: Dictionary) -> float:
	var nearest := INF
	for goal in goals.keys():
		var across := float(((cell.x - goal.x) - (cell.y - goal.y)) * 24)
		var down := float(((cell.x - goal.x) + (cell.y - goal.y)) * 12)
		nearest = minf(nearest, sqrt(across * across + down * down))
	return nearest


static func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i(1, 0), cell + Vector2i(0, 1), cell + Vector2i(-1, 0), cell + Vector2i(0, -1),
		cell + Vector2i(1, 1), cell + Vector2i(-1, 1), cell + Vector2i(-1, -1), cell + Vector2i(1, -1),
	]
