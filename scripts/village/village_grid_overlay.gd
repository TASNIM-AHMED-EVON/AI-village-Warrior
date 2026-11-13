extends Node2D
## Optional build-mode grid plus placement preview.

const TILE := VillageGrid.TILE_SIZE

var visible_grid := false
var hovered_cell := Vector2i(-1, -1)
var preview_footprint := Vector2i.ONE
var preview_valid := false
var grid_data := VillageGrid.new()
var preview_art: Texture2D
var preview_art_size := Vector2(90, 100)


func set_grid_visible(show_grid: bool) -> void:
	visible_grid = show_grid
	queue_redraw()


func set_preview(cell: Vector2i, footprint: Vector2i, is_valid: bool) -> void:
	hovered_cell = cell
	preview_footprint = footprint
	preview_valid = is_valid
	queue_redraw()


func set_preview_art(texture: Texture2D, draw_size: Vector2 = Vector2(90, 100)) -> void:
	preview_art = texture
	preview_art_size = draw_size
	queue_redraw()


func _draw() -> void:
	if not visible_grid:
		return
	var line_color := Color(0.85, 0.97, 0.85, 0.18)
	for y in range(grid_data.height):
		for x in range(grid_data.width):
			var center := grid_data.cell_to_world(Vector2(x, y))
			var points := PackedVector2Array([
				center + Vector2(0, -TILE.y * 0.5),
				center + Vector2(TILE.x * 0.5, 0),
				center + Vector2(0, TILE.y * 0.5),
				center + Vector2(-TILE.x * 0.5, 0),
				center + Vector2(0, -TILE.y * 0.5),
			])
			draw_polyline(points, line_color, 1.0)
	if grid_data.contains_cell(hovered_cell):
		var preview_center_cell := Vector2(hovered_cell) + (Vector2(preview_footprint) - Vector2.ONE) * 0.5
		var center := grid_data.cell_to_world(preview_center_cell)
		var half_width := float(preview_footprint.x + preview_footprint.y) * TILE.x * 0.25
		var half_height := float(preview_footprint.x + preview_footprint.y) * TILE.y * 0.25
		var color := Color("65e68f", 0.43) if preview_valid else Color("ff645e", 0.48)
		var outline := Color("a3ffbb") if preview_valid else Color("ffaaa1")
		var points := PackedVector2Array([
			center + Vector2(0, -half_height),
			center + Vector2(half_width, 0),
			center + Vector2(0, half_height),
			center + Vector2(-half_width, 0),
		])
		draw_colored_polygon(points, color)
		points.append(points[0])
		draw_polyline(points, outline, 2.0)
		if preview_art != null:
			var anchor := center + Vector2(0, half_height)
			draw_texture_rect(preview_art, Rect2(anchor + Vector2(-preview_art_size.x * 0.5, -preview_art_size.y), preview_art_size), false, Color(0.62, 1.0, 0.7, 0.62) if preview_valid else Color(1.0, 0.5, 0.45, 0.65))
