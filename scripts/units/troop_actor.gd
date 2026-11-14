extends Node2D
class_name TroopActor
## Unit state machine and sprite sheet animation for battle scenes.

enum State { IDLE, SELECT_TARGET, MOVE, ATTACK, RECOVER, DEAD, STUNNED, FLEE, RETURN }
enum Team { ATTACKER, DEFENDER }

signal attack_requested(attacker: TroopActor, target: Node2D, damage: int)
signal died(actor: TroopActor)
signal state_changed(previous_state: State, new_state: State)

var troop_id := "warrior"
var display_name := "Warrior"
var troop_level := 1
var max_hp := 1
var hp := 1
var damage := 1
var attack_range := 48.0
var move_speed := 1.0
var attack_interval := 1.0
var simulation_speed := 1.0
var state: State = State.IDLE
var target: Node2D
var facing_direction := Vector2.UP
var movement_path: Array[Vector2] = []
var waypoint_index := 0
## Defender-only bookkeeping, driven by BattleManager. Attackers leave these at their defaults.
var team: Team = Team.ATTACKER
var home_position := Vector2.ZERO
var leash_center := Vector2.ZERO
var leash_radius := 0.0
var castle_id := ""
var think_cooldown := 0.0
var repath_cooldown := 0.0

var _attack_cooldown := 0.0
var _attack_flash := 0.0
## "arrow" or "magic" for ranged troops (BattleManager launches the matching projectile), "" for melee.
var projectile_kind := ""
var _hit_flash := 0.0
var _hit_point := Vector2(0, -30)
var _death_elapsed := 0.0
var _walk_phase := 0.0
var _animation_time := 0.0
var _art_sprite: Sprite2D
var _animated_sprite: AnimatedSprite2D
static var _shared_frames: Dictionary = {}

const SPRITES := {
	"warrior": preload("res://assets/troops/warrior_sprite.png"),
	"archer": preload("res://assets/troops/archer_sprite.png"),
	"mage": preload("res://assets/troops/mage_sprite.png"),
	"goblin": preload("res://assets/troops/goblin_sprite.png"),
	"tank": preload("res://assets/troops/tank_sprite.png"),
}


func configure(unit_type: String, level: int = 1) -> bool:
	var definition := TroopCatalog.get_definition(unit_type)
	if definition.is_empty():
		push_warning("Unknown troop type '%s'." % unit_type)
		return false
	troop_id = unit_type
	display_name = definition["name"]
	troop_level = clampi(level, 1, TroopCatalog.MAX_LEVEL)
	max_hp = TroopCatalog.hp_at_level(unit_type, troop_level)
	hp = max_hp
	damage = TroopCatalog.damage_at_level(unit_type, troop_level)
	attack_range = float(definition["range"]) * 48.0
	move_speed = float(definition["move_speed"])
	attack_interval = float(definition["attack_speed"])
	projectile_kind = str(definition.get("projectile", ""))
	_build_visual()
	queue_redraw()
	return true


## Where a shot leaves the troop (local offset to the bow / staff, and the same point in world space).
func projectile_origin_local() -> Vector2:
	return Vector2(0, -38) + facing_direction.normalized() * 9.0


func projectile_origin() -> Vector2:
	return global_position + projectile_origin_local()


func assign_target(new_target: Node2D) -> void:
	if state == State.DEAD or not is_instance_valid(new_target):
		return
	target = new_target
	var target_direction := target.global_position - global_position
	if target_direction.length_squared() > 0.01:
		facing_direction = target_direction.normalized()
	_attack_cooldown = 0.0
	_change_state(State.SELECT_TARGET)
	queue_redraw()


func set_walk_path(path_cells: Array[Vector2i], grid: VillageGrid) -> void:
	movement_path.clear()
	waypoint_index = 0
	for cell in path_cells:
		var point := grid.cell_to_world(Vector2(cell))
		if point.distance_to(global_position) > 3.0:
			movement_path.append(point)
	# A re-plan issued mid-step must not make the troop walk back to the centre of the cell it is leaving.
	if movement_path.size() >= 2 and global_position.distance_to(movement_path[1]) < movement_path[0].distance_to(movement_path[1]):
		movement_path.remove_at(0)


## Walk to a point without a target (defenders returning to their castle).
func walk_home(path_cells: Array[Vector2i], grid: VillageGrid) -> void:
	if state == State.DEAD:
		return
	target = null
	set_walk_path(path_cells, grid)
	if movement_path.is_empty():
		_change_state(State.IDLE)
	else:
		_change_state(State.RETURN)
	queue_redraw()


func clear_target() -> void:
	target = null
	_change_state(State.IDLE)


func set_simulation_speed(multiplier: float) -> void:
	simulation_speed = clampf(multiplier, 1.0, 5.0)


func apply_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEAD or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	_hit_flash = 0.28
	_sync_visual()
	if source_position != Vector2.ZERO:
		var incoming := to_local(source_position).normalized()
		_hit_point = incoming * 9.0 + Vector2(0, -28)
	queue_redraw()
	if hp == 0:
		target = null
		_death_elapsed = 0.0
		_change_state(State.DEAD)
		died.emit(self)


func step(delta: float) -> void:
	_animation_time += delta
	_hit_flash = maxf(0.0, _hit_flash - delta)
	if _hit_flash > 0.0 or _attack_flash > 0.0 or state == State.DEAD:
		queue_redraw()
	_sync_visual()
	if state == State.DEAD:
		_death_elapsed += delta
		modulate.a = clampf(1.0 - _death_elapsed / 0.7, 0.0, 1.0)
		queue_redraw()
		if _death_elapsed >= 0.7:
			queue_free()
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_attack_flash = maxf(0.0, _attack_flash - delta)
	if _attack_flash > 0.0:
		queue_redraw()
	if state == State.RETURN:
		_step_return(delta)
		return
	if not is_instance_valid(target):
		target = null
		if state != State.IDLE:
			_change_state(State.SELECT_TARGET)
		if state == State.SELECT_TARGET:
			_change_state(State.IDLE)
		return
	if state == State.SELECT_TARGET or state == State.IDLE or state == State.RECOVER:
		_evaluate_target_distance()
		return
	if state == State.MOVE:
		_evaluate_target_distance()
		if state == State.MOVE and is_instance_valid(target):
			if waypoint_index < movement_path.size():
				var waypoint := movement_path[waypoint_index]
				var move_vector := waypoint - global_position
				if move_vector.length() > 1.5:
					facing_direction = move_vector.normalized()
					global_position = global_position.move_toward(waypoint, move_speed * delta)
					_walk_phase = fposmod(_walk_phase + delta * 12.0, TAU)
				else:
					waypoint_index += 1
			else:
				# Do not fall back to direct movement through walls if a route is exhausted.
				target = null
				_change_state(State.IDLE)
			return
	if state == State.ATTACK:
		facing_direction = (target.global_position - global_position).normalized()
		if _attack_cooldown <= 0.0 and is_instance_valid(target):
			attack_requested.emit(self, target, damage)
			_attack_cooldown = attack_interval
			_attack_flash = 0.48
			_sync_visual()
			queue_redraw()
		_change_state(State.RECOVER)
		return
	if state == State.STUNNED or state == State.FLEE:
		_change_state(State.SELECT_TARGET)


func _step_return(delta: float) -> void:
	if waypoint_index >= movement_path.size():
		_change_state(State.IDLE)
		return
	var waypoint := movement_path[waypoint_index]
	var move_vector := waypoint - global_position
	if move_vector.length() > 1.5:
		facing_direction = move_vector.normalized()
		global_position = global_position.move_toward(waypoint, move_speed * delta)
		_walk_phase = fposmod(_walk_phase + delta * 12.0, TAU)
	else:
		waypoint_index += 1


func _process(delta: float) -> void:
	step(delta * simulation_speed)


func _evaluate_target_distance() -> void:
	if not is_instance_valid(target):
		_change_state(State.IDLE)
		return
	var target_delta := target.global_position - global_position
	if target_delta.length_squared() > 0.01:
		facing_direction = target_delta.normalized()
	var distance := target_delta.length()
	if distance <= attack_range:
		_change_state(State.ATTACK if _attack_cooldown <= 0.0 else State.RECOVER)
	else:
		_change_state(State.MOVE)


func _change_state(next_state: State) -> void:
	if state == next_state:
		return
	var previous := state
	state = next_state
	_sync_visual()
	state_changed.emit(previous, state)


func _build_visual() -> void:
	if _art_sprite != null:
		_art_sprite.queue_free()
		_art_sprite = null
	if _animated_sprite != null:
		_animated_sprite.queue_free()
		_animated_sprite = null
	var dimensions := Vector2(55, 71)
	if troop_id == "mage":
		dimensions = Vector2(53, 75)
	elif troop_id == "goblin":
		dimensions = Vector2(51, 65)
	elif troop_id == "tank":
		dimensions = Vector2(78, 66)
	if TroopSpriteFrames.SHEETS.has(troop_id):
		if not _shared_frames.has(troop_id):
			var frame_bank := SpriteFrames.new()
			for animation in ["idle", "walk", "attack", "death"]:
				frame_bank.add_animation(animation)
				frame_bank.set_animation_speed(animation, 10)
				frame_bank.set_animation_loop(animation, animation != "death")
				var row_data: Array = TroopSpriteFrames.ROWS[troop_id][animation]
				for i in range(int(row_data[1])):
					var piece := AtlasTexture.new()
					piece.atlas = TroopSpriteFrames.texture_for(troop_id)
					piece.region = TroopSpriteFrames.region_for(troop_id, animation, i)
					frame_bank.add_frame(animation, piece)
			_shared_frames[troop_id] = frame_bank
		_animated_sprite = AnimatedSprite2D.new()
		_animated_sprite.name = "CharacterAnimation"
		_animated_sprite.sprite_frames = _shared_frames[troop_id]
		_animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_animated_sprite.position.y = -dimensions.y * .5
		var frame: Texture2D = _animated_sprite.sprite_frames.get_frame_texture("idle", 0)
		_animated_sprite.scale = dimensions / frame.get_size()
		add_child(_animated_sprite)
		_animated_sprite.play("idle")
	else:
		_art_sprite = Sprite2D.new()
		_art_sprite.name = "CharacterArt"
		var texture: Texture2D = SPRITES.get(troop_id)
		if troop_id == "tank":
			var source_path := "res://assets/generated/siege_wagon.png"
			if ResourceLoader.exists(source_path):
				texture = load(source_path)
			else:
				var generated := Image.load_from_file(ProjectSettings.globalize_path(source_path))
				if generated != null and not generated.is_empty():
					texture = ImageTexture.create_from_image(generated)
		_art_sprite.texture = texture
		_art_sprite.position.y = -dimensions.y * .5
		_art_sprite.scale = dimensions / texture.get_size()
		_art_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_art_sprite)
	_sync_visual()


func _sync_visual() -> void:
	var left := facing_direction.x < -0.05
	var base_color := Color(0.82, 0.92, 1.0) if team == Team.DEFENDER else Color.WHITE
	var flash_color := Color(1.0, 0.73, 0.67) if _hit_flash > 0.0 else base_color
	if _animated_sprite != null:
		var animation := "idle"
		if state == State.DEAD:
			animation = "death"
		elif _attack_flash > 0.0 or state == State.ATTACK:
			animation = "attack"
		elif state == State.MOVE or state == State.RETURN:
			animation = "walk"
		if _animated_sprite.animation != animation:
			_animated_sprite.play(animation)
		_animated_sprite.flip_h = left
		_animated_sprite.modulate = flash_color
	elif _art_sprite != null:
		_art_sprite.flip_h = left
		_art_sprite.modulate = flash_color


func set_animation_paused(is_paused: bool) -> void:
	if _animated_sprite == null:
		return
	if is_paused:
		_animated_sprite.pause()
	else:
		_animated_sprite.play()


func _draw() -> void:
	# A shadow and brief feedback are the ONLY procedural rendering on actors.
	# The body is a real Sprite2D / AnimatedSprite2D child, Y-sorted by its feet.
	var shadow_color := Color(0.045, 0.075, 0.06, 0.29)
	if team == Team.DEFENDER:
		shadow_color = Color(0.10, 0.20, 0.55, 0.42)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-15, 1), Vector2(0, -5), Vector2(15, 1), Vector2(0, 7),
	]), shadow_color)
	if team == Team.DEFENDER and state != State.DEAD:
		# Small blue shield so defenders are readable at a glance.
		draw_colored_polygon(PackedVector2Array([
			Vector2(-6, -98), Vector2(6, -98), Vector2(6, -90), Vector2(0, -85), Vector2(-6, -90),
		]), Color("3b66c4"))
		draw_polyline(PackedVector2Array([Vector2(-6, -98), Vector2(6, -98), Vector2(6, -90), Vector2(0, -85), Vector2(-6, -90), Vector2(-6, -98)]), Color("d8e2ff"), 1.5)
	if hp > 0 and hp < max_hp:
		var health_ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		draw_rect(Rect2(-21, -83, 42, 6), Color("17262b", 0.94))
		draw_rect(Rect2(-20, -82, 40 * health_ratio, 4), Color("71d994") if health_ratio > .4 else Color("e58a59"))
	_draw_hit_effect()
	if _attack_flash > 0.0:
		_draw_attack_effect()


func _draw_hit_effect() -> void:
	if _hit_flash <= 0.0:
		return
	var progress := 1.0 - _hit_flash / 0.28
	var radius := 5.0 + progress * 9.0
	draw_arc(_hit_point, radius, 0.0, TAU, 20, Color(1.0, 0.93, 0.58, 1.0 - progress), 2.5, true)
	for index in range(4):
		var direction := Vector2.RIGHT.rotated(float(index) * PI * 0.5)
		draw_line(_hit_point + direction * (radius + 1.0), _hit_point + direction * (radius + 5.0), Color("fff2b2", 1.0 - progress), 2.0, true)


func _draw_attack_effect() -> void:
	var direction := facing_direction.normalized()
	var origin := projectile_origin_local()
	# 1.0 at the instant of the attack, fading to 0.0 as the cue ends.
	var fade := clampf(_attack_flash / 0.48, 0.0, 1.0)
	if projectile_kind == "arrow":
		# The arrow itself flies to the target (CombatFx); this is the release flash at the bow.
		var strength := clampf((fade - 0.5) / 0.5, 0.0, 1.0)
		if strength > 0.0:
			for index in range(3):
				var fan := direction.rotated(float(index - 1) * 0.55)
				draw_line(origin + fan * 4.0, origin + fan * (9.0 + 9.0 * strength), Color(1.0, 0.94, 0.71, strength), 2.2, true)
			draw_circle(origin, 3.0 * strength, Color(1.0, 0.97, 0.8, strength))
	elif projectile_kind == "magic":
		# The bolt itself flies to the target (CombatFx); this is the spell gathering at the staff.
		var strength := clampf((fade - 0.35) / 0.65, 0.0, 1.0)
		if strength > 0.0:
			draw_circle(origin, 5.0 + 7.0 * strength, Color(0.62, 0.45, 1.0, 0.35 * strength))
			draw_circle(origin, 3.0 + 3.0 * strength, Color(0.79, 0.65, 1.0, 0.8 * strength))
			draw_circle(origin, 2.0, Color(0.96, 0.92, 1.0, strength))
			draw_arc(origin, 8.0 + 10.0 * (1.0 - strength), 0.0, TAU, 20, Color(0.85, 0.75, 1.0, 0.7 * strength), 1.6, true)
	else:
		var angle := direction.angle()
		draw_arc(origin + direction * 6.0, 22.0, angle - 0.55, angle + 0.55, 10, Color("ffe38d"), 2.5, true)
