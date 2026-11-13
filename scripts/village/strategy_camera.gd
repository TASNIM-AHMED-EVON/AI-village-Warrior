extends Camera2D
## Smooth RTS-style camera: WASD pan, middle-mouse drag, wheel zoom, R reset.

@export var pan_speed := 900.0
@export var smoothing := 10.0
@export var minimum_zoom := 0.42
@export var maximum_zoom := 1.7
@export var zoom_step := 0.12
@export var default_zoom := 0.88

var target_position := Vector2.ZERO
var _dragging := false
var _drag_anchor := Vector2.ZERO
var _default_position := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = false
	_default_position = position
	target_position = position
	zoom = Vector2.ONE * default_zoom


func _process(delta: float) -> void:
	var direction := Input.get_vector("camera_pan_left", "camera_pan_right", "camera_pan_up", "camera_pan_down")
	target_position += direction * pan_speed * delta / maxf(zoom.x, 0.1)
	position = position.lerp(target_position, 1.0 - exp(-smoothing * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_camera"):
		reset_view()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_anchor = event.position
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(zoom.x + zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(zoom.x - zoom_step)
	elif event is InputEventMouseMotion and _dragging:
		var mouse_motion := event as InputEventMouseMotion
		var drag_delta: Vector2 = mouse_motion.position - _drag_anchor
		_drag_anchor = mouse_motion.position
		target_position -= drag_delta / maxf(zoom.x, 0.1)


func set_home_position(home: Vector2) -> void:
	_default_position = home
	target_position = home
	position = home


func set_battle_view(home: Vector2) -> void:
	# Show the deployment perimeter and keep the camera's smoothing target in sync.
	default_zoom = 0.42
	minimum_zoom = 0.30
	maximum_zoom = 1.2
	set_home_position(home)
	zoom = Vector2.ONE * default_zoom


func reset_view() -> void:
	target_position = _default_position
	zoom = Vector2.ONE * default_zoom


func _set_zoom(next_zoom: float) -> void:
	var clamped := clampf(next_zoom, minimum_zoom, maximum_zoom)
	zoom = Vector2.ONE * clamped
