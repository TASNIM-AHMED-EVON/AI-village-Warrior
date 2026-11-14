extends Node2D
class_name VisualEntity
## Presentation-only node: its origin is the front ground edge (Y-sort anchor).
## Gameplay still reads VillageModel / BattleManager, never these sprites.

const CANNON_BASE := preload("res://assets/buildings/cannon_base_sprite.png")
const CANNON_GUN := preload("res://assets/buildings/cannon_gun_sprite.png")
const CANNON_GUN_ART_ANGLE := -0.28
const CANNON_PIVOT_IN_ENTITY := Vector2(-2.0, -58.0)

var entity_id: String = ""
var entity_kind: String = ""
var entity_type: String = ""
var shadow_radius := Vector2(28.0, 10.0)
var shadow_offset := Vector2(0.0, -6.0)
var is_selected := false
var max_health := 0
var current_health := 0
## The battle draws its own, larger health bar above the building (BattleBuildingTarget), so this ground-level
## bar (hidden behind the sprite) is switched off there.
var show_health_bar := true
var hit_tween: Tween
## Presentation extras for buildings: the foundation plate, the level badge and the ambient animation layer.
var footprint := Vector2i.ZERO
var level := 1
var show_level_badge := false
var _decor_ready := false
var _ambient: BuildingAmbientFx
var _sprite: Sprite2D
var _animator: AnimatedSprite2D
var _cannon_pivot: Node2D
var _cannon_gun: Sprite2D
var _cannon_target_angle := 0.0


func configure_structure(id: String, type: String, texture: Texture2D, dimensions: Vector2, shadow_size: Vector2, ground_offset: Vector2, rotating_cannon: bool = false) -> void:
	entity_id = id
	entity_kind = "structure"
	entity_type = type
	shadow_radius = shadow_size
	shadow_offset = ground_offset
	_sprite = Sprite2D.new()
	_sprite.name = "Art"
	_sprite.texture = CANNON_BASE if rotating_cannon and type == "cannon" else texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = true
	_sprite.position = Vector2(0, -dimensions.y * 0.5)
	if texture != null and texture.get_size().x > 0 and texture.get_size().y > 0:
		_sprite.scale = dimensions / texture.get_size()
	add_child(_sprite)
	if rotating_cannon and type == "cannon":
		_cannon_pivot = Node2D.new()
		_cannon_pivot.name = "CannonAimPivot"
		_cannon_pivot.position = CANNON_PIVOT_IN_ENTITY
		_cannon_gun = Sprite2D.new()
		_cannon_gun.name = "CannonGun"
		_cannon_gun.texture = CANNON_GUN
		_cannon_gun.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_cannon_gun.centered = true
		_cannon_gun.scale = _sprite.scale
		_cannon_gun.position = _sprite.position - _cannon_pivot.position
		_cannon_pivot.add_child(_cannon_gun)
		add_child(_cannon_pivot)
	queue_redraw()


## Called by the object layer once a structure's art exists. `village_mode` adds the level badge and ambient life.
func setup_decor(footprint_cells: Vector2i, structure_level: int, village_mode: bool, sprite_dimensions: Vector2) -> void:
	footprint = footprint_cells
	level = maxi(structure_level, 1)
	show_level_badge = village_mode
	if village_mode and BuildingAmbientFx.supports(entity_type) and _ambient == null:
		_ambient = BuildingAmbientFx.new()
		_ambient.name = "AmbientFx"
		add_child(_ambient)
		_ambient.configure(entity_type, sprite_dimensions)
	_decor_ready = true
	queue_redraw()


## Keeps the badge in step with the model and plays a celebration when a building levels up.
func set_level(new_level: int) -> void:
	new_level = maxi(new_level, 1)
	if new_level == level:
		return
	var leveled_up := new_level > level and _decor_ready
	level = new_level
	if leveled_up:
		play_placement()
		if _ambient != null:
			_ambient.burst()
	queue_redraw()


func configure_troop(id: String, type: String, texture: Texture2D, dimensions: Vector2, frames: SpriteFrames = null) -> void:
	entity_id = id
	entity_kind = "unit"
	entity_type = type
	shadow_radius = Vector2(15.0, 6.5)
	shadow_offset = Vector2.ZERO
	if frames != null:
		_animator = AnimatedSprite2D.new()
		_animator.sprite_frames = frames
		_animator.animation = "idle"
		_animator.position.y = -dimensions.y * 0.5
		var first_frame: Texture2D = frames.get_frame_texture("idle", 0)
		if first_frame != null:
			_animator.scale = dimensions / first_frame.get_size()
		_animator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_animator)
		_animator.play("idle")
	else:
		configure_static_unit(texture, dimensions)
	queue_redraw()


func configure_static_unit(texture: Texture2D, dimensions: Vector2) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position.y = -dimensions.y * 0.5
	if texture != null and texture.get_size().x > 0 and texture.get_size().y > 0:
		_sprite.scale = dimensions / texture.get_size()
	add_child(_sprite)


func set_walking(moving: bool, facing_left: bool) -> void:
	if _animator != null:
		var desired := "walk" if moving else "idle"
		if _animator.animation != desired:
			_animator.play(desired)
		_animator.flip_h = facing_left
	elif _sprite != null:
		_sprite.flip_h = facing_left


func set_cannon_aim(direction: Vector2) -> void:
	if _cannon_pivot == null or direction.length_squared() < 0.001:
		return
	_cannon_target_angle = direction.angle() - CANNON_GUN_ART_ANGLE


func _process(delta: float) -> void:
	if _cannon_pivot != null:
		_cannon_pivot.rotation = rotate_toward(_cannon_pivot.rotation, _cannon_target_angle, 5.0 * delta)


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	queue_redraw()


func set_health(value: int, maximum: int) -> void:
	if maximum <= 0:
		return
	var was_damaged := max_health > 0 and value < current_health
	max_health = maximum
	current_health = maxi(0, value)
	if was_damaged:
		flash_hit()
	queue_redraw()


func flash_hit() -> void:
	if _sprite == null and _animator == null:
		return
	var art: CanvasItem = (_sprite as CanvasItem) if _sprite != null else (_animator as CanvasItem)
	if hit_tween != null and hit_tween.is_running():
		hit_tween.kill()
	var flashing_art: Array[CanvasItem] = [art]
	if _cannon_gun != null:
		flashing_art.append(_cannon_gun)
	hit_tween = create_tween().set_parallel(true)
	for item in flashing_art:
		item.modulate = Color(1.0, 0.68, 0.53, 1.0)
		hit_tween.tween_property(item, "modulate", Color.WHITE, 0.24)


func play_placement() -> void:
	var art: Node2D = (_sprite as Node2D) if _sprite != null else (_animator as Node2D)
	if art == null:
		return
	var target_scale := art.scale
	art.scale = target_scale * 0.68
	var animation := create_tween()
	animation.set_trans(Tween.TRANS_BACK)
	animation.set_ease(Tween.EASE_OUT)
	animation.tween_property(art, "scale", target_scale, 0.22)


func _draw() -> void:
	_draw_foundation()
	# Soft layered ellipse, no texture files or per-frame allocations.
	for band in range(3):
		var scale_factor := 1.0 - float(band) * 0.18
		_draw_ellipse(shadow_offset + Vector2(0, 2), shadow_radius * scale_factor, Color(0.045, 0.085, 0.06, 0.10 + band * 0.035))
	if is_selected:
		_draw_ellipse(shadow_offset, shadow_radius * 1.45, Color(1.0, 0.78, 0.34, 0.16))
		_draw_ellipse_outline(shadow_offset, shadow_radius * 1.4, Color("ffda73", 0.85))
	if show_health_bar and max_health > 0 and current_health < max_health and current_health > 0:
		var ratio := clampf(float(current_health) / float(max_health), 0.0, 1.0)
		var top := Vector2(-25, -shadow_radius.y - 29)
		draw_rect(Rect2(top, Vector2(50, 6)), Color("152027", 0.86))
		draw_rect(Rect2(top + Vector2(1, 1), Vector2(48 * ratio, 4)), Color("70db87") if ratio > .45 else Color("eea05a") if ratio > .2 else Color("e7645c"))
	_draw_level_badge()


## A packed-earth plate under the building, tinted by the building's own colour, so it sits on the ground
## instead of floating on the grass. Corner maths follows the isometric grid (see VillageGrid).
func _draw_foundation() -> void:
	if entity_kind != "structure" or footprint == Vector2i.ZERO or entity_type == "wall" or entity_type == "cannon":
		return
	var fx := float(footprint.x)
	var fy := float(footprint.y)
	var tx := VillageGrid.TILE_SIZE.x * 0.25
	var ty := VillageGrid.TILE_SIZE.y * 0.5
	var front := Vector2((fx - fy) * tx, 0.0)
	var right := Vector2((fx + fy) * tx, -fy * ty)
	var back := Vector2((fy - fx) * tx, -(fx + fy) * ty)
	var left := Vector2(-(fx + fy) * tx, -fx * ty)
	var tint: Color = BuildingCatalog.get_definition(entity_type).get("color", Color("8b7355"))
	var earth := Color(0.47, 0.40, 0.30).lerp(tint, 0.22)
	draw_colored_polygon(PackedVector2Array([front, right, back, left]), Color(earth, 0.55))
	var middle := (front + right + back + left) * 0.25
	draw_colored_polygon(PackedVector2Array([
		middle.lerp(front, 0.86), middle.lerp(right, 0.86), middle.lerp(back, 0.86), middle.lerp(left, 0.86),
	]), Color(earth.lightened(0.18), 0.30))
	# Faint flagstone seams, one per tile.
	for i in range(1, footprint.x):
		var t := float(i) / fx
		draw_line(left.lerp(front, t), back.lerp(right, t), Color(0.12, 0.09, 0.06, 0.20), 1.0)
	for j in range(1, footprint.y):
		var u := float(j) / fy
		draw_line(front.lerp(right, u), left.lerp(back, u), Color(0.12, 0.09, 0.06, 0.20), 1.0)
	draw_polyline(PackedVector2Array([left, front, right]), Color(0.17, 0.12, 0.08, 0.65), 2.0, true)
	draw_polyline(PackedVector2Array([left, back, right]), Color(1.0, 0.95, 0.8, 0.22), 1.5, true)


func _draw_level_badge() -> void:
	if not show_level_badge or entity_kind != "structure" or level < 2 or entity_type == "wall":
		return
	var tier_color := Color("cfdde6")
	if level >= 7:
		tier_color = Color("c9a2ff")
	elif level >= 4:
		tier_color = Color("ffd567")
	var font := ThemeDB.fallback_font
	var label := "LV %d" % level
	var center := Vector2(0.0, 17.0)
	var rect := Rect2(center - Vector2(22.0, 9.0), Vector2(44.0, 18.0))
	draw_rect(rect, Color(0.07, 0.10, 0.13, 0.88))
	draw_rect(rect, tier_color, false, 1.6)
	draw_string(font, center + Vector2(-22.0, 4.5), label, HORIZONTAL_ALIGNMENT_CENTER, 44.0, 12, tier_color)


func _draw_ellipse(center: Vector2, radius: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, fill)


func _draw_ellipse_outline(center: Vector2, radius: Vector2, line_color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(17):
		var angle := TAU * float(i) / 16.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_polyline(points, line_color, 2.0, true)
