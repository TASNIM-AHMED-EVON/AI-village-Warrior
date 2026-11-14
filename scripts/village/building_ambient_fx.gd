extends Node2D
class_name BuildingAmbientFx
## Presentation-only ambient life for buildings: fountain spray, bubbling elixir, glinting gold, torch embers,
## waving banners, a floating laboratory orb, and a burst when a building is upgraded.
## It owns no gameplay data and is only created in the village (never in battle).

const SUPPORTED := ["town_hall", "barracks", "laboratory", "clan_castle", "gold_mine", "elixir_pump", "archer_tower"]
const MAX_PARTICLES := 90

var building_type := ""
var sprite_size := Vector2(100.0, 100.0)
var _time := 0.0
var _particles: Array[Dictionary] = []
var _accumulators: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _burst_time := -1.0


static func supports(type: String) -> bool:
	return SUPPORTED.has(type)


func configure(type: String, size: Vector2) -> void:
	building_type = type
	sprite_size = size
	_rng.randomize()
	_time = _rng.randf() * 20.0  # Every building animates out of step with its neighbours.
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-size.x * 0.7, -size.y * 1.5, size.x * 1.4, size.y * 1.9)
	notifier.screen_entered.connect(func() -> void: set_process(true); visible = true)
	notifier.screen_exited.connect(func() -> void: set_process(false); visible = false)
	add_child(notifier)


## A burst of golden sparks and a ground ring, played when the building is upgraded.
func burst() -> void:
	_burst_time = 0.0
	for _i in range(26):
		var angle := _rng.randf() * TAU
		var speed := _rng.randf_range(55.0, 140.0)
		_add_particle("twinkle", _at(0.5, 0.78), Vector2(cos(angle) * speed, sin(angle) * speed * 0.55 - 45.0),
				_rng.randf_range(0.7, 1.1), _rng.randf_range(3.0, 5.5), Color(1.0, 0.86, 0.38), 130.0)


## Local position of a point on the sprite, given in 0..1 across (u) and down (v) its picture.
func _at(u: float, v: float) -> Vector2:
	return Vector2((u - 0.5) * sprite_size.x, -sprite_size.y + v * sprite_size.y)


func _tick(key: String, rate: float, delta: float) -> int:
	var total: float = float(_accumulators.get(key, 0.0)) + rate * delta
	var whole := int(total)
	_accumulators[key] = total - float(whole)
	return whole


func _add_particle(kind: String, where: Vector2, velocity: Vector2, life: float, size: float, color: Color, gravity: float = 0.0) -> void:
	if _particles.size() >= MAX_PARTICLES:
		return
	_particles.append({"kind": kind, "pos": where, "vel": velocity, "life": life, "max": life, "size": size, "color": color, "g": gravity})


func _jitter(amount: float) -> Vector2:
	return Vector2(_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount))


func _process(delta: float) -> void:
	_time += delta
	match building_type:
		"town_hall":
			for _i in _tick("water", 16.0, delta):
				_add_particle("water", _at(0.79, 0.76) + _jitter(2.0), Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-78.0, -52.0)), 0.75, 1.9, Color(0.72, 0.9, 1.0), 175.0)
			for _i in _tick("twinkle", 0.5, delta):
				_add_particle("twinkle", _at(0.555, 0.30) + _jitter(7.0), Vector2.ZERO, 0.7, 4.2, Color(1.0, 0.95, 0.7))
		"barracks":
			for _i in _tick("dust", 1.8, delta):
				_add_particle("dust", _at(0.80, 0.82) + _jitter(10.0), Vector2(_rng.randf_range(4.0, 12.0), _rng.randf_range(-10.0, -4.0)), 1.4, 4.0, Color(0.74, 0.64, 0.5))
		"laboratory":
			for _i in _tick("bubble", 5.0, delta):
				var tint: Color = [Color(0.55, 1.0, 0.85), Color(0.78, 0.62, 1.0), Color(0.6, 0.85, 1.0)][_rng.randi() % 3]
				_add_particle("bubble", _at(0.52, 0.30) + _jitter(5.0), Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-34.0, -20.0)), _rng.randf_range(1.3, 2.0), _rng.randf_range(2.2, 4.2), tint)
			for _i in _tick("spark", 1.4, delta):
				_add_particle("twinkle", _at(0.5, 0.06) + _jitter(14.0), Vector2.ZERO, 0.6, 3.6, Color(0.85, 0.78, 1.0))
		"elixir_pump":
			for _i in _tick("bubble", 7.0, delta):
				var tint: Color = [Color(0.95, 0.55, 1.0), Color(0.8, 0.5, 1.0), Color(1.0, 0.7, 0.95)][_rng.randi() % 3]
				_add_particle("bubble", _at(0.5, 0.33) + Vector2(_rng.randf_range(-16.0, 16.0), _rng.randf_range(-3.0, 3.0)), Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-42.0, -26.0)), _rng.randf_range(1.0, 1.6), _rng.randf_range(2.0, 3.8), tint)
			for _i in _tick("spark", 1.5, delta):
				_add_particle("twinkle", _at(0.5, 0.22) + _jitter(16.0), Vector2.ZERO, 0.65, 3.4, Color(1.0, 0.8, 1.0))
		"gold_mine":
			for _i in _tick("glint", 3.4, delta):
				var spot := _rng.randi() % 3
				var where := _at(_rng.randf_range(0.2, 0.34), _rng.randf_range(0.78, 0.86))
				if spot == 1:
					where = _at(_rng.randf_range(0.38, 0.56), _rng.randf_range(0.82, 0.9))
				elif spot == 2:
					where = _at(_rng.randf_range(0.5, 0.66), _rng.randf_range(0.18, 0.3))
				_add_particle("twinkle", where, Vector2.ZERO, 0.75, _rng.randf_range(3.2, 5.0), Color(1.0, 0.9, 0.45))
			for _i in _tick("dust", 0.9, delta):
				_add_particle("dust", _at(0.5, 0.62) + _jitter(8.0), Vector2(_rng.randf_range(-4.0, 4.0), -9.0), 1.6, 3.4, Color(0.62, 0.52, 0.42))
		"archer_tower":
			for _i in _tick("ember", 7.0, delta):
				_add_particle("ember", _at(0.635, 0.845) + _jitter(2.5), Vector2(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-34.0, -18.0)), _rng.randf_range(0.6, 1.0), _rng.randf_range(1.2, 2.2), Color(1.0, _rng.randf_range(0.5, 0.75), 0.15))
		"clan_castle":
			for _i in _tick("twinkle", 0.7, delta):
				_add_particle("twinkle", _at(0.5, 0.2) + _jitter(16.0), Vector2.ZERO, 0.7, 3.8, Color(0.85, 0.92, 1.0))
	var index := _particles.size() - 1
	while index >= 0:
		var particle := _particles[index]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			_particles.remove_at(index)
		else:
			particle["vel"] = Vector2(particle["vel"]) + Vector2(0.0, float(particle["g"])) * delta
			particle["pos"] = Vector2(particle["pos"]) + Vector2(particle["vel"]) * delta
		index -= 1
	if _burst_time >= 0.0:
		_burst_time += delta
		if _burst_time > 0.9:
			_burst_time = -1.0
	queue_redraw()


func _draw() -> void:
	match building_type:
		"elixir_pump":
			var pulse := 0.5 + 0.5 * sin(_time * 2.4)
			var pool := _at(0.5, 0.31)
			for layer in range(4):
				_ellipse(pool, Vector2(30.0 - layer * 5.0, 12.0 - layer * 2.0), Color(0.85, 0.35, 1.0, (0.07 + 0.05 * pulse) * (1.0 + layer * 0.45)))
		"archer_tower":
			var flicker := 0.75 + 0.25 * sin(_time * 17.0) * sin(_time * 7.3 + 1.0)
			var torch := _at(0.635, 0.855)
			draw_circle(torch, 20.0 * flicker, Color(1.0, 0.55, 0.12, 0.10))
			draw_circle(torch, 12.0 * flicker, Color(1.0, 0.65, 0.18, 0.16))
		"laboratory":
			var orb := _at(0.5, 0.02) + Vector2(0.0, sin(_time * 1.9) * 4.0)
			var glow := 0.6 + 0.4 * sin(_time * 3.0)
			draw_circle(orb, 17.0, Color(0.55, 0.45, 1.0, 0.10 + 0.07 * glow))
			draw_circle(orb, 11.0, Color(0.6, 0.9, 1.0, 0.25 + 0.12 * glow))
			draw_circle(orb, 6.0, Color(0.9, 0.97, 1.0, 0.9))
			for k in range(3):
				var angle := _time * 2.6 + TAU * float(k) / 3.0
				draw_circle(orb + Vector2(cos(angle) * 15.0, sin(angle) * 6.0), 1.8, Color(1.0, 0.95, 1.0, 0.9))
		"barracks":
			_draw_flag(_at(0.63, 0.10), 30.0, 22.0, 12.0, Color("c8402f"), Color("f4cf6a"), 0.0)
		"clan_castle":
			_draw_flag(_at(0.21, 0.27), 17.0, 14.0, 8.0, Color("3d63c8"), Color("e8eeff"), 1.3)
			_draw_flag(_at(0.81, 0.27), 17.0, 14.0, 8.0, Color("3d63c8"), Color("e8eeff"), 2.4)
	for particle in _particles:
		_draw_particle(particle)
	if _burst_time >= 0.0:
		var progress := clampf(_burst_time / 0.9, 0.0, 1.0)
		var ring_center := Vector2(0.0, -sprite_size.y * 0.1)
		_ring(ring_center, Vector2(30.0 + 110.0 * progress, 13.0 + 48.0 * progress), Color(1.0, 0.86, 0.4, 0.9 * (1.0 - progress)), 3.0)
		_ring(ring_center, Vector2(18.0 + 80.0 * progress, 8.0 + 34.0 * progress), Color(1.0, 0.97, 0.75, 0.6 * (1.0 - progress)), 2.0)


func _draw_particle(particle: Dictionary) -> void:
	var t := 1.0 - float(particle["life"]) / float(particle["max"])
	var fade := 1.0 - t
	var where: Vector2 = particle["pos"]
	var size := float(particle["size"])
	var color: Color = particle["color"]
	match str(particle["kind"]):
		"water":
			draw_circle(where, size, Color(color, 0.85 * fade + 0.1))
		"ember":
			draw_circle(where, size * (1.0 - 0.5 * t), Color(color, fade))
			draw_circle(where, size * 0.5, Color(1.0, 0.95, 0.6, fade))
		"dust":
			draw_circle(where, size * (0.7 + 1.3 * t), Color(color, 0.22 * fade))
		"bubble":
			var radius := size * (0.8 + 0.5 * t)
			draw_circle(where, radius, Color(color, 0.22 * fade))
			draw_arc(where, radius, 0.0, TAU, 14, Color(color, 0.9 * fade), 1.3, true)
			draw_circle(where + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.28, Color(1, 1, 1, 0.8 * fade))
		"twinkle":
			var pulse := sin(clampf(t, 0.0, 1.0) * PI)
			var arm := size * pulse
			var star := Color(color, 0.95 * pulse)
			draw_line(where + Vector2(-arm, 0), where + Vector2(arm, 0), star, 1.4, true)
			draw_line(where + Vector2(0, -arm), where + Vector2(0, arm), star, 1.4, true)
			draw_line(where + Vector2(-arm, -arm) * 0.5, where + Vector2(arm, arm) * 0.5, Color(star, star.a * 0.6), 1.0, true)
			draw_line(where + Vector2(-arm, arm) * 0.5, where + Vector2(arm, -arm) * 0.5, Color(star, star.a * 0.6), 1.0, true)
			draw_circle(where, maxf(arm * 0.28, 0.6), Color(1.0, 1.0, 1.0, pulse))


func _draw_flag(base: Vector2, height: float, flag_width: float, flag_height: float, color: Color, trim: Color, phase: float) -> void:
	var top := base + Vector2(0.0, -height)
	draw_line(base, top, Color(0.32, 0.22, 0.16), 2.2, true)
	draw_circle(top, 2.3, trim)
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var segments := 7
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var wave := sin(_time * 5.2 - t * 4.2 + phase) * (1.0 + 3.2 * t)
		var y := top.y + 2.0 + wave
		upper.append(Vector2(top.x + 1.5 + t * flag_width, y))
		lower.append(Vector2(top.x + 1.5 + t * flag_width, y + flag_height * (1.0 - 0.38 * t)))
	var shape := PackedVector2Array()
	shape.append_array(upper)
	for i in range(lower.size() - 1, -1, -1):
		shape.append(lower[i])
	draw_colored_polygon(shape, color)
	draw_polyline(upper, trim, 1.3, true)
	draw_polyline(lower, Color(0.0, 0.0, 0.0, 0.25), 1.0, true)


func _ellipse(center: Vector2, radius: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, fill)


func _ring(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(33):
		var angle := TAU * float(i) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_polyline(points, color, width, true)
