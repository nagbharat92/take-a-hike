extends Camera2D

@export var target: Node2D
@export var world_bounds := Rect2(-160, -380, 1600, 1120)
@export_range(0.0, 0.5) var horizontal_dead_zone: float = 0.16
@export_range(0.0, 0.5) var vertical_dead_zone: float = 0.10
@export_range(0.0, 1.0) var body_screen_height: float = 0.60
@export var body_center_offset := Vector2(0, -20)
@export_range(0.01, 2.0) var horizontal_response: float = 0.25
@export_range(0.01, 2.0) var vertical_response: float = 0.35
@export_range(0.0, 0.25) var lookahead_fraction: float = 0.08
@export_range(0.0, 1.0) var turn_confirmation: float = 0.20
@export_range(0.01, 2.0) var lookahead_response: float = 0.40

var _last_target_position: Vector2
var _confirmed_direction: float = 0.0
var _pending_direction: float = 0.0
var _turn_time: float = 0.0
var _lookahead: float = 0.0
var overview_bounds: Rect2
var overview_enabled: bool = false
var close_scale: float = 2.2
var map_scale: float = 1.0
var transitioning: bool = false
var _transition_time: float = 0.0
var _transition_origin: Vector2
var _transition_zoom: Vector2
var _transition_destination: Vector2
var _transition_destination_zoom: Vector2
var _viewport_size := Vector2.ZERO
const TRANSITION_SECONDS: float = 0.72


func _ready() -> void:
	assert(target != null, "Camera requires a target")
	assert(world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0,
		"Camera world bounds must have positive size")
	target.connect("restarted", reframe)
	snap_to_target()


func _physics_process(delta: float) -> void:
	var size: Vector2 = get_viewport_rect().size
	if size != _viewport_size:
		_viewport_size = size
		reframe()
	var wanted_zoom: Vector2 = Vector2.ONE * (_overview_fit() * map_scale
		if overview_enabled else close_scale)
	if transitioning:
		_transition_time = minf(_transition_time + delta, TRANSITION_SECONDS)
		var weight: float = smoothstep(0, 1, _transition_time / TRANSITION_SECONDS)
		zoom = _transition_zoom.lerp(_transition_destination_zoom, weight)
		# Interpolate the displayed affine transform, not the world-space center.
		# Every stationary world point therefore follows a straight screen path.
		var screen_offset: Vector2 = (-_transition_origin * _transition_zoom).lerp(
			-_transition_destination * _transition_destination_zoom, weight)
		global_position = -screen_offset / zoom
		transitioning = _transition_time < TRANSITION_SECONDS
		_last_target_position = target.global_position
	elif overview_enabled:
		zoom = wanted_zoom
		global_position = _overview_center(zoom.x)
	else:
		zoom = wanted_zoom
		update_follow(delta)


func set_overview(enabled: bool) -> void:
	if enabled == overview_enabled:
		return
	overview_enabled = enabled
	_transition_origin = global_position
	_transition_zoom = zoom
	_transition_destination_zoom = Vector2.ONE * (
		_overview_fit() * map_scale if overview_enabled else close_scale)
	var visible_size: Vector2 = get_viewport_rect().size / _transition_destination_zoom
	_transition_destination = _overview_center(_transition_destination_zoom.x) if overview_enabled else \
		_bounded(_framed_target(visible_size), visible_size)
	_transition_time = 0
	transitioning = true
	_last_target_position = target.global_position
	_lookahead = 0
	_confirmed_direction = 0
	_pending_direction = 0
	_turn_time = 0


func reframe() -> void:
	snap_to_target()


func manual_zoom(steps: float) -> void:
	if overview_enabled:
		map_scale = clampf(map_scale * pow(1.16, steps), 0.65, 2.5)
	else:
		close_scale = clampf(close_scale * pow(1.16, steps), 1.25, 3.5)
	reframe()


func _overview_fit() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var available := Vector2(maxf(160, viewport_size.x - 380), maxf(100, viewport_size.y - 180))
	return minf(available.x / maxf(1, overview_bounds.size.x),
		available.y / maxf(1, overview_bounds.size.y))


func _overview_center(scale_value: float) -> Vector2:
	return overview_bounds.get_center() + Vector2(-170, 35) / scale_value


func _fit_overview() -> void:
	# Reserve the left third for controls, fitting the entire route in the rest.
	var fit: float = _overview_fit() * map_scale
	zoom = Vector2.ONE * fit
	global_position = _overview_center(fit)
	force_update_scroll()


func update_follow(delta: float) -> void:
	var visible_size: Vector2 = get_viewport_rect().size / zoom
	var movement: Vector2 = target.global_position - _last_target_position
	_last_target_position = target.global_position
	var direction: float = signf(movement.x) if absf(movement.x) > 0.01 else 0.0
	if direction != 0.0 and direction != _confirmed_direction:
		if direction != _pending_direction:
			_pending_direction = direction
			_turn_time = 0.0
		_turn_time += delta
		if _turn_time >= turn_confirmation:
			_confirmed_direction = direction
			_turn_time = 0.0
	else:
		_pending_direction = 0.0
		_turn_time = 0.0

	_lookahead = lerpf(_lookahead, _confirmed_direction * visible_size.x * lookahead_fraction,
		1.0 - exp(-delta / lookahead_response))
	var focus: Vector2 = _framed_target(visible_size) + Vector2(_lookahead, 0)
	var half_zone := visible_size * Vector2(horizontal_dead_zone, vertical_dead_zone) * 0.5
	var error: Vector2 = focus - global_position
	var excess := error - error.clamp(-half_zone, half_zone)
	# Independent exponential responses avoid frame-rate-dependent lerp and double smoothing.
	global_position += excess * Vector2(
		1.0 - exp(-delta / horizontal_response),
		1.0 - exp(-delta / vertical_response))
	global_position = _bounded(global_position, visible_size)


func snap_to_target() -> void:
	transitioning = false
	_viewport_size = get_viewport_rect().size
	_last_target_position = target.global_position
	_confirmed_direction = 0.0
	_pending_direction = 0.0
	_turn_time = 0.0
	_lookahead = 0.0
	if overview_enabled:
		_fit_overview()
		return
	zoom = Vector2.ONE * close_scale
	_last_target_position = target.global_position
	_confirmed_direction = 0.0
	_pending_direction = 0.0
	_turn_time = 0.0
	_lookahead = 0.0
	var visible_size: Vector2 = get_viewport_rect().size / zoom
	global_position = _bounded(_framed_target(visible_size), visible_size)
	force_update_scroll()


func _framed_target(visible_size: Vector2) -> Vector2:
	return target.global_position + body_center_offset \
		- Vector2(0, (body_screen_height - 0.5) * visible_size.y)


func _bounded(center: Vector2, visible_size: Vector2) -> Vector2:
	var half_view := visible_size * 0.5
	var result := world_bounds.get_center()
	if world_bounds.size.x >= visible_size.x:
		result.x = clampf(center.x, world_bounds.position.x + half_view.x,
			world_bounds.end.x - half_view.x)
	if world_bounds.size.y >= visible_size.y:
		result.y = clampf(center.y, world_bounds.position.y + half_view.y,
			world_bounds.end.y - half_view.y)
	return result
