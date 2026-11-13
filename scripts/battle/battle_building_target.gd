extends Node2D
class_name BattleBuildingTarget

signal damaged(building_id: String, remaining_hp: int)
signal destroyed(building_id: String)
signal aim_changed(building_id: String, direction: Vector2)

const ART_DIMENSIONS := preload("res://scripts/village/village_object_layer.gd").DIMENSIONS
## Seconds a wall's health bar stays visible after the last hit. Other buildings keep their bar once damaged.
const WALL_BAR_LINGER := 4.0
const WALL_BAR_FADE := 0.5
## The yellow "just lost" segment waits this long, then drains.
const TRAIL_DELAY := 0.45
const TRAIL_DRAIN_SECONDS := 1.1
const BAR_HEIGHT := 9.0

var building_id := ""
var building_type := ""
var hp := 1
var max_hp := 1
var aim_direction := Vector2.UP
## Scales every visual timer here: 0 while the battle is paused, the battle speed otherwise.
var visual_time_scale := 1.0
var building_name := ""
var _shot_time := 0.0
var _shot_target := Vector2.ZERO
var _shot_origin := Vector2.ZERO
var _hit_flash := 0.0
var _hit_point := Vector2(0, -32)
## What the health bar shows. `hp` is the real value and drops the instant damage is dealt; the bar only
## drops when the hit visually lands (an arrow takes time to arrive), so bar and animation agree.
var _shown_hp := 1.0
var _trail_hp := 1.0
var _trail_delay := 0.0
var _pending_hits: Array[Dictionary] = []
var _bar_seen := false
var _bar_linger := 0.0
var _bar_width := 56.0
var _art_top_y := -60.0
var _art_center_y := -30.0
var _last_screen_scale := 1.0


func _init() -> void:
	z_index = 20  # Health bars and hit effects must never be hidden behind neighbouring buildings.


func configure(structure: Dictionary, grid: VillageGrid) -> void:
	building_id = str(structure["id"])
	building_type = str(structure["type"])
	hp = int(structure["hp"])
	max_hp = maxi(int(structure.get("max_hp", hp)), 1)
	_shown_hp = float(hp)
	_trail_hp = float(hp)
	building_name = str(BuildingCatalog.get_definition(building_type).get("name", building_type.capitalize()))
	var footprint: Vector2i = structure["footprint"]
	var center_cell: Vector2 = Vector2(structure["cell"]) + (Vector2(footprint) - Vector2.ONE) * 0.5
	global_position = grid.cell_to_world(center_cell)
	# The building art stands on the bottom corner of its footprint diamond (see VillageObjectLayer).
	var art: Vector2 = ART_DIMENSIONS.get(building_type, Vector2(90, 90))
	var half_height := float(footprint.x + footprint.y) * VillageGrid.TILE_SIZE.y * 0.25
	_art_top_y = half_height - art.y
	_art_center_y = half_height - art.y * 0.5
	_bar_width = clampf(34.0 + 11.0 * float(footprint.x + footprint.y), 46.0, 92.0)
	queue_redraw()


## World-space point where an incoming arrow or spell should land: the middle of the building's art.
func impact_point() -> Vector2:
	return global_position + Vector2(0, _art_center_y)


func aim_at(world_position: Vector2) -> void:
	var pivot_offset := Vector2(-2, -34) if building_type == "cannon" else Vector2(0, -150)
	var direction := world_position - (global_position + pivot_offset)
	if direction.length_squared() > 0.01:
		aim_direction = direction.normalized()
		aim_changed.emit(building_id, aim_direction)
		queue_redraw()


func fire_at(world_position: Vector2) -> void:
	aim_at(world_position)
	_shot_target = to_local(world_position)
	var pivot := Vector2(-2, -34) if building_type == "cannon" else Vector2(0, -150)
	var muzzle_distance := 42.0 if building_type == "cannon" else 18.0
	_shot_origin = pivot + aim_direction * muzzle_distance
	_shot_time = 0.12
	queue_redraw()


## `visual_delay` (battle seconds) is how long a projectile is still in flight: the health points are taken
## off at once, but the health bar and the hit flash wait until the arrow or bolt actually arrives.
func apply_damage(amount: int, source_position: Vector2 = Vector2.ZERO, visual_delay: float = 0.0) -> void:
	if hp <= 0 or amount <= 0:
		return
	var dealt := mini(amount, hp)
	hp -= dealt
	_bar_seen = true
	_bar_linger = WALL_BAR_LINGER
	var hit_point := _hit_point
	if source_position != Vector2.ZERO:
		var incoming := to_local(source_position).normalized()
		hit_point = incoming * 28.0 + Vector2(0, -22)
	_pending_hits.append({"delay": maxf(visual_delay, 0.0), "dealt": dealt, "point": hit_point})
	if visual_delay <= 0.0:
		_land_ready_hits(0.0)
	queue_redraw()
	damaged.emit(building_id, hp)
	if hp == 0:
		destroyed.emit(building_id)


func _land_ready_hits(elapsed: float) -> void:
	var remaining: Array[Dictionary] = []
	for hit in _pending_hits:
		hit["delay"] = float(hit["delay"]) - elapsed
		if float(hit["delay"]) <= 0.0:
			# Subtract what this shot did instead of jumping to a stored value: shots with different flight times
			# can land out of order, and the bar must only ever go down.
			_shown_hp = maxf(0.0, _shown_hp - float(hit["dealt"]))
			_hit_point = hit["point"]
			_hit_flash = 0.32
			_trail_delay = TRAIL_DELAY
			_bar_linger = WALL_BAR_LINGER
		else:
			remaining.append(hit)
	_pending_hits = remaining


func _process(delta: float) -> void:
	var scaled := delta * visual_time_scale
	var dirty := false
	if not _pending_hits.is_empty():
		_land_ready_hits(scaled)
		dirty = true
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - scaled)
		dirty = true
	if _shot_time > 0.0:
		_shot_time = maxf(0.0, _shot_time - scaled)
		dirty = true
	if _trail_hp > _shown_hp:
		if _trail_delay > 0.0:
			_trail_delay = maxf(0.0, _trail_delay - scaled)
		else:
			_trail_hp = maxf(_shown_hp, _trail_hp - float(max_hp) * scaled / TRAIL_DRAIN_SECONDS)
		dirty = true
	if building_type == "wall" and _bar_seen and _bar_linger > -WALL_BAR_FADE and _pending_hits.is_empty():
		_bar_linger -= scaled
		dirty = true
	if _bar_seen and absf(_screen_scale() - _last_screen_scale) > 0.02:
		dirty = true  # The player zoomed the camera: keep the bar readable.
	if dirty:
		queue_redraw()


## The health bar and its text are drawn larger when the camera is zoomed out so they stay readable.
func _screen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return clampf(1.0 / maxf(get_canvas_transform().get_scale().x, 0.05), 1.0, 2.4)


## How visible the health bar is right now (0..1). Walls fade out after a while; other buildings keep it.
func bar_alpha() -> float:
	if not _bar_seen or hp <= 0:
		return 0.0
	if building_type != "wall":
		return 1.0
	if _bar_linger >= 0.0:
		return 1.0
	return clampf(1.0 + _bar_linger / WALL_BAR_FADE, 0.0, 1.0)


## The numbers the bar currently shows (hp as it has visually landed, and the lagging "just lost" edge).
func displayed_hp() -> float:
	return _shown_hp


func displayed_trail_hp() -> float:
	return _trail_hp


func pending_hit_count() -> int:
	return _pending_hits.size()


func _draw() -> void:
	if _hit_flash > 0.0:
		var progress := 1.0 - _hit_flash / 0.32
		var radius := 7.0 + progress * 13.0
		draw_arc(_hit_point, radius, 0.0, TAU, 24, Color(1.0, 0.78, 0.34, 1.0 - progress), 3.0, true)
		for index in range(6):
			var direction := Vector2.RIGHT.rotated(TAU * float(index) / 6.0)
			draw_line(_hit_point + direction * (radius + 2.0), _hit_point + direction * (radius + 8.0), Color("fff0a2", 1.0 - progress), 2.5, true)
	if building_type == "archer_tower":
		# The tower sprite contains its own archer; this directional bow/arrow cue follows the live aim.
		var archer_origin := Vector2(0, -150)
		var arrow_tip := archer_origin + aim_direction * 18.0
		draw_line(archer_origin, arrow_tip, Color("f4df9f"), 2.0, true)
		draw_line(arrow_tip, arrow_tip - aim_direction.rotated(0.5) * 5.0, Color("f4df9f"), 1.5, true)
		draw_line(arrow_tip, arrow_tip - aim_direction.rotated(-0.5) * 5.0, Color("f4df9f"), 1.5, true)
	if _shot_time > 0.0:
		# Keep the supplied cannon/tower artwork intact and render a brief shot travelling from its muzzle.
		var progress := 1.0 - clampf(_shot_time / 0.12, 0.0, 1.0)
		var projectile := _shot_origin.lerp(_shot_target, progress)
		draw_line(_shot_origin, projectile, Color(1.0, 0.79, 0.33, 0.46), 2.0, true)
		draw_circle(projectile, 5.0, Color("fff1a6"))
		draw_circle(projectile, 2.5, Color("ffac48"))
	_draw_health_bar()


func _draw_health_bar() -> void:
	var alpha := bar_alpha()
	if alpha <= 0.0:
		return
	_last_screen_scale = _screen_scale()
	# Everything below is drawn in "bar space": its bottom-centre sits just above the building art, and the
	# whole bar grows upward when the camera is zoomed out.
	draw_set_transform(Vector2(0.0, _art_top_y - 10.0), 0.0, Vector2(_last_screen_scale, _last_screen_scale))
	var width := _bar_width
	var origin := Vector2(-width * 0.5, -BAR_HEIGHT)
	var shown_ratio := clampf(_shown_hp / float(max_hp), 0.0, 1.0)
	var trail_ratio := clampf(_trail_hp / float(max_hp), 0.0, 1.0)
	draw_rect(Rect2(origin + Vector2(-2, -2), Vector2(width + 4.0, BAR_HEIGHT + 4.0)), Color(0.04, 0.06, 0.08, 0.92 * alpha))
	draw_rect(Rect2(origin, Vector2(width, BAR_HEIGHT)), Color(0.20, 0.23, 0.26, alpha))
	if trail_ratio > shown_ratio:
		# The health that was just lost: it lingers in yellow, then drains away.
		draw_rect(Rect2(origin + Vector2(width * shown_ratio, 0.0), Vector2(width * (trail_ratio - shown_ratio), BAR_HEIGHT)), Color(1.0, 0.88, 0.45, alpha))
	var fill := Color("70db87") if shown_ratio > 0.55 else (Color("eea05a") if shown_ratio > 0.25 else Color("e7645c"))
	fill.a = alpha
	draw_rect(Rect2(origin, Vector2(width * shown_ratio, BAR_HEIGHT)), fill)
	for quarter in range(1, 4):
		var tick_x := origin.x + width * float(quarter) / 4.0
		draw_line(Vector2(tick_x, origin.y), Vector2(tick_x, origin.y + BAR_HEIGHT), Color(0.04, 0.06, 0.08, 0.55 * alpha), 1.0)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "%s  %d / %d" % [building_name, int(ceil(_shown_hp)), max_hp]
		var label_origin := Vector2(-width * 0.5 - 70.0, origin.y - 6.0)
		draw_string_outline(font, label_origin, label, HORIZONTAL_ALIGNMENT_CENTER, width + 140.0, 13, 4, Color(0.03, 0.05, 0.07, 0.95 * alpha))
		draw_string(font, label_origin, label, HORIZONTAL_ALIGNMENT_CENTER, width + 140.0, 13, Color(1.0, 0.97, 0.9, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
