extends RefCounted
class_name VillageGrid
## Logical square grid used by village data. Rendering is handled elsewhere.

const TILE_SIZE := Vector2(48.0, 24.0)

var width: int
var height: int
var occupied: Dictionary = {}


func _init(grid_width: int = 60, grid_height: int = 60) -> void:
	width = grid_width
	height = grid_height


func contains_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func cell_to_world(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_SIZE.x * 0.5, (cell.x + cell.y) * TILE_SIZE.y * 0.5)


func world_to_cell(world_position: Vector2) -> Vector2i:
	var grid_x := world_position.x / TILE_SIZE.x + world_position.y / TILE_SIZE.y
	var grid_y := world_position.y / TILE_SIZE.y - world_position.x / TILE_SIZE.x
	return Vector2i(roundi(grid_x), roundi(grid_y))


func is_footprint_clear(origin: Vector2i, footprint: Vector2i) -> bool:
	if footprint.x <= 0 or footprint.y <= 0:
		return false
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			var cell := Vector2i(x, y)
			if not contains_cell(cell) or occupied.has(cell):
				return false
	return true


func occupy(origin: Vector2i, footprint: Vector2i, object_id: String) -> bool:
	if not is_footprint_clear(origin, footprint):
		return false
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			occupied[Vector2i(x, y)] = object_id
	return true


func get_object_id_at(cell: Vector2i) -> String:
	return str(occupied.get(cell, ""))


func release(origin: Vector2i, footprint: Vector2i, object_id: String) -> void:
	for y in range(origin.y, origin.y + footprint.y):
		for x in range(origin.x, origin.x + footprint.x):
			var cell := Vector2i(x, y)
			if occupied.get(cell, "") == object_id:
				occupied.erase(cell)


func clear() -> void:
	occupied.clear()


func to_dict() -> Dictionary:
	var occupied_cells: Array[Dictionary] = []
	for cell in occupied:
		occupied_cells.append({"x": cell.x, "y": cell.y, "id": occupied[cell]})
	return {"width": width, "height": height, "occupied": occupied_cells}
