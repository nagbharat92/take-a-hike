extends Node2D

signal restarted

const WALK_SPEED: float = 180.0
const Art = preload("res://scripts/pixel_art.gd")
const Library = preload("res://scripts/asset_library.gd")
const GAIT_FRAMES: int = 16
const STRIDE: float = 40.0
const PIXEL_SCALE := Vector2(30.0 / 36.0, 51.0 / 60.0)
@export var trail: Line2D

var _segment: int = 0
var _distance: float = 0.0
var facing: float = -1.0
var moving: bool = false
var phase: float = 0.0
var elapsed: float = 0.0
var depth_walking: bool = false
var depth_facing: float = 1.0
var _frames: Dictionary = {}
var _gait_direction: float = 1.0
var _legs: ImageTexture
var _leg_pose: Array = []


func _ready() -> void:
	for mode in ["idle", "walk", "back", "front"]:
		var frames: Array[Texture2D] = []
		for frame in range(GAIT_FRAMES):
			frames.append(Library.hiker(frame / 2, mode))
		_frames[mode] = frames
	reset()


func route_points() -> PackedVector2Array:
	return trail.points


func kind(index: int) -> String:
	return trail.segment_kinds[index]


func _physics_process(delta: float) -> void:
	var horizontal: float = Input.get_axis("ui_left", "ui_right")
	horizontal += float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var depth: float = Input.get_axis("ui_down", "ui_up")
	depth += float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	advance(clampf(horizontal, -1, 1), delta, clampf(depth, -1, 1))


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _intent(index: int, horizontal: float, depth: float) -> float:
	if kind(index) == "stairs":
		return depth
	var points: PackedVector2Array = route_points()
	return horizontal * signf(points[index + 1].x - points[index].x)


func advance(horizontal: float, delta: float, depth: float = 0.0) -> void:
	var points: PackedVector2Array = route_points()
	var previous: Vector2 = global_position
	var length: float = points[_segment].distance_to(points[_segment + 1])
	if _distance >= length - 0.001 and _segment < points.size() - 2:
		if _intent(_segment + 1, horizontal, depth) > 0:
			_segment += 1
			_distance = 0
	elif _distance <= 0.001 and _segment > 0:
		if _intent(_segment - 1, horizontal, depth) < 0:
			_segment -= 1
			_distance = points[_segment].distance_to(points[_segment + 1])
	var intent: float = _intent(_segment, horizontal, depth)
	var remaining: float = absf(intent) * WALK_SPEED * delta
	var route_travel: float = 0
	var forward: bool = intent > 0
	while remaining > 0:
		length = points[_segment].distance_to(points[_segment + 1])
		var available: float = length - _distance if forward else _distance
		var travelled: float = minf(remaining, available)
		route_travel += travelled
		_distance += travelled if forward else -travelled
		remaining -= travelled
		if remaining <= 0.00001:
			break
		var next: int = _segment + (1 if forward else -1)
		if next < 0 or next >= points.size() - 1:
			break
		var next_intent: float = _intent(next, horizontal, depth)
		if (next_intent > 0) != forward or is_zero_approx(next_intent):
			break
		_segment = next
		_distance = 0 if forward else points[next].distance_to(points[next + 1])
	length = points[_segment].distance_to(points[_segment + 1])
	global_position = points[_segment].lerp(points[_segment + 1], _distance / length)
	depth_walking = kind(_segment) == "stairs"
	moving = global_position.distance_to(previous) > 0.001
	if moving:
		var direction: float = 1.0 if forward else -1.0
		if direction != _gait_direction:
			# Keep the same foot locations when pivoting into the return journey.
			phase += fposmod(PI - 2 * phase, TAU)
		_gait_direction = direction
		phase += route_travel * TAU / STRIDE
		if depth_walking and not is_zero_approx(depth):
			depth_facing = signf(depth)
		if absf(horizontal) > 0.01 and not depth_walking:
			facing = signf(horizontal)


func at_summit() -> bool:
	var points: PackedVector2Array = route_points()
	return _segment == points.size() - 2 \
		and _distance >= points[-2].distance_to(points[-1]) - 0.01


func reset() -> void:
	_segment = 0
	_distance = 0
	moving = false
	phase = 0
	_gait_direction = 1
	facing = -1
	advance(0, 0)
	restarted.emit()


func _route_position(offset: float) -> Vector2:
	var points: PackedVector2Array = route_points()
	var index: int = _segment
	var distance: float = _distance + offset
	while distance < 0 and index > 0:
		index -= 1
		distance += points[index].distance_to(points[index + 1])
	var length: float = points[index].distance_to(points[index + 1])
	while distance > length and index < points.size() - 2:
		distance -= length
		index += 1
		length = points[index].distance_to(points[index + 1])
	return points[index].lerp(points[index + 1], clampf(distance / length, 0, 1))


func foot_position(leg: int) -> Vector2:
	if not moving:
		return Vector2(-3 if leg == 0 else 3, 0)
	var t: float = fposmod(phase / TAU + leg * 0.5, 1.0)
	var offset: float
	var lift: float = 0
	if t < 0.5:
		# A stance lasts half a stride: its route anchor stays fixed as the body travels.
		offset = (0.25 - t) * STRIDE
	else:
		var swing: float = (t - 0.5) * 2
		offset = lerpf(-STRIDE * 0.25, STRIDE * 0.25, smoothstep(0, 1, swing))
		lift = sin(swing * PI) * (6 if depth_walking else 4)
	return _route_position(offset * _gait_direction) - global_position - Vector2(0, lift)


func _draw() -> void:
	draw_ellipse_shadow()
	if _frames.is_empty():
		return
	var mode: String = "walk" if moving else "idle"
	if depth_walking:
		mode = "back" if depth_facing > 0 else "front"
	var frame: int = int(floor(phase / TAU * GAIT_FRAMES)) % GAIT_FRAMES if moving else 0
	if not moving and not depth_walking:
		frame = int(elapsed * 4.0) % GAIT_FRAMES
	var feet: Array[Vector2] = []
	for leg in range(2):
		feet.append(Vector2(18, 58) + foot_position(leg) / PIXEL_SCALE)
	var toe_facing: float = facing
	if depth_walking:
		toe_facing = signf(_route_position(_gait_direction * 8).x - global_position.x)
	var pose: Array = [Vector2i(feet[0].round()), Vector2i(feet[1].round()), frame, toe_facing]
	if pose != _leg_pose:
		var image: Image = Art.hiker_legs(feet, frame, toe_facing)
		if _legs == null:
			_legs = ImageTexture.create_from_image(image)
		else:
			_legs.update(image)
		_leg_pose = pose
	draw_texture_rect(_legs, Rect2(Vector2(-36, -75) * PIXEL_SCALE,
		Vector2(72, 96) * PIXEL_SCALE), false)
	draw_set_transform(Vector2.ZERO, 0, Vector2(facing if not depth_walking else 1.0, 1))
	draw_texture_rect(_frames[mode][frame], Rect2(-15, -50.15, 30, 51), false)


func draw_ellipse_shadow() -> void:
	for leg in range(2):
		if moving and fposmod(phase / TAU + leg * 0.5, 1.0) >= 0.5:
			continue
		var p: Vector2 = foot_position(leg)
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-3, 0), p + Vector2(3, -1), p + Vector2(12, 2),
			p + Vector2(8, 3), p + Vector2(-3, 1)]), Color(0.035, 0.09, 0.10, 0.16))
		draw_rect(Rect2(p + Vector2(-4, 0), Vector2(8, 1)),
			Color(0.025, 0.07, 0.07, 0.45))
