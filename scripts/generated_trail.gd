extends Line2D

const GENERATOR_VERSION: int = 8
const WORLD_UNITS_PER_METER: float = 20.0
const MAX_SLOPE: float = 0.62486935 # tan(32 degrees).
const REST_LENGTH: float = 240.0
const CURVE_SPACING: float = 4.0
const JOIN_RADIUS: float = 48.0

enum Personality { GENTLE, STEADY, RUGGED }

@export var start_point := Vector2(1120, 500)
@export var shelf_color := Color(1.0, 0.77, 0.32)

class Climb:
	var title: String
	var span: float
	var rise: float
	var roughness: float
	var spacing: float
	var rest_center: float = 0.0
	var first_point: int
	var last_point: int
	var rest_points := PackedVector2Array()

var hike_seed: int
var personality: Personality
var climbs: Array[Climb] = []
var walking_distance: float
var uphill_travel: float
var downhill_travel: float
var steepest_slope: float
var resting_spots: int
var _shelf_lines: Array[Line2D] = []
var segment_kinds := PackedStringArray()
var stairs: Array[Dictionary] = []


func _ready() -> void:
	antialiased = true
	generate(randi())


func generate(new_seed: int) -> void:
	hike_seed = new_seed
	var recipe_rng := RandomNumberGenerator.new()
	recipe_rng.seed = hike_seed
	var shape_rng := RandomNumberGenerator.new()
	shape_rng.seed = hike_seed ^ 15485863
	climbs.clear()
	stairs.clear()
	segment_kinds.clear()
	var personalities: Array[Personality] = [
		Personality.GENTLE, Personality.STEADY, Personality.RUGGED]
	personality = personalities[recipe_rng.randi_range(0, personalities.size() - 1)]
	var count: int
	match personality:
		Personality.GENTLE:
			count = recipe_rng.randi_range(2, 3)
		Personality.STEADY:
			count = recipe_rng.randi_range(3, 4)
		Personality.RUGGED:
			count = recipe_rng.randi_range(4, 5)
	for index in range(count):
		climbs.append(_choose_climb(_choose_kind(recipe_rng), recipe_rng))

	var generated := PackedVector2Array()
	var origin := start_point
	var direction: float = -1.0
	for climb in climbs:
		climb.first_point = maxi(0, generated.size() - 1)
		var anchors := PackedVector2Array()
		_append_climb(anchors, origin, direction, climb, shape_rng)
		var rounded: PackedVector2Array = _round_walk(anchors)
		for index in range(0 if generated.is_empty() else 1, rounded.size()):
			generated.append(rounded[index])
		climb.last_point = generated.size() - 1
		while segment_kinds.size() < generated.size() - 1:
			segment_kinds.append("walk")
		var stair_start: int = generated.size() - 1
		var lower: PackedVector2Array = _landing(generated[-1], direction, false)
		_append_stair_points(generated, lower)
		var tread_first: int = generated.size() - 1
		var steps: Array[Vector2] = []
		var backs: Array[Vector2] = []
		for step in range(24):
			var foot: Vector2 = generated[-1]
			steps.append(foot)
			generated.append(foot + Vector2(direction * 2.0, -4.0))
			backs.append(generated[-1])
			segment_kinds.append("stairs")
			generated.append(generated[-1] + Vector2(0, -4.0))
			segment_kinds.append("stairs")
		var tread_last: int = generated.size() - 1
		var upper: PackedVector2Array = _landing(generated[-1], direction, true)
		_append_stair_points(generated, upper)
		stairs.append({"first": stair_start, "last": generated.size() - 1,
			"tread_first": tread_first, "tread_last": tread_last,
			"steps": steps, "backs": backs, "lower": lower, "upper": upper,
			"direction": direction})
		origin = generated[-1]
		direction *= -1.0
	# A quiet level approach makes arrival distinct from a switchback.
	generated.append(origin + Vector2(direction * 130.0, 0))
	segment_kinds.append("walk")
	points = generated
	_update_rest_lines()
	_measure_hike()
	visible = false


func _append_stair_points(generated: PackedVector2Array, landing: PackedVector2Array) -> void:
	for index in range(1, landing.size()):
		generated.append(landing[index])
		segment_kinds.append("stairs")


func _landing(origin: Vector2, direction: float, upper: bool) -> PackedVector2Array:
	var result := PackedVector2Array([origin])
	var a := origin + Vector2(direction * (6 if upper else 12), -12 if upper else 0)
	var b := origin + Vector2(direction * 14, -12 if upper else -4)
	var end := origin + Vector2(direction * (6 if upper else 18), -12)
	# Convex-hull-bounded controls: a level entry, then a small level hairpin exit.
	for index in range(1, 17):
		var t: float = index / 16.0
		result.append(origin.bezier_interpolate(a, b, end, t))
	return result


func _round_walk(anchors: PackedVector2Array) -> PackedVector2Array:
	var rounded := PackedVector2Array([anchors[0]])
	for index in range(1, anchors.size() - 1):
		var a: Vector2 = anchors[index - 1]
		var p: Vector2 = anchors[index]
		var b: Vector2 = anchors[index + 1]
		var incoming: Vector2 = p - a
		var outgoing: Vector2 = b - p
		var entry: Vector2 = p - incoming * minf(0.45, JOIN_RADIUS / incoming.length())
		var exit: Vector2 = p + outgoing * minf(0.45, JOIN_RADIUS / outgoing.length())
		rounded.append(entry)
		var samples: int = maxi(2, ceili((entry.distance_to(p) + p.distance_to(exit)) / CURVE_SPACING))
		# Quadratic corner cuts stay inside the original wedge; their derivatives
		# are convex combinations of the two already slope-bounded directions.
		for sample in range(1, samples + 1):
			var t: float = float(sample) / samples
			rounded.append(entry.lerp(p, t).lerp(p.lerp(exit, t), t))
	rounded.append(anchors[-1])
	return rounded


func personality_text() -> String:
	match personality:
		Personality.GENTLE:
			return "Gentle ramble"
		Personality.STEADY:
			return "Steady ascent"
		Personality.RUGGED:
			return "Rugged climb"
	assert(false, "Unknown hike personality")
	return ""


func _choose_kind(rng: RandomNumberGenerator) -> int:
	var choice: float = rng.randf()
	match personality:
		Personality.GENTLE:
			return 0 if choice < 0.8 else 2
		Personality.STEADY:
			return 0 if choice < 0.2 else (1 if choice < 0.8 else 2)
		Personality.RUGGED:
			return 1 if choice < 0.4 else 2
	assert(false, "Unknown hike personality")
	return -1


func _choose_climb(kind: int, rng: RandomNumberGenerator) -> Climb:
	var climb := Climb.new()
	var grade: float
	match kind:
		0:
			climb.title = "Gentle climb"
			climb.span = rng.randf_range(1400.0, 1800.0)
			grade = rng.randf_range(0.12, 0.18)
			climb.roughness = 8.0
			climb.spacing = 100.0
		1:
			climb.title = "Steeper climb"
			climb.span = rng.randf_range(900.0, 1250.0)
			grade = rng.randf_range(0.26, 0.32)
			climb.roughness = 12.0
			climb.spacing = 80.0
		2:
			climb.title = "Uneven traverse"
			climb.span = rng.randf_range(1200.0, 1600.0)
			grade = rng.randf_range(0.18, 0.24)
			climb.roughness = 24.0
			climb.spacing = 80.0
		_:
			assert(false, "Unknown climb type")
	match personality:
		Personality.GENTLE:
			grade *= 0.8
			climb.roughness *= 0.7
		Personality.RUGGED:
			grade *= 1.1
			climb.roughness *= 1.25
	if rng.randf() < 0.55:
		climb.rest_center = rng.randf_range(0.3, 0.7)
	climb.rise = climb.span * grade
	return climb


func _append_climb(generated: PackedVector2Array, origin: Vector2,
		direction: float, climb: Climb, rng: RandomNumberGenerator) -> void:
	if climb.rest_center == 0.0:
		_append_uphill(generated, origin, direction, climb.span, climb.rise, climb, rng)
		return
	var before: float = climb.span * climb.rest_center - REST_LENGTH * 0.5
	var after: float = climb.span - before - REST_LENGTH
	var before_rise: float = climb.rise * before / (before + after)
	_append_uphill(generated, origin, direction, before, before_rise, climb, rng)
	var rest_start: Vector2 = generated[-1]
	var rest_end := rest_start + Vector2(direction * REST_LENGTH, 0)
	generated.append(rest_end)
	climb.rest_points = PackedVector2Array([rest_start, rest_end])
	_append_uphill(generated, rest_end, direction, after, climb.rise - before_rise, climb, rng)


func _append_uphill(generated: PackedVector2Array, origin: Vector2,
		direction: float, span: float, rise: float, climb: Climb,
		rng: RandomNumberGenerator) -> void:
	assert(span > 0.0 and rise > 0.0 and rise / span < MAX_SLOPE,
		"Climb recipe must fit the slope limit")
	if generated.is_empty():
		generated.append(origin)
	# Reserve short level aprons without changing the profile's span or rise.
	var apron: float = minf(24.0, (span - rise / MAX_SLOPE) * 0.2)
	generated.append(origin + Vector2(direction * apron, 0))
	origin = generated[-1]
	span -= apron * 2
	var segments: int = maxi(2, ceili(span / climb.spacing))
	var endpoint := origin + Vector2(direction * span, -rise)
	for index in range(1, segments + 1):
		var progress: float = float(index) / segments
		var point := origin + Vector2(direction * span * progress, -rise * progress)
		if index < segments:
			var envelope: float = minf(climb.roughness, rise * minf(progress, 1.0 - progress) * 0.8)
			var previous: Vector2 = generated[-1]
			var step_limit: float = absf(point.x - previous.x) * MAX_SLOPE
			var remaining_limit: float = absf(endpoint.x - point.x) * MAX_SLOPE
			# Keep random bumps reachable from both the previous point and the fixed end.
			var lowest: float = maxf(point.y - envelope,
				maxf(previous.y - step_limit, endpoint.y - remaining_limit))
			var highest: float = minf(point.y + envelope,
				minf(previous.y + step_limit, endpoint.y + remaining_limit))
			assert(lowest <= highest + 0.001, "No valid terrain height for climb")
			point.y = clampf(point.y + rng.randf_range(-envelope, envelope), lowest, highest)
		else:
			point = endpoint
		generated.append(point)
	generated.append(endpoint + Vector2(direction * apron, 0))


func _update_rest_lines() -> void:
	resting_spots = 0
	for climb in climbs:
		if climb.rest_points.is_empty():
			continue
		if resting_spots == _shelf_lines.size():
			var line := Line2D.new()
			line.name = "RestSpot%d" % (resting_spots + 1)
			line.antialiased = true
			add_child(line)
			_shelf_lines.append(line)
		var line: Line2D = _shelf_lines[resting_spots]
		line.points = climb.rest_points
		line.width = width
		line.default_color = shelf_color
		line.visible = true
		resting_spots += 1
	for index in range(resting_spots, _shelf_lines.size()):
		_shelf_lines[index].visible = false


func _measure_hike() -> void:
	walking_distance = 0.0
	uphill_travel = 0.0
	downhill_travel = 0.0
	steepest_slope = 0.0
	for index in range(points.size() - 1):
		var step: Vector2 = points[index + 1] - points[index]
		walking_distance += step.length()
		uphill_travel += maxf(-step.y, 0.0)
		downhill_travel += maxf(step.y, 0.0)
		steepest_slope = maxf(steepest_slope, rad_to_deg(atan2(absf(step.y), absf(step.x))))


func specs_text() -> String:
	var summary := ("Length  %.2f km\nElevation gain  %.0f m\n"
		+ "%d %s  |  %d %s\n\n") % [
		walking_distance / WORLD_UNITS_PER_METER / 1000.0,
		uphill_travel / WORLD_UNITS_PER_METER,
		climbs.size() - 1, "switchback" if climbs.size() == 2 else "switchbacks",
		resting_spots, "resting spot" if resting_spots == 1 else "resting spots"]
	for index in range(climbs.size()):
		var climb: Climb = climbs[index]
		summary += "%d. %s%s\n" % [index + 1, climb.title,
			" + rest" if climb.rest_center > 0.0 else ""]
	return summary.strip_edges()


func identity_text() -> String:
	return "Hike #%d\nPrototype scale: 20 units = 1 m" % hike_seed
