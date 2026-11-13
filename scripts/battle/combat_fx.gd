extends Node2D
## Compact presentation effects. No custom shader or external particle textures.

## Battle seconds that pass per real second: 0 while the battle is paused, the battle speed otherwise.
## Projectiles use it so arrows and spells slow down, speed up and freeze together with the battle.
var time_scale := 1.0


## An arrow ("arrow") or a spell ("magic") travelling from `from_position` to `to_position` (world space)
## in `flight_time` battle seconds, followed by an impact burst where it lands.
func fire_projectile(kind: String, from_position: Vector2, to_position: Vector2, flight_time: float) -> void:
	var projectile := Projectile.new()
	projectile.configure(self, kind, to_local(from_position), to_local(to_position), maxf(flight_time, 0.05))
	add_child(projectile)


## A short burst where an arrow or spell lands (world space).
func impact(kind: String, where: Vector2) -> void:
	spawn_impact_local(kind, to_local(where))


func spawn_impact_local(kind: String, where: Vector2) -> void:
	var burst := ImpactBurst.new()
	burst.configure(self, kind)
	burst.position = where
	add_child(burst)


func damage_number(where: Vector2, amount: int, heavy: bool = false) -> void:
	var label := Label.new()
	label.text = "-%d" % amount
	label.position = where + Vector2(-12, -82)
	label.z_index = 15
	label.add_theme_font_size_override("font_size", 21 if heavy else 16)
	label.add_theme_color_override("font_color", Color("ffd18a") if heavy else Color("fff0db"))
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 43, 0.64)
	tween.tween_property(label, "modulate:a", 0.0, 0.64)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	if heavy:
		var flash := ColorRect.new()
		flash.color = Color("ffdf97", 0.25)
		flash.position = where - Vector2(19, 35)
		flash.size = Vector2(38, 38)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flash)
		var fade := create_tween()
		fade.tween_property(flash, "modulate:a", 0.0, 0.15)
		fade.tween_callback(flash.queue_free)


func crumble(where: Vector2) -> void:
	var debris := CPUParticles2D.new()
	debris.position = where + Vector2(0, -18)
	debris.amount = 14
	debris.lifetime = 0.65
	debris.one_shot = true
	debris.explosiveness = 0.94
	debris.direction = Vector2(0, -1)
	debris.spread = 85
	debris.gravity = Vector2(0, 155)
	debris.initial_velocity_min = 35
	debris.initial_velocity_max = 85
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = 5.0
	debris.color = Color("b9a38a", 0.88)
	add_child(debris)
	debris.emitting = true
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(debris.queue_free)


class Projectile extends Node2D:
	var _fx: Node
	var _kind := "arrow"
	var _from := Vector2.ZERO
	var _to := Vector2.ZERO
	var _duration := 0.2
	var _age := 0.0
	var _arc := 0.0
	var _angle := 0.0
	var _trail: Array[Vector2] = []
	var _visual_scale := 1.0

	func configure(fx: Node, kind: String, from_local: Vector2, to_local_position: Vector2, duration: float) -> void:
		_fx = fx
		_kind = kind
		_from = from_local
		_to = to_local_position
		_duration = duration
		z_index = 25
		# Arrows fly in a gentle arc; spells fly straight and slightly wobble.
		_arc = clampf(_from.distance_to(_to) * 0.16, 6.0, 44.0) if kind == "arrow" else 0.0
		position = _from
		_angle = (_to - _from).angle()

	func _point_at(progress: float) -> Vector2:
		var p := clampf(progress, 0.0, 1.0)
		var point := _from.lerp(_to, p)
		point.y -= _arc * sin(p * PI)
		if _kind == "magic":
			var side := (_to - _from).orthogonal().normalized()
			point += side * sin(p * PI * 6.0) * 3.5 * (1.0 - p)
		return point

	func _process(delta: float) -> void:
		var scale_value := 1.0
		if is_instance_valid(_fx):
			scale_value = float(_fx.get("time_scale"))
		_age += delta * scale_value
		var progress := _age / _duration
		if progress >= 1.0:
			if is_instance_valid(_fx):
				_fx.spawn_impact_local(_kind, _to)
			queue_free()
			return
		var point := _point_at(progress)
		var ahead := _point_at(minf(progress + 0.04, 1.0))
		if ahead.distance_squared_to(point) > 0.01:
			_angle = (ahead - point).angle()
		position = point
		# Zoomed-out cameras shrink everything, so arrows and spells grow to stay readable.
		_visual_scale = clampf(1.0 / maxf(get_canvas_transform().get_scale().x, 0.05), 1.0, 2.2) if is_inside_tree() else 1.0
		_trail.append(point)
		if _trail.size() > 7:
			_trail.pop_front()
		queue_redraw()

	func _draw() -> void:
		if _kind == "magic":
			var pulse := 1.0 + 0.18 * sin(_age * 38.0)
			for index in range(_trail.size() - 1):
				var fade := float(index + 1) / float(_trail.size())
				draw_circle(_trail[index] - position, 6.5 * fade, Color(0.62, 0.45, 1.0, 0.30 * fade))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(_visual_scale, _visual_scale))
			draw_circle(Vector2.ZERO, 13.0 * pulse, Color(0.55, 0.38, 1.0, 0.28))
			draw_circle(Vector2.ZERO, 8.5 * pulse, Color(0.76, 0.60, 1.0, 0.88))
			draw_circle(Vector2.ZERO, 4.5, Color(0.97, 0.93, 1.0))
			for index in range(3):
				var orbit := _age * 14.0 + TAU * float(index) / 3.0
				draw_circle(Vector2(cos(orbit), sin(orbit)) * 11.0, 1.8, Color(1.0, 0.95, 1.0, 0.9))
			return
		var direction := Vector2.RIGHT.rotated(_angle)
		var side := direction.orthogonal()
		for index in range(_trail.size() - 1):
			var fade := float(index) / float(_trail.size())
			draw_line(_trail[index] - position, _trail[index + 1] - position, Color(1.0, 0.96, 0.8, 0.10 + 0.30 * fade), 1.6, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(_visual_scale, _visual_scale))
		draw_line(direction * -15.0, direction * 9.0, Color("e9d9a6"), 2.4, true)
		draw_colored_polygon(PackedVector2Array([direction * 18.0, direction * 8.0 + side * 3.8, direction * 8.0 - side * 3.8]), Color("e3e8ec"))
		draw_line(direction * -15.0, direction * -21.0 + side * 3.6, Color("c94b3b"), 2.0, true)
		draw_line(direction * -15.0, direction * -21.0 - side * 3.6, Color("c94b3b"), 2.0, true)


class ImpactBurst extends Node2D:
	var _fx: Node
	var _kind := "arrow"
	var _age := 0.0
	var _life := 0.24
	var _visual_scale := 1.0

	func configure(fx: Node, kind: String) -> void:
		_fx = fx
		_kind = kind
		_life = 0.36 if kind == "magic" else 0.24
		z_index = 26

	func _process(delta: float) -> void:
		var scale_value := 1.0
		if is_instance_valid(_fx):
			scale_value = float(_fx.get("time_scale"))
		_age += delta * scale_value
		if _age >= _life:
			queue_free()
			return
		_visual_scale = clampf(1.0 / maxf(get_canvas_transform().get_scale().x, 0.05), 1.0, 2.2) if is_inside_tree() else 1.0
		queue_redraw()

	func _draw() -> void:
		var progress := clampf(_age / _life, 0.0, 1.0)
		var fade := 1.0 - progress
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(_visual_scale, _visual_scale))
		if _kind == "magic":
			draw_circle(Vector2.ZERO, 12.0 * fade, Color(0.8, 0.65, 1.0, 0.5 * fade))
			draw_arc(Vector2.ZERO, 6.0 + 24.0 * progress, 0.0, TAU, 28, Color(0.85, 0.72, 1.0, 0.9 * fade), 3.0, true)
			for index in range(8):
				var spark := Vector2.RIGHT.rotated(TAU * float(index) / 8.0)
				draw_line(spark * (8.0 + 16.0 * progress), spark * (14.0 + 24.0 * progress), Color(0.95, 0.88, 1.0, fade), 2.2, true)
			return
		draw_arc(Vector2.ZERO, 3.0 + 9.0 * progress, 0.0, TAU, 16, Color(1.0, 0.93, 0.65, 0.9 * fade), 2.2, true)
		for index in range(5):
			var spark := Vector2.RIGHT.rotated(-PI * 0.5 + (float(index) - 2.0) * 0.55)
			draw_line(spark * (4.0 + 6.0 * progress), spark * (9.0 + 13.0 * progress), Color(1.0, 0.95, 0.75, fade), 2.0, true)
