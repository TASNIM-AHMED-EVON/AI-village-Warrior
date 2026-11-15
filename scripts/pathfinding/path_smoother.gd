extends RefCounted
class_name PathSmoother
## Turns the grid router's cell-by-cell route into a path a person would actually walk.
##   1. Shortcut: from each point, skip ahead to the farthest point that can be reached in a straight line
##      without touching a building or wall (so no more zig-zagging between cell centres).
##   2. Rounding: soften the sharp corners that remain with a small curve, but only where the curve stays clear.
## The first and last points are never changed, so the troop still arrives exactly where the router said.

## Distance a troop keeps from obstacles while walking (world pixels).
const CLEARANCE := 9.0
const SAMPLE_SPACING := 9.0
const CORNER_RADIUS := 20.0
## Switch off to compare against the raw cell-by-cell route (used by tests and measurements).
static var enabled := true


static func smooth(start: Vector2, route: Array[Vector2], grid: VillageGrid) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not enabled or route.size() <= 1:
		for point in route:
			result.append(point)
		return result
	# 1. Line-of-sight shortcuts.
	var points: Array[Vector2] = []
	var anchor := start
	var index := 0
	while index < route.size():
		var farthest := index
		for candidate in range(route.size() - 1, index - 1, -1):
			if candidate == index or is_clear(anchor, route[candidate], grid):
				farthest = candidate
				break
		points.append(route[farthest])
		anchor = route[farthest]
		index = farthest + 1
	# 2. Round the corners that are left.
	return _round_corners(start, points, grid)


## True when a troop can walk straight from `from_point` to `to_point` without clipping an obstacle.
static func is_clear(from_point: Vector2, to_point: Vector2, grid: VillageGrid) -> bool:
	var length := from_point.distance_to(to_point)
	var steps := maxi(1, ceili(length / SAMPLE_SPACING))
	for step in range(steps + 1):
		var point := from_point.lerp(to_point, float(step) / float(steps))
		if _blocked(point, grid):
			return false
		for offset in [Vector2(CLEARANCE, 0), Vector2(-CLEARANCE, 0), Vector2(0, CLEARANCE * 0.5), Vector2(0, -CLEARANCE * 0.5)]:
			if _blocked(point + offset, grid):
				return false
	return true


static func _blocked(point: Vector2, grid: VillageGrid) -> bool:
	var cell := grid.world_to_cell(point)
	return not grid.contains_cell(cell) or grid.occupied.has(cell)


static func _round_corners(start: Vector2, points: Array[Vector2], grid: VillageGrid) -> Array[Vector2]:
	if points.size() < 2:
		return points
	var result: Array[Vector2] = []
	var previous := start
	for index in range(points.size()):
		var corner := points[index]
		if index == points.size() - 1:
			result.append(corner)  # The destination is never moved.
			break
		var next := points[index + 1]
		var back := previous - corner
		var forward := next - corner
		var radius := minf(CORNER_RADIUS, minf(back.length(), forward.length()) * 0.5)
		if radius < 4.0 or absf(back.normalized().dot(forward.normalized())) > 0.97:
			result.append(corner)  # Nearly straight already, or too short to round.
			previous = corner
			continue
		var enter := corner + back.normalized() * radius
		var leave := corner + forward.normalized() * radius
		var middle := (enter + corner * 2.0 + leave) * 0.25
		if is_clear(enter, middle, grid) and is_clear(middle, leave, grid):
			result.append(enter)
			result.append(middle)
			result.append(leave)
			previous = leave
		else:
			result.append(corner)
			previous = corner
	return result
