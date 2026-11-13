extends Node2D
## Static terrain pass. It is drawn once and does not participate in game logic.

const TILE := VillageGrid.TILE_SIZE
const GRASS_MAP := preload("res://assets/terrain/village_grass_map.png")
const GRASS_TILES := [
	preload("res://assets/terrain/grass_tile_0.png"),
	preload("res://assets/terrain/grass_tile_1.png"),
	preload("res://assets/terrain/grass_tile_2.png"),
	preload("res://assets/terrain/grass_tile_3.png"),
	preload("res://assets/terrain/grass_tile_4.png"),
	preload("res://assets/terrain/grass_tile_5.png"),
	preload("res://assets/terrain/grass_tile_6.png"),
	preload("res://assets/terrain/grass_tile_7.png"),
	preload("res://assets/terrain/grass_tile_8.png"),
]


var village: VillageModel


func set_village(model: VillageModel) -> void:
	village = model
	queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	# Dark rolling landscape outside the diamond so the camera never reveals void.
	draw_rect(Rect2(-5400, -2800, 10800, 8200), Color("243d31"))
	var frame := PackedVector2Array([
		Vector2(0, -64), Vector2(1530, 720), Vector2(0, 1505), Vector2(-1530, 720),
	])
	draw_colored_polygon(frame, Color("4a5238"))
	draw_texture(GRASS_MAP, Vector2(-1440, 0))
	_draw_grass_tile_variation()
	_draw_dirt_paths()
	var map := PackedVector2Array([
		_cell_to_world(Vector2(0, 0)), _cell_to_world(Vector2(60, 0)),
		_cell_to_world(Vector2(60, 60)), _cell_to_world(Vector2(0, 60)),
	])
	for index in range(map.size()):
		draw_line(map[index], map[(index + 1) % map.size()], Color("344d35"), 12.0, true)
		draw_line(map[index] + Vector2(0, -5), map[(index + 1) % map.size()] + Vector2(0, -5), Color("b8bd7a", 0.25), 2.0, true)
	_draw_grass_details()
	_draw_trees()


func _draw_dirt_paths() -> void:
	# A low-contrast dirt path follows unoccupied tiles around the Town Hall.
	if village == null:
		return
	for structure in village.structures:
		if str(structure.get("type", "")) != "town_hall":
			continue
		var origin: Vector2i = structure["cell"]
		var footprint: Vector2i = structure["footprint"]
		for y in range(origin.y - 2, origin.y + footprint.y + 2):
			for x in range(origin.x - 2, origin.x + footprint.x + 2):
				var cell := Vector2i(x, y)
				if not village.grid.contains_cell(cell) or village.grid.occupied.has(cell):
					continue
				var outer := x == origin.x - 2 or y == origin.y - 2 or x == origin.x + footprint.x + 1 or y == origin.y + footprint.y + 1
				if not outer:
					continue
				var center := _cell_to_world(Vector2(cell))
				var points := PackedVector2Array([center + Vector2(0, -11), center + Vector2(22, 0), center + Vector2(0, 11), center + Vector2(-22, 0)])
				draw_colored_polygon(points, Color("bca273", 0.25))



func _draw_grass_tile_variation() -> void:
	# The generated map was a single repeated tile. Repaint each logical cell from the
	# supplied grass variants so the field has the same textured style without a checker pattern.
	var tile_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var tile_uvs := PackedVector2Array([
		Vector2(0.5, 0.0), Vector2(1.0, 0.5), Vector2(0.5, 1.0), Vector2(0.0, 0.5),
	])
	for y in range(60):
		for x in range(60):
			var center := _cell_to_world(Vector2(x, y))
			var points := PackedVector2Array([
				center + Vector2(0, -TILE.y * 0.5),
				center + Vector2(TILE.x * 0.5, 0),
				center + Vector2(0, TILE.y * 0.5),
				center + Vector2(-TILE.x * 0.5, 0),
			])
			var tile_index := posmod(x * 5 + y * 7 + (x * y) % 11, GRASS_TILES.size())
			draw_polygon(points, tile_colors, tile_uvs, GRASS_TILES[tile_index])


func _draw_grass_details() -> void:
	for index in range(520):
		var cell := Vector2i((index * 37 + 7) % 60, (index * 23 + 11) % 60)
		var point := _cell_to_world(Vector2(cell)) + Vector2(float(index % 9) - 4.0, float((index * 3) % 7) - 3.0)
		var blade_color := Color("b3d866", 0.28) if index % 3 == 0 else Color("477e39", 0.24)
		draw_line(point, point + Vector2(-2, -5), blade_color, 1.4, true)
		draw_line(point, point + Vector2(2, -4), blade_color, 1.2, true)
		if index % 29 == 0:
			draw_circle(point + Vector2(4, 1), 2.2, Color("f2df85"))
			draw_circle(point + Vector2(-1, 2), 1.8, Color("e8a6a2"))


func _draw_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 732091
	# Plants have no CollisionShape2D and do not change occupied/grid cells.
	# Check the live model so no deco sits beneath an existing structure.
	for index in range(190):
		var cell := Vector2i(rng.randi_range(1, 58), rng.randi_range(1, 58))
		if not _decoration_cell_clear(cell):
			continue
		var center := _cell_to_world(Vector2(cell))
		var roll := index % 11
		if roll == 0:
			_draw_tree(center, rng.randf_range(0.62, 0.88))
		elif roll == 1 or roll == 6:
			_draw_rock(center + Vector2(0, 5))
		elif roll < 8:
			_draw_shrub(center, rng)
		else:
			draw_circle(center + Vector2(rng.randf_range(-8, 8), 0), 2.5, Color("f0c56d", 0.78))


func _decoration_cell_clear(cell: Vector2i) -> bool:
	if village == null:
		return cell.x < 10 or cell.x > 50 or cell.y < 10 or cell.y > 50
	for yy in range(cell.y - 2, cell.y + 3):
		for xx in range(cell.x - 2, cell.x + 3):
			if village.grid.occupied.has(Vector2i(xx, yy)):
				return false
	return true


func _draw_shrub(center: Vector2, rng: RandomNumberGenerator) -> void:
	_draw_ellipse_shape(center + Vector2(0, 2), Vector2(9, 3), Color("233f2b", 0.22))
	var scale_value := rng.randf_range(.65, 1.15)
	draw_circle(center + Vector2(-4, -5), 6 * scale_value, Color("385c35", 0.8))
	draw_circle(center + Vector2(3, -7), 7 * scale_value, Color("5c8746", 0.82))
	draw_circle(center + Vector2(0, -10), 4 * scale_value, Color("85ae5b", 0.75))



func _draw_tree(center: Vector2, scale_value: float) -> void:
	_draw_ellipse_shape(center + Vector2(0, 3), Vector2(20, 8) * scale_value, Color("395631", 0.28))
	draw_rect(Rect2(center + Vector2(-4, -22) * scale_value, Vector2(8, 25) * scale_value), Color("79502e"))
	draw_circle(center + Vector2(-7, -31) * scale_value, 15 * scale_value, Color("43843c"))
	draw_circle(center + Vector2(8, -35) * scale_value, 17 * scale_value, Color("559c42"))
	draw_circle(center + Vector2(0, -47) * scale_value, 14 * scale_value, Color("6aaa49"))
	draw_circle(center + Vector2(-5, -49) * scale_value, 4 * scale_value, Color("8bc75a", 0.72))


func _draw_rock(center: Vector2) -> void:
	_draw_ellipse_shape(center + Vector2(0, 4), Vector2(13, 5), Color("3c5534", 0.24))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-12, 1), center + Vector2(-8, -9), center + Vector2(0, -13),
		center + Vector2(10, -8), center + Vector2(13, 2), center + Vector2(4, 6),
	]), Color("aaa997"))
	draw_line(center + Vector2(-7, -5), center + Vector2(0, -10), Color("d7d2bd"), 2.0, true)


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(17):
		var angle := TAU * float(index) / 16.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _cell_to_world(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE.x * 0.5, (cell.x + cell.y) * TILE.y * 0.5)
