extends RefCounted
class_name GridPathfinder
## Eight-direction grid search used by attacking and defending troops: a troop may step up, down, left, right
## AND diagonally, so routes head straight at their goal instead of staircasing along the grid axes.
##
## Costs are the real distance a troop walks across the isometric map, in pixels: a step along a grid axis is about
## 27 px, a diagonal that looks like straight up or down on screen is 24 px, and a diagonal that looks like straight
## left or right is 48 px. Measuring in screen distance makes "shortest" mean what the player sees. A diagonal step
## is only allowed when both cells it passes between are free, so a route never squeezes through the corner where two
## buildings touch. BFS is unweighted: it finds the route with the fewest moves, and a diagonal counts as one move.
##
## Performance notes: the search runs on flat arrays indexed by `y * width + x` and keeps its open
## list in a binary heap ordered by (score, insertion sequence). That selects exactly the cell the
## original linear-scan implementation selected (lowest score, earliest inserted on ties), so every
## route and every traced exploration order is unchanged, only much cheaper to compute.

const ASTAR := "A* Search"
const BFS := "BFS"
const GREEDY_BFS := "Greedy BFS"
const BEST_FIRST := "Weighted Best-First Search"
const ALGORITHMS := [ASTAR, BFS, GREEDY_BFS, BEST_FIRST]
## The first four directions are straight, the last four diagonal. The order is part of the contract: ties between
## equally good cells are broken by who was inserted first, and tests compare against a reference implementation.
const _DX := [1, 0, -1, 0, 1, -1, -1, 1]
const _DY := [0, 1, 0, -1, 1, 1, -1, -1]
## Screen distance of each direction above, in pixels (tile 48 x 24: an axis step is (24, 12), a "down" diagonal (0, 24)).
const _STEP_COST := [27, 27, 27, 27, 24, 48, 24, 48]
const _AXIS_STEP_PIXELS := 26.83


## Length of a route in cells of walking, where one step along a grid axis counts as 1 (what the AI uses as distance).
static func path_length(path: Array[Vector2i]) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		var step := path[index] - path[index - 1]
		if step.x != 0 and step.y != 0:
			total += (24.0 if step.x == step.y else 48.0) / _AXIS_STEP_PIXELS
		else:
			total += 1.0
	return total


static func find_path_to_any(grid: VillageGrid, start: Vector2i, goals: Array[Vector2i], algorithm: String = ASTAR, trace: Dictionary = {}) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	var record_trace := bool(trace.get("record", false))
	if not grid.contains_cell(start) or goals.is_empty():
		return empty_path
	var width := grid.width
	var height := grid.height
	var cell_count := width * height
	var is_goal := PackedByteArray()
	is_goal.resize(cell_count)
	var goal_xs := PackedInt32Array()
	var goal_ys := PackedInt32Array()
	for goal in goals:
		if grid.contains_cell(goal) and (not grid.occupied.has(goal) or goal == start):
			var goal_index := goal.y * width + goal.x
			if is_goal[goal_index] == 0:
				is_goal[goal_index] = 1
				goal_xs.append(goal.x)
				goal_ys.append(goal.y)
	if goal_xs.is_empty():
		return empty_path
	var start_index := start.y * width + start.x
	if is_goal[start_index] == 1:
		if record_trace:
			trace["visited"] = [start]
			trace["nodes_expanded"] = 1
			trace["path"] = [start]
		return [start]
	var blocked := PackedByteArray()
	blocked.resize(cell_count)
	for occupied_cell in grid.occupied.keys():
		if occupied_cell.x >= 0 and occupied_cell.y >= 0 and occupied_cell.x < width and occupied_cell.y < height:
			blocked[occupied_cell.y * width + occupied_cell.x] = 1
	var selected_algorithm := algorithm if ALGORITHMS.has(algorithm) else ASTAR
	var cost := PackedInt32Array()
	cost.resize(cell_count)
	cost.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(cell_count)
	parent.fill(-1)
	cost[start_index] = 0
	var explored: Array[Vector2i] = []
	var found_index := -1
	if selected_algorithm == BFS:
		found_index = _search_bfs(width, height, start_index, is_goal, blocked, cost, parent, explored, record_trace)
	else:
		found_index = _search_scored(selected_algorithm, width, height, start_index, is_goal, goal_xs, goal_ys, blocked, cost, parent, explored, record_trace)
	if record_trace:
		trace["visited"] = explored
		trace["nodes_expanded"] = explored.size()
	if found_index < 0:
		return empty_path
	var path: Array[Vector2i] = []
	var cursor := found_index
	while cursor != start_index:
		path.push_front(_to_cell(cursor, width))
		cursor = parent[cursor]
	path.push_front(start)
	if record_trace:
		trace["path"] = path
	return path


static func _search_bfs(width: int, height: int, start_index: int, is_goal: PackedByteArray, blocked: PackedByteArray, cost: PackedInt32Array, parent: PackedInt32Array, explored: Array[Vector2i], record_trace: bool) -> int:
	# Breadth-first search is a plain FIFO queue (the heap's insertion-sequence order).
	var queue := PackedInt32Array([start_index])
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if record_trace:
			explored.append(_to_cell(current, width))
		if is_goal[current] == 1:
			return current
		var cx := current % width
		@warning_ignore("integer_division")
		var cy := current / width
		for direction in range(8):
			var nx: int = cx + _DX[direction]
			var ny: int = cy + _DY[direction]
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbor := ny * width + nx
			if blocked[neighbor] == 1 or cost[neighbor] != -1:
				continue  # Unit costs: the first discovery is always the cheapest.
			if direction >= 4 and (blocked[cy * width + nx] == 1 or blocked[ny * width + cx] == 1):
				continue  # No cutting a corner between two blocked cells.
			cost[neighbor] = cost[current] + 1
			parent[neighbor] = current
			queue.append(neighbor)
	return -1


static func _search_scored(algorithm: String, width: int, height: int, start_index: int, is_goal: PackedByteArray, goal_xs: PackedInt32Array, goal_ys: PackedInt32Array, blocked: PackedByteArray, cost: PackedInt32Array, parent: PackedInt32Array, explored: Array[Vector2i], record_trace: bool) -> int:
	var heuristics := PackedFloat64Array()
	heuristics.resize(width * height)
	var open_sequence := PackedInt32Array()
	open_sequence.resize(width * height)
	open_sequence.fill(-1)
	var heap := _MinHeap.new()
	var open_count := 1
	var next_sequence := 1
	@warning_ignore("integer_division")
	var start_y := start_index / width
	heuristics[start_index] = _nearest_distance(start_index % width, start_y, goal_xs, goal_ys)
	open_sequence[start_index] = 0
	heap.push(_frontier_score(algorithm, 0, heuristics[start_index]), 0, start_index)
	while open_count > 0 and not heap.is_empty():
		var current := heap.pop()
		# Skip stale heap entries (cell already expanded, or a cheaper entry was pushed later).
		if open_sequence[current] != heap.popped_sequence:
			continue
		if heap.popped_score != _frontier_score(algorithm, cost[current], heuristics[current]):
			continue
		open_sequence[current] = -1
		open_count -= 1
		if record_trace:
			explored.append(_to_cell(current, width))
		if is_goal[current] == 1:
			return current
		var cx := current % width
		@warning_ignore("integer_division")
		var cy := current / width
		for direction in range(8):
			var nx: int = cx + _DX[direction]
			var ny: int = cy + _DY[direction]
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var neighbor := ny * width + nx
			if blocked[neighbor] == 1:
				continue
			if direction >= 4 and (blocked[cy * width + nx] == 1 or blocked[ny * width + cx] == 1):
				continue  # No cutting a corner between two blocked cells.
			var next_cost := cost[current] + int(_STEP_COST[direction])
			var known_cost := cost[neighbor]
			if known_cost != -1 and next_cost >= known_cost:
				continue
			cost[neighbor] = next_cost
			parent[neighbor] = current
			if known_cost == -1:
				heuristics[neighbor] = _nearest_distance(nx, ny, goal_xs, goal_ys)
			var neighbor_score := _frontier_score(algorithm, next_cost, heuristics[neighbor])
			if open_sequence[neighbor] != -1:
				heap.push(neighbor_score, open_sequence[neighbor], neighbor)
			else:
				open_sequence[neighbor] = next_sequence
				heap.push(neighbor_score, next_sequence, neighbor)
				next_sequence += 1
				open_count += 1
	return -1


static func _frontier_score(algorithm: String, path_cost: int, heuristic: float) -> float:
	var g := float(path_cost)
	match algorithm:
		GREEDY_BFS:
			# Greedy Best-First uses h only; g is a stable tie breaker, not its objective.
			return heuristic + g * 0.001
		BEST_FIRST:
			# Weighted Best-First (w=1.5) trades some path optimality for stronger goal direction.
			return g + heuristic * 1.5
	return g + heuristic


static func _nearest_distance(x: int, y: int, goal_xs: PackedInt32Array, goal_ys: PackedInt32Array) -> float:
	var nearest_distance := 1.0e30
	for index in range(goal_xs.size()):
		# Straight-line screen distance to the goal cell: never longer than any real route, so A* stays exact.
		var across := float(((x - goal_xs[index]) - (y - goal_ys[index])) * 24)
		var down := float(((x - goal_xs[index]) + (y - goal_ys[index])) * 12)
		var distance := sqrt(across * across + down * down)
		if distance < nearest_distance:
			nearest_distance = distance
	return nearest_distance


static func _to_cell(index: int, width: int) -> Vector2i:
	@warning_ignore("integer_division")
	var row := index / width
	return Vector2i(index % width, row)


## Minimal binary min-heap keyed by (score, sequence) holding cell indices.
class _MinHeap:
	var scores := PackedFloat64Array()
	var sequences := PackedInt32Array()
	var cells := PackedInt32Array()
	var popped_score := 0.0
	var popped_sequence := 0

	func is_empty() -> bool:
		return scores.is_empty()

	func push(score: float, sequence: int, cell: int) -> void:
		scores.append(score)
		sequences.append(sequence)
		cells.append(cell)
		var index := scores.size() - 1
		while index > 0:
			var parent_index := (index - 1) >> 1
			if not _less(index, parent_index):
				break
			_swap(index, parent_index)
			index = parent_index

	func pop() -> int:
		var top_cell := cells[0]
		popped_score = scores[0]
		popped_sequence = sequences[0]
		var last := scores.size() - 1
		if last > 0:
			scores[0] = scores[last]
			sequences[0] = sequences[last]
			cells[0] = cells[last]
		scores.resize(last)
		sequences.resize(last)
		cells.resize(last)
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < last and _less(left, smallest):
				smallest = left
			if right < last and _less(right, smallest):
				smallest = right
			if smallest == index:
				break
			_swap(index, smallest)
			index = smallest
		return top_cell

	func _less(a: int, b: int) -> bool:
		if scores[a] != scores[b]:
			return scores[a] < scores[b]
		return sequences[a] < sequences[b]

	func _swap(a: int, b: int) -> void:
		var score := scores[a]
		scores[a] = scores[b]
		scores[b] = score
		var sequence := sequences[a]
		sequences[a] = sequences[b]
		sequences[b] = sequence
		var cell := cells[a]
		cells[a] = cells[b]
		cells[b] = cell
