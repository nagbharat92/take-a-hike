extends Node2D

const Art = preload("res://scripts/pixel_art.gd")
const Library = preload("res://scripts/asset_library.gd")
const Placement = preload("res://scripts/vegetation_placement.gd")
const HikeScatter = preload("res://scripts/hike_scatter.gd")
var scatter = HikeScatter.new()
var placement = Placement.new()
var vegetation: Array[Dictionary] = []
var distant_trees: Array[Dictionary] = []
var shadow_cache: Dictionary = {}
var distant_canvas: Node2D
var trees: Array[Dictionary] = []
var tree_meshes: Array[ArrayMesh] = []
var stones: Array[Dictionary] = []
var reeds: Array[Dictionary] = []
var mountain := PackedVector2Array()
var pine_frames: Array = []
var rock_textures: Array[Texture2D] = []
var fern_frames: Array = []
var cliff_texture: Texture2D
var distant_cliff: Texture2D
var treads: Array[Texture2D] = []
var wind_clock: float = 0.0
var clearings: Array[Dictionary] = []
var stair_banks: Array[PackedVector2Array] = []
var terminal_surfaces: Dictionary = {}
var mountain_floor: float
var ledges: Array[Dictionary] = []
var rock_canvases: Array[Node2D] = []
var foreground_trees: Array[Dictionary] = []
var grove_floors: Array[PackedVector2Array] = []
var forest_stretches: Array[Dictionary] = []
var grass_frames: Array = []
var grasses: Array[Dictionary] = []
var tree_rejections: Dictionary = {}
var regeneration_timings: Dictionary = {}
var route_index: Dictionary = {}
@onready var trail = $"../Trail"

func _ready() -> void:
	scatter.attach(self)
	Library.prepare()
	pine_frames = Library.tree_frames
	for variant in range(4):
		var ferns: Array[Texture2D] = []
		var grass: Array[Texture2D] = []
		for wind in [-1, 0, 1]:
			ferns.append(Art.fern(variant, wind))
			grass.append(Art.grass(variant, wind))
		fern_frames.append(ferns)
		grass_frames.append(grass)
		rock_textures.append(Art.rock(variant))
		treads.append(Art.tread(variant))
	cliff_texture = Art.cliff()
	distant_cliff = Art.cliff(true)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(delta: float) -> void:
	wind_clock += delta
	queue_redraw()
	if is_instance_valid(distant_canvas):
		distant_canvas.queue_redraw()


func rebuild() -> void:
	var stage: int = Time.get_ticks_usec()
	trees.clear()
	tree_meshes.clear()
	stones.clear()
	reeds.clear()
	mountain.clear()
	clearings.clear()
	stair_banks.clear()
	terminal_surfaces.clear()
	ledges.clear()
	foreground_trees.clear()
	grove_floors.clear()
	forest_stretches.clear()
	grasses.clear()
	vegetation.clear()
	distant_trees.clear()
	shadow_cache.clear()
	tree_rejections.clear()
	placement = Placement.new()
	placement.configure(trail.hike_seed)
	scatter.generated_candidates = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = trail.hike_seed ^ 982451653
	route_index = Placement.index_segments(trail.points)
	_build_clearing(trail.points[0], 1, false)
	var summit_direction: float = signf(trail.points[-1].x - trail.points[-2].x)
	_build_clearing(trail.points[-1], summit_direction, true)
	for stair in trail.stairs:
		stair_banks.append(_stair_outline(stair))
		for upper in [false, true]:
			terminal_surfaces[stair.first * 2 + int(upper)] = _build_terminal_surface(stair, upper)
	regeneration_timings["surface_rasters_ms"] = (Time.get_ticks_usec() - stage) / 1000.0
	stage = Time.get_ticks_usec()
	_build_mountain()
	for index in range(stair_banks.size()):
		var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(stair_banks[index], mountain)
		if not clipped.is_empty():
			stair_banks[index] = clipped[0]
	for climb_index in range(trail.climbs.size()):
		var climb = trail.climbs[climb_index]
		var ledge: Dictionary = _build_ledge(climb)
		ledges.append(ledge)
		ledge["support"] = placement.add_surface(ledge.surface, "ribbon", ledge.route)
	for clearing in clearings:
		clearing["support"] = placement.add_surface(clearing.surface, "clearing", clearing.route)
	for terminal in terminal_surfaces.values():
		terminal["support"] = placement.add_surface(terminal.polygon, "stone", PackedVector2Array())
	regeneration_timings["terrain_ms"] = (Time.get_ticks_usec() - stage) / 1000.0
	stage = Time.get_ticks_usec()
	for climb_index in range(trail.climbs.size()):
		var climb = trail.climbs[climb_index]
		var ledge: Dictionary = ledges[climb_index]
		_compose_forest(ledge, climb, climb_index, rng)
	_compose_clearings(rng)
	regeneration_timings["vegetation_ms"] = (Time.get_ticks_usec() - stage) / 1000.0
	stage = Time.get_ticks_usec()
	_compose_distant_ridge(rng)
	regeneration_timings["distant_ms"] = (Time.get_ticks_usec() - stage) / 1000.0
	stage = Time.get_ticks_usec()
	trees.sort_custom(func(a: Dictionary, b: Dictionary): return a.p.y < b.p.y)
	for canvas in rock_canvases:
		canvas.free()
	rock_canvases.clear()
	_cache_rock(mountain, true)
	distant_canvas = Node2D.new()
	distant_canvas.show_behind_parent = true
	distant_canvas.draw.connect(_draw_distant.bind(distant_canvas))
	add_child(distant_canvas)
	rock_canvases.append(distant_canvas)
	for bank in stair_banks:
		_cache_rock(bank)
	for ledge in ledges:
		_cache_rock(ledge.cliff, false, ledge.planes)
	for ledge in ledges:
		var canvas := Node2D.new()
		canvas.show_behind_parent = true
		canvas.draw.connect(_draw_ledge.bind(ledge, canvas))
		add_child(canvas)
		rock_canvases.append(canvas)
	queue_redraw()
	regeneration_timings["render_cache_ms"] = (Time.get_ticks_usec() - stage) / 1000.0


func _is_rest(climb, point: Vector2, margin: float = 0) -> bool:
	return not climb.rest_points.is_empty() and point.x >= minf(
		climb.rest_points[0].x, climb.rest_points[1].x) - margin and point.x <= maxf(
		climb.rest_points[0].x, climb.rest_points[1].x) + margin


func _compose_forest(ledge: Dictionary, climb, climb_index: int,
		rng: RandomNumberGenerator) -> void:
	var patches: Array[Dictionary] = placement.seed_patches(ledge.length, rng, trail.personality)
	var exclusions: Array[Vector2] = []
	if not climb.rest_points.is_empty():
		var first: float = _ledge_distance(ledge, climb.rest_points[0])
		var last: float = _ledge_distance(ledge, climb.rest_points[1])
		exclusions.append(Vector2(minf(first, last) - 45, maxf(first, last) + 45))
	for patch in patches:
		var member: int = 0
		var distances: PackedFloat32Array = scatter.grove(patch.start + 28, patch.end - 20,
			rng.randf_range(25, 32), trail.hike_seed ^ (climb_index * 104729 + int(patch.start)),
			exclusions)
		for distance_in_patch in distances:
			var at: Vector2 = _ledge_point(ledge, distance_in_patch)
			if not _is_rest(climb, at, 45):
				var height: float = rng.randf_range(255, 280) if member % 2 == 0 else rng.randf_range(320, 400)
				var variant: int = 0 if member % 2 == 0 or rng.randf() < 0.75 else 1
				# Both are mature imported silhouettes. A narrower physical trunk
				# may fit the rear shoulder; never shrink height or use the lane.
				for candidate in ([1, 0] if variant == 1 else [0]):
					var root_half: Vector2 = Library.tree_footprint(height, candidate)
					var gradient: float = placement.gradient_at(ledge.support, at.x, root_half.x)
					var root: Vector2 = placement.shoulder_roots(ledge.support, at.x, root_half,
						Library.tree_root_offset(height, candidate), Placement.TREE_ROOT_MARGIN, gradient)[0]
					if _add_tree(root, height, candidate, ledge.support, rng):
						trees[-1]["climb"] = climb_index
						trees[-1]["patch_start"] = patch.start
						break
			member += 1
	var distance: float = 55
	while distance < ledge.length - 65:
		var weight: float = 0
		var kind: int = 2
		for patch in patches:
			var influence: float = placement.patch_weight(distance, patch)
			if influence > weight:
				weight = influence
				kind = patch.kind
		var point: Vector2 = _ledge_point(ledge, distance)
		var resting: bool = _is_rest(climb, point, 42)
		forest_stretches.append({"p": point, "kind": kind, "rest": resting,
			"distance": distance, "climb": climb_index, "weight": weight})
		if weight > 0.08 and not resting:
			var slope: float = placement.slope_at(ledge.support, point.x)
			# Low cover fills the same groves without replacing mature silhouettes.
			for side in [-1, 1]:
				var root: Vector2 = (point + Vector2(rng.randf_range(-3, 3),
					-6 if side < 0 else 12)).round()
				if slope < 0.27 and kind == 0:
					_add_low("fern", root, ledge.support, 0.28 + weight * 0.20, rng)
				elif slope < 0.38:
					_add_low("grass", root, ledge.support, 0.3 + weight * 0.18, rng)
				else:
					_add_low("moss", root, ledge.support, 0.5, rng)
		distance += rng.randf_range(14, 22)


func _boot_clear(root: Vector2, radius: float) -> bool:
	if not _stairs_clear(root, radius):
		return false
	for index in Placement.segments_in(route_index, root.x - 5 - radius, root.x + 5 + radius):
		if Geometry2D.get_closest_point_to_segment(root, trail.points[index],
				trail.points[index + 1]).distance_to(root) < 5 + radius:
			return false
	return true


func _stairs_clear(root: Vector2, radius: float) -> bool:
	for stair in trail.stairs:
		if Rect2(stair.lower[0], Vector2.ZERO).expand(stair.upper[-1]).grow(48 + radius).has_point(root):
			return false
	return true


func _add_low(kind: String, root: Vector2, support: int, scale_value: float,
		rng: RandomNumberGenerator) -> void:
	var half := Vector2(2, 1) if kind == "fern" else Vector2(12 * scale_value, 1)
	if not placement.supported(support, root, half) or not _boot_clear(root, half.y):
		return
	var plant := {"p": root, "support": support, "half": half, "kind": kind,
		"scale": scale_value, "variant": rng.randi_range(0, 3), "phase": rng.randf_range(0, TAU)}
	vegetation.append(plant)
	if kind == "fern":
		reeds.append(plant)
	else:
		grasses.append(plant)


func _add_tree(root: Vector2, height: float, variant: int, support: int,
		rng: RandomNumberGenerator, near: bool = false) -> bool:
	var half: Vector2 = Library.tree_footprint(height, variant)
	var root_offset: Vector2 = Library.tree_root_offset(height, variant)
	# Canopies may overhang a slope. Only the measured physical roots need soil.
	var reserve: Vector2 = half
	var margin: float = Placement.TREE_ROOT_MARGIN
	var gradient: float = placement.gradient_at(support, root.x, half.x)
	if not Placement.tree_site_allowed(placement.surfaces[support].kind,
			placement.slope_at(support, root.x, reserve.x), height):
		tree_rejections["slope"] = tree_rejections.get("slope", 0) + 1
		return false
	if not placement.tree_footprint_clear(support, root + root_offset, half, margin, gradient):
		tree_rejections["walking_lane"] = tree_rejections.get("walking_lane", 0) + 1
		return false
	if not placement.supported(support, root + root_offset, reserve, margin, gradient):
		tree_rejections["support"] = tree_rejections.get("support", 0) + 1
		return false
	if not _stairs_clear(root, half.y):
		tree_rejections["corridor"] = tree_rejections.get("corridor", 0) + 1
		return false
	for tree in trees + foreground_trees:
		if tree.p.distance_to(root) < 23:
			tree_rejections["spacing"] = tree_rejections.get("spacing", 0) + 1
			return false
	if _tree_clearance(root, height, variant) < height:
		tree_rejections["canopy"] = tree_rejections.get("canopy", 0) + 1
		return false
	var frame: Rect2 = Library.tree_rect(root, height, variant)
	var plant := {"p": root, "height": height, "width": frame.size.x * 0.5,
		"layer": 0, "variant": variant, "phase": rng.randf_range(0, TAU),
		"support": support, "half": half, "root_offset": root_offset, "reserve": reserve,
		"margin": margin, "kind": "tree", "near": near, "root_gradient": gradient,
		"mesh_index": tree_meshes.size()}
	tree_meshes.append(Library.tree_mesh(root, height, variant, gradient))
	vegetation.append(plant)
	if near:
		foreground_trees.append(plant)
	else:
		trees.append(plant)
	return true


func _compose_clearings(rng: RandomNumberGenerator) -> void:
	for clearing in clearings:
		var support: int = clearing.support
		# Reserve near framing first so edge saplings do not crowd its root footprint.
		var near_x: float = roundf(clearing.p.x + clearing.direction * (208 if not clearing.summit else 135))
		var near_height: float = rng.randf_range(300, 390)
		var near_half: Vector2 = Library.tree_footprint(near_height, 0)
		var near_roots: PackedVector2Array = placement.shoulder_roots(support, near_x, near_half,
			Library.tree_root_offset(near_height, 0), Placement.TREE_ROOT_MARGIN,
			placement.gradient_at(support, near_x, near_half.x))
		_add_tree(near_roots[1], near_height, 0, support, rng, true)
		# One sheltered grove, an open boot/log corridor, then a small edge sapling.
		var offsets: Array = [68, 104, 146, 181, 208] if not clearing.summit else [51, 91, 126]
		for index in range(offsets.size()):
			var x: float = roundf(clearing.p.x + clearing.direction * (offsets[index] + rng.randf_range(-5, 5)))
			var variant: int = rng.randi_range(0, 1) if index in [1, 2] else rng.randi_range(2, 4)
			var height: float = rng.randf_range(300, 420) if variant < 2 else rng.randf_range(75, 125)
			var half: Vector2 = Library.tree_footprint(height, variant)
			var roots: PackedVector2Array = placement.shoulder_roots(support, x, half,
				Library.tree_root_offset(height, variant), Placement.TREE_ROOT_MARGIN,
				placement.gradient_at(support, x, half.x))
			var root: Vector2 = roots[0]
			_add_tree(root, height, variant, support, rng)
			for member in range(3):
				var at := Vector2(x + rng.randf_range(-14, 14), root.y + rng.randf_range(-3, 4)).round()
				_add_low("fern", at, support, rng.randf_range(0.35, 0.55), rng)


func _compose_distant_ridge(rng: RandomNumberGenerator) -> void:
	# Distant silhouettes root into the existing mountain envelope, not fake ledge soil.
	var support: int = placement.add_surface(mountain, "distant_ridge", PackedVector2Array())
	var bounds: Rect2 = placement.surfaces[support].bounds
	var left: float = INF
	var right: float = -INF
	for point in trail.points:
		left = minf(left, point.x)
		right = maxf(right, point.x)
	for patch in placement.seed_patches(right - left, rng, trail.personality):
		var x: float = left + patch.start
		while x < left + patch.end:
			var weight: float = placement.patch_weight(x - left, patch)
			var span: Vector2 = placement.span_at_x(support, x)
			var slope: float = placement.slope_at(support, x)
			if weight > 0.15 and slope < 0.45 and bounds.has_point(Vector2(x, span.x + 8)):
				var root := Vector2(roundf(x), roundf(span.x + 8))
				var variant: int = 0 if weight > 0.7 else 3
				var height: float = lerpf(160, rng.randf_range(260, 360), weight)
				var half: Vector2 = Library.tree_footprint(height, variant)
				if placement.supported(support, root, half, 1) and _boot_clear(root, 4) and \
						_tree_clearance(root, height, variant) >= height:
					distant_trees.append({"p": root, "height": height, "width": height * 0.2,
						"variant": variant, "layer": 2, "support": support, "half": half})
			x += rng.randf_range(24, 36)


func _surface_chips_on(canvas: Node2D, polygon: PackedVector2Array) -> void:
	var bounds: Rect2 = _polygon_bounds(polygon)
	for x in range(floori(bounds.position.x), ceili(bounds.end.x), 17):
		for y in range(floori(bounds.position.y), ceili(bounds.end.y), 11):
			var point := Vector2(x + posmod(y, 7), y)
			if Geometry2D.is_point_in_polygon(point, polygon):
				canvas.draw_rect(Rect2(point, Vector2(7, 2)), Color("#4b694d"))


func _tree_clearance(root: Vector2, desired: float, variant: int = -1) -> float:
	var height: float = desired
	var frame: Rect2 = Library.tree_rect(root, desired, variant) if variant >= 0 else \
		Rect2(root - Vector2(desired * 0.18, desired), Vector2(desired * 0.36, desired))
	for i in Placement.segments_in(route_index, frame.position.x, frame.end.x):
		var a: Vector2 = trail.points[i]
		var b: Vector2 = trail.points[i + 1]
		if maxf(a.y, b.y) >= root.y - 45:
			continue
		if frame.end.x < minf(a.x, b.x) or frame.position.x > maxf(a.x, b.x):
			continue
		height = minf(height, root.y - maxf(a.y, b.y) - 55)
	return height


func _draw_distant(canvas: Node2D) -> void:
	var camera: Camera2D = $"../Camera2D"
	var size: Vector2 = get_viewport_rect().size / camera.zoom
	var view := Rect2(camera.get_screen_center_position() - size * 0.5, size).grow(8)
	# The foreground terrain lip occludes distant bases, not the other way around.
	for tree in distant_trees:
		var frame: Rect2 = Library.tree_rect(tree.p, tree.height, tree.variant)
		if view.intersects(frame):
			var wind: int = 1 + roundi(sin(wind_clock * 1.4 + tree.p.x * 0.013))
			canvas.draw_texture_rect(pine_frames[tree.variant][wind], frame, false, Color("#718f83"))


func _draw() -> void:
	var camera: Camera2D = $"../Camera2D"
	var size: Vector2 = get_viewport_rect().size / camera.zoom
	var view := Rect2(camera.get_screen_center_position() - size * 0.5, size).grow(8)
	var end: Vector2 = trail.points[-1]
	for clearing in clearings:
		if view.intersects(_polygon_bounds(clearing.surface).grow(145)):
			_draw_clearing(clearing)
	for tree in foreground_trees:
		if not camera.overview_enabled and view.has_point(tree.p):
			_contact_shadow(tree.p + Vector2(2, 2 * tree.root_gradient),
				tree.half.x + 2, 1.5, 0.12, tree.support, tree.root_gradient)
	for tree in trees:
		if view.intersects(Rect2(tree.p - Vector2(tree.width, tree.height),
				Vector2(tree.width * 2, tree.height))):
			_pine(tree)
	for stair in trail.stairs:
		if view.intersects(Rect2(stair.lower[0], Vector2.ZERO).expand(stair.upper[-1]).grow(95)):
			_draw_stair(stair)
	for stone in stones:
		if view.grow(30).has_point(stone.p):
			_rock(stone.p, stone.size)
	for reed in reeds:
		if view.grow(30).has_point(reed.p):
			_fern(reed.p, reed.scale, reed.support)
	for grass in grasses:
		if view.grow(18).has_point(grass.p):
			var wind: int = 1 + roundi(sin(wind_clock * 1.65 + grass.phase))
			if grass.kind == "moss":
				draw_rect(Rect2(grass.p - Vector2(3, 1), Vector2(6, 2)), Color("#587653"))
			else:
				draw_texture_rect(grass_frames[grass.variant][wind],
					Rect2(grass.p - Vector2(14, 15) * grass.scale, Vector2(28, 16) * grass.scale), false)
	for climb in trail.climbs:
		if not climb.rest_points.is_empty():
			var point: Vector2 = (climb.rest_points[0] + climb.rest_points[1]) * 0.5
			if view.grow(30).has_point(point):
				_draw_bench(point)
	_rock(end + Vector2(16, 0), 20)
	_rock(end + Vector2(16, -10), 15)
	_rock(end + Vector2(16, -19), 10)
	_rock(end + Vector2(16, -26), 6)
	draw_line(end + Vector2(37, -3), end + Vector2(37, -70), Color("#a5a785"), 2)
	_draw_sign(trail.points[0] + Vector2(68, -6))
	_draw_trailhead(trail.points[0])


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	return bounds


func _build_ledge(climb) -> Dictionary:
	var route := PackedVector2Array()
	for index in range(climb.first_point, climb.last_point + 1):
		route.append(trail.points[index])
	var surface := PackedVector2Array()
	for p in route:
		surface.append(p + Vector2(0, -9))
	for index in range(route.size() - 1, -1, -1):
		surface.append(route[index] + Vector2(0, 15))
	var cliff := PackedVector2Array()
	for p in route:
		cliff.append(p + Vector2(0, 15))
	var distances := PackedFloat32Array([0.0])
	for index in range(1, route.size()):
		distances.append(distances[-1] + route[index - 1].distance_to(route[index]))
	for index in range(route.size() - 1, -1, -1):
		var distance: float = distances[index]
		var depth: float = 148 + sin(distance * 0.012 + climb.first_point) * 39
		depth += sin(distance * 0.027) * 17
		# Stepped basal shelves widen the mass instead of tracing a parallel ribbon.
		depth = roundf(depth / 12) * 12
		cliff.append((route[index] + Vector2(0, depth)).round())
	var planes: Array[PackedVector2Array] = []
	var formation_distance: float = 80
	while formation_distance < distances[-1] - 40:
		var p: Vector2 = _ledge_point({"route": route, "distances": distances},
			formation_distance) + Vector2(-55, 32)
		var plane := PackedVector2Array([
			p, p + Vector2(111, -8), p + Vector2(143, 17),
			p + Vector2(122, 62), p + Vector2(77, 70),
			p + Vector2(63, 93), p + Vector2(7, 85), p + Vector2(-13, 44)])
		for clipped in Geometry2D.intersect_polygons(plane, cliff):
			planes.append(clipped)
		formation_distance += 185 + sin(formation_distance) * 37
	return {"route": route, "surface": surface, "cliff": cliff,
		"distances": distances, "length": distances[-1], "planes": planes}


func _ledge_point(ledge: Dictionary, distance: float) -> Vector2:
	var distances: PackedFloat32Array = ledge.distances
	for index in range(1, distances.size()):
		if distance <= distances[index]:
			return ledge.route[index - 1].lerp(ledge.route[index],
				clampf((distance - distances[index - 1]) /
				(distances[index] - distances[index - 1]), 0, 1))
	return ledge.route[-1]


func _ledge_distance(ledge: Dictionary, point: Vector2) -> float:
	var nearest: float = INF
	var distance: float = 0
	for index in range(ledge.route.size() - 1):
		var at := Geometry2D.get_closest_point_to_segment(point, ledge.route[index], ledge.route[index + 1])
		if at.distance_squared_to(point) < nearest:
			nearest = at.distance_squared_to(point)
			distance = ledge.distances[index] + ledge.route[index].distance_to(at)
	return distance


func _draw_ledge(ledge: Dictionary, canvas: Node2D) -> void:
	var route: PackedVector2Array = ledge.route
	canvas.draw_colored_polygon(ledge.surface, Color("#66755c"))
	canvas.draw_polyline(route, Color("#b0ad86"), 3, false)
	var back := PackedVector2Array()
	for p in route:
		back.append(p + Vector2(0, -8))
	canvas.draw_polyline(back, Color("#7d8b64"), 2)
	var next_sample: float = 0
	var travelled: float = 0
	var sample: int = 0
	for index in range(route.size() - 1):
		var p: Vector2 = route[index]
		var q: Vector2 = route[index + 1]
		var length: float = p.distance_to(q)
		while next_sample < travelled + length:
			var t: float = (next_sample - travelled) / length
			var at: Vector2 = p.lerp(q, t).round()
			var offset: int = (sample * 7) % 9 - 4
			canvas.draw_rect(Rect2(at + Vector2(0, offset), Vector2(3 + sample % 2, 2)),
				Color("#9ca58b") if sample % 3 else Color("#85987b"))
			if sample % 4 == 0:
				canvas.draw_rect(Rect2(at + Vector2(2, -6), Vector2(8, 2)), Color("#4d7151"))
			if sample % 3 == 0:
				canvas.draw_rect(Rect2(at + Vector2(-3, 13), Vector2(7, 1)), Color("#a6ae95"))
			next_sample += 26
			sample += 1
		travelled += length


func _stair_outline(stair: Dictionary) -> PackedVector2Array:
	var top: Vector2 = stair.upper[-1]
	var foot: Vector2 = stair.lower[-1]
	# A buttress continues down into the mountain, never a suspended landing disk.
	return PackedVector2Array([
		top + Vector2(-51, 4), top + Vector2(47, 5),
		foot + Vector2(63, 25), foot + Vector2(73, 78),
		foot + Vector2(98, 92), foot + Vector2(90, 156),
		foot + Vector2(66, 181), foot + Vector2(22, 184),
		foot + Vector2(10, 205), foot + Vector2(-57, 198),
		foot + Vector2(-88, 166), foot + Vector2(-81, 97),
		foot + Vector2(-60, 76), foot + Vector2(-53, 22)])


func _cache_rock(polygon: PackedVector2Array, distant: bool = false,
		planes: Array[PackedVector2Array] = []) -> void:
	var canvas := Node2D.new()
	canvas.show_behind_parent = true
	canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var uv := PackedVector2Array()
	for point in polygon:
		uv.append(point / (768.0 if distant else 384.0))
	var texture: Texture2D = distant_cliff if distant else cliff_texture
	canvas.draw.connect(func():
		canvas.draw_polygon(polygon, PackedColorArray([Color.WHITE]), uv, texture)
		for plane in planes:
			canvas.draw_colored_polygon(plane, Color(0.10, 0.19, 0.17, 0.10)))
	add_child(canvas)
	rock_canvases.append(canvas)


func _terminal_sections(stair: Dictionary, upper: bool) -> Array[PackedVector2Array]:
	var d: float = stair.direction
	var route: PackedVector2Array = stair.upper if upper else stair.lower
	var root: Vector2 = route[0] if upper else route[-1]
	var mouth: Vector2 = _terminal_mouth(stair, upper)
	var outer: Vector2 = root + Vector2(d * 31, 2)
	var inner: Vector2 = root + Vector2(-d * 31, 2)
	var far: Vector2 = mouth + Vector2(0, -9)
	var near: Vector2 = mouth + Vector2(0, 15)
	# Sweep the two edges separately: a normal-offset ribbon folds at this tight turn.
	var a: Vector2 = outer if upper else near
	var b: Vector2 = inner if upper else far
	var c: Vector2 = far if upper else outer
	var e: Vector2 = near if upper else inner
	var outer_corner := Vector2(outer.x, far.y if upper else near.y)
	var inner_corner: Vector2 = inner.lerp(near, 0.5) if upper else Vector2(inner.x, far.y)
	var sections: Array[PackedVector2Array] = []
	for index in range(5):
		var t: float = index / 4.0
		sections.append(PackedVector2Array([
			a.lerp(outer_corner, t).lerp(outer_corner.lerp(c, t), t),
			b.lerp(inner_corner, t).lerp(inner_corner.lerp(e, t), t)]))
	return sections


func _terminal_mouth(stair: Dictionary, upper: bool) -> Vector2:
	var index: int = stair.last if upper else stair.first
	var stride: int = 1 if upper else -1
	var remaining: float = 64 if upper else 48
	while index + stride >= 0 and index + stride < trail.points.size():
		var a: Vector2 = trail.points[index]
		var b: Vector2 = trail.points[index + stride]
		var length: float = a.distance_to(b)
		if length >= remaining:
			return a.lerp(b, remaining / length)
		remaining -= length
		index += stride
	return trail.points[index]


func _draw_terminal_treads(stair: Dictionary, upper: bool) -> void:
	var surface: Dictionary = terminal_surfaces[stair.first * 2 + int(upper)]
	# The face and buttress sample the same world-space rock as the adjoining ledge.
	var front: PackedVector2Array = surface.front
	var face: PackedVector2Array = front.duplicate()
	for index in range(front.size() - 1, -1, -1):
		face.append(front[index] + Vector2(0, 112))
	for clipped in Geometry2D.intersect_polygons(face, mountain):
		_textured_cliff(clipped, Color.WHITE)
	draw_texture(surface.texture, surface.origin)
	var sections: Array[PackedVector2Array] = surface.sections
	for index in range(1, 4):
		var a: Vector2 = sections[index][0]
		var b: Vector2 = sections[index][1]
		# Worn joints stop short of the soil and outside edge, not bright fan spokes.
		for interval in [Vector2(0.16, 0.39), Vector2(0.48, 0.76)]:
			draw_line(a.lerp(b, interval.x).round(), a.lerp(b, interval.y).round(),
				Color("#71816e"), 1)


func _build_terminal_surface(stair: Dictionary, upper: bool) -> Dictionary:
	var sections: Array[PackedVector2Array] = _terminal_sections(stair, upper)
	var polygon := PackedVector2Array()
	var front := PackedVector2Array()
	for section in sections:
		polygon.append(section[0])
		front.append(section[1] if upper else section[0])
	for index in range(sections.size() - 1, -1, -1):
		polygon.append(sections[index][1])
	var bounds: Rect2 = _polygon_bounds(polygon)
	var origin: Vector2 = bounds.position.floor()
	var size: Vector2i = Vector2i(bounds.end.ceil() - origin) + Vector2i.ONE
	var route: PackedVector2Array = stair.upper if upper else stair.lower
	var mouth: Vector2 = (sections[-1][0] + sections[-1][1]) * 0.5 if upper else (
		(sections[0][0] + sections[0][1]) * 0.5)
	return {"sections": sections, "front": front, "polygon": polygon, "origin": origin,
		"texture": Art.terminal_surface(size, origin, polygon, mouth,
			route[0] if upper else route[-1], stair.direction)}


func _draw_stair(stair: Dictionary) -> void:
	var steps: Array = stair.steps
	_draw_terminal_treads(stair, true)
	_draw_terminal_treads(stair, false)
	# Draw far-to-near: each tread and riser shares the traversal's endpoints.
	for index in range(steps.size() - 1, -1, -1):
		var p: Vector2 = steps[index]
		var back: Vector2 = stair.backs[index]
		var half := Vector2(31, 0)
		draw_colored_polygon(PackedVector2Array([
			p - half + Vector2(0, 2), p + half + Vector2(0, 2),
			p + half + Vector2(0, 5 if index == 0 else 9),
			p - half + Vector2(0, 5 if index == 0 else 9)]),
			Color("#566a59") if index == 0 else Color("#3f514b"))
		var tread := PackedVector2Array([
			p - half + Vector2(0, 2), p + half + Vector2(0, 2),
			back + half + Vector2(0, -2), back - half + Vector2(0, -2)])
		draw_polygon(tread, PackedColorArray([Color.WHITE]),
			PackedVector2Array([Vector2(0, 0.84), Vector2(1, 0.84),
				Vector2(1, 0), Vector2(0, 0)]), treads[index % 4])
		draw_line(p + Vector2(-29, 2), p + Vector2(-10 + index % 5, 2),
			Color("#a6ae95"), 1)
		draw_line(p + Vector2(3 + index % 7, 2), p + Vector2(26, 2),
			Color("#a6ae95"), 1)
		draw_line(p + Vector2(11, 2), back + Vector2(9, -2), Color("#687c68"), 1)
		draw_line(p + Vector2(-27, 3), p + Vector2(-18, 3), Color("#526e58"), 2)
		draw_line(p + Vector2(18, 6), p + Vector2(24, 6), Color("#293f40"), 1)
		_rock(p + Vector2(-37, 2), 7)
		if index % 4 == 0:
			draw_line(p + Vector2(31, 3), p + Vector2(33, -22),
				Color("#536752"), 4)
			draw_circle(p + Vector2(33, -23), 3, Color("#b3b28a"))


func _pine(tree: Dictionary) -> void:
	if pine_frames.is_empty():
		return
	var p: Vector2 = tree.p
	var variant: int = tree.variant
	var wind: int = 1 + roundi(sin(wind_clock * 1.4 + p.x * 0.013))
	if tree.layer == 0:
		_contact_shadow(p + Vector2(2, 2 * tree.root_gradient),
			tree.half.x + 2, 1.5, 0.12, tree.support, tree.root_gradient)
	var tint: Color = [Color.WHITE, Color("#91a99a"), Color("#718f83")][tree.layer]
	draw_mesh(tree_meshes[tree.mesh_index], pine_frames[variant][wind], Transform2D.IDENTITY, tint)


func _rock(p: Vector2, size: float) -> void:
	if not rock_textures.is_empty():
		_contact_shadow(p + Vector2(size * 0.12, size * 0.25), size * 0.72, 1.5, 0.13)
		draw_texture_rect(rock_textures[absi(int(p.x)) % 4],
			Rect2((p - Vector2(size, size)).round(), Vector2(size * 2, size * 1.33).round()), false)


func _fern(p: Vector2, scale_value: float = 1.0, support: int = -1) -> void:
	if fern_frames.is_empty():
		return
	var wind: int = 1 + roundi(sin(wind_clock * 1.8 + p.x * 0.03))
	_contact_shadow(p, 3, 1, 0.09, support)
	draw_texture_rect(fern_frames[absi(int(p.x)) % 4][wind],
		Rect2(p - Vector2(24, 31) * scale_value, Vector2(48, 32) * scale_value), false)


func _contact_shadow(p: Vector2, width: float, height: float, opacity: float,
		support: int = -1, gradient: float = 0.0) -> void:
	if support < 0:
		for index in range(placement.surfaces.size()):
			if placement.surfaces[index].kind != "distant_ridge" and Geometry2D.is_point_in_polygon(
					p, placement.surfaces[index].polygon):
				support = index
				break
	if support < 0:
		return
	var key := "%s:%s:%s:%s:%s" % [p, width, height, support, gradient]
	if not shadow_cache.has(key):
		var polygon := PackedVector2Array([
		p + Vector2(-width, 0), p + Vector2(-width * 0.6, -height),
		p + Vector2(width * 0.5, -height), p + Vector2(width, 0),
		p + Vector2(width * 0.6, height), p + Vector2(-width * 0.5, height)])
		for index in range(polygon.size()):
			polygon[index].y += (polygon[index].x - p.x) * gradient
		shadow_cache[key] = Geometry2D.intersect_polygons(polygon, placement.surfaces[support].polygon)
	for polygon in shadow_cache[key]:
		draw_colored_polygon(polygon, Color(0.06, 0.14, 0.12, opacity))


func _textured_cliff(polygon: PackedVector2Array, tint: Color, distant: bool = false) -> void:
	var uv := PackedVector2Array()
	for point in polygon:
		uv.append(point / (768.0 if distant else 384.0))
	draw_polygon(polygon, PackedColorArray([tint]), uv, distant_cliff if distant else cliff_texture)


func _draw_bench(p: Vector2) -> void:
	draw_line(p + Vector2(-15, 0), p + Vector2(-15, -10), Color("#3a4940"), 3)
	draw_line(p + Vector2(15, 0), p + Vector2(15, -10), Color("#3a4940"), 3)
	draw_rect(Rect2(p + Vector2(-22, -14), Vector2(44, 4)), Color("#b09b68"))
	draw_rect(Rect2(p + Vector2(-22, -22), Vector2(44, 5)), Color("#847c55"))
	draw_line(p + Vector2(-21, -22), p + Vector2(20, -22), Color("#b7a777"), 1)
	draw_line(p + Vector2(-19, -12), p + Vector2(18, -12), Color("#d1b98a"), 1)
	for x in [-17, 16]:
		draw_rect(Rect2(p + Vector2(x, -21), Vector2(1, 1)), Color("#344b47"))
		draw_rect(Rect2(p + Vector2(x, -13), Vector2(1, 1)), Color("#344b47"))


func _draw_sign(p: Vector2) -> void:
	draw_line(p, p + Vector2(0, -36), Color("#7f805c"), 3)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(12, -32), p + Vector2(-16, -32),
		p + Vector2(-22, -27), p + Vector2(-16, -22),
		p + Vector2(12, -22)]), Color("#b1a375"))
	draw_line(p + Vector2(-15, -31), p + Vector2(10, -31), Color("#d2bf8e"), 1)
	draw_line(p + Vector2(5, -27), p + Vector2(-11, -27), Color("#465c51"), 1)
	draw_line(p + Vector2(-11, -27), p + Vector2(-7, -30), Color("#465c51"), 1)
	draw_line(p + Vector2(-11, -27), p + Vector2(-7, -24), Color("#465c51"), 1)


func _build_clearing(p: Vector2, direction: float, summit: bool) -> void:
	var back := PackedVector2Array()
	var front := PackedVector2Array()
	var route := PackedVector2Array()
	var profile: Array = [[-66, -9], [-30, -15], [-8, -22],
		[52, -42], [98, -51], [144, -29], [195, 12]] if summit else [
		[-190, -9], [-135, -14], [-35, -18], [40, -21], [100, -34],
		[165, -44], [217, -28], [265, 12]]
	var first: float = profile[0][0]
	var last: float = profile[-1][0]
	for sample in range(ceili((last - first) / 4.0) + 1):
		var offset: float = minf(last, first + sample * 4)
		var section: int = 0
		while section < profile.size() - 2 and offset > profile[section + 1][0]:
			section += 1
		var t: float = smoothstep(profile[section][0], profile[section + 1][0], offset)
		var center: Vector2 = _clearing_route_point(p.x + direction * minf(offset, 0), summit)
		center.x = p.x + direction * offset
		var widening: float = smoothstep(first, first + 90, offset)
		var noise: float = (sin(center.x * 0.17) + sin(center.x * 0.39) * 0.5) * widening
		var rear: float = lerpf(profile[section][1], profile[section + 1][1], t)
		back.append(center + Vector2(0, rear + noise))
		front.append(center + Vector2(0,
			lerpf(15, 20 + sin(offset * 0.018) * 7, widening) + noise * 0.7))
		route.append(center)
	var polygon: PackedVector2Array = back.duplicate()
	var reversed: PackedVector2Array = front.duplicate()
	reversed.reverse()
	polygon.append_array(reversed)
	var bounds: Rect2 = _polygon_bounds(polygon)
	var origin: Vector2 = bounds.position.floor()
	var size := Vector2i(bounds.end.ceil() - origin) + Vector2i.ONE
	clearings.append({"surface": polygon, "back": back, "front": front,
		"p": p, "direction": direction, "summit": summit, "route": route,
		"origin": origin, "texture": Art.clearing_surface(size, origin, polygon,
			back, front, route, p, direction)})


func _clearing_route_point(x: float, summit: bool) -> Vector2:
	var first: int = trail.points.size() - 2 if summit else 0
	var last: int = trail.points.size() - 1 if summit else trail.climbs[0].last_point
	for index in range(first, last):
		var a: Vector2 = trail.points[index]
		var b: Vector2 = trail.points[index + 1]
		if x >= minf(a.x, b.x) - 0.001 and x <= maxf(a.x, b.x) + 0.001:
			return a.lerp(b, clampf((x - a.x) / (b.x - a.x), 0, 1))
	return trail.points[-1] if summit else trail.points[0]


func _build_mountain() -> void:
	var bounds := Rect2(trail.points[0], Vector2.ZERO)
	for p in trail.points:
		bounds = bounds.expand(p)
	var contours: Array[PackedVector2Array] = [trail.points]
	for clearing in clearings:
		contours.append(clearing.back)
		for p in clearing.back:
			bounds = bounds.expand(p)
	mountain_floor = bounds.end.y + 1100
	var indices: Array[Dictionary] = []
	for contour in contours:
		var transposed := PackedVector2Array()
		for p in contour:
			transposed.append(Vector2(p.y, p.x))
		indices.append(Placement.index_segments(transposed))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var top: float = bounds.position.y
	var bottom: float = bounds.end.y + 150
	# Resolve both cliff sides at each elevation. A highest-route Y(x) envelope
	# wrongly projects an upper landing's roof all the way down behind lower stairs.
	for sample in range(ceili((bottom - top) / 8.0) + 1):
		var y: float = minf(bottom, top + sample * 8)
		var low: float = INF
		var high: float = -INF
		for guide_index in range(contours.size()):
			var guide: PackedVector2Array = contours[guide_index]
			for index in Placement.segments_in(indices[guide_index], y - 150, y):
				var a: Vector2 = guide[index]
				var b: Vector2 = guide[index + 1]
				if y < minf(a.y, b.y) or y > maxf(a.y, b.y) + 150:
					continue
				var t: float = clampf((y - a.y) / (b.y - a.y), 0, 1) if absf(b.y - a.y) > 0.01 else 0.0
				var x: float = lerpf(a.x, b.x, t)
				var width: float = 40 if guide_index == 0 else 12
				low = minf(low, minf(a.x, b.x) - width if absf(a.y - b.y) < 1 else x - width)
				high = maxf(high, maxf(a.x, b.x) + width if absf(a.y - b.y) < 1 else x + width)
		if is_inf(low):
			low = left[-1].y if not left.is_empty() else trail.points[-1].x - 40
			high = -right[-1].y if not right.is_empty() else trail.points[-1].x + 40
		# All higher shelves root into the same mass, not a floating route ribbon.
		if not left.is_empty():
			low = minf(low, left[-1].y)
			high = maxf(high, -right[-1].y)
		left.append(Vector2(y, low))
		right.append(Vector2(y, -high))
	left = _talus_envelope(left)
	right = _talus_envelope(right)
	var cap_index: int = mini(ceili(85.0 / 8.0), left.size() - 1)
	for index in range(left.size()):
		if index < cap_index:
			continue
		var y: float = left[index].x
		# Eroded shelves belong to the mass itself, not foliage hiding a crop.
		var erosion: float = _rock_shoulder(y, top, false)
		mountain.append(Vector2(left[index].y - maxf(0, erosion), y).round())
	var base_left: Vector2 = mountain[-1]
	mountain.append(Vector2(base_left.x - 160, mountain_floor))
	mountain.append(Vector2(-right[-1].y + 160, mountain_floor))
	for index in range(right.size() - 1, -1, -1):
		if index < cap_index:
			continue
		var y: float = right[index].x
		var erosion: float = _rock_shoulder(y, top, true)
		mountain.append(Vector2(-right[index].y + maxf(0, erosion), y).round())
	# Close the apex with the real route/clearing crest, not a horizontal roof
	# between the two side envelopes.
	var cap := PackedVector2Array()
	var first: Vector2 = mountain[0]
	var last: Vector2 = mountain[-1]
	var upper_segments: Array[Dictionary] = []
	for guide_index in range(contours.size()):
		var guide: PackedVector2Array = contours[guide_index]
		for index in range(guide.size() - 1):
			if minf(guide[index].y, guide[index + 1].y) <= first.y:
				upper_segments.append({"a": guide[index], "b": guide[index + 1],
					"width": 31 if guide_index == 0 and trail.segment_kinds[index] == "stairs" else 0})
	for surface in terminal_surfaces.values():
		var guide: PackedVector2Array = surface.polygon
		for index in range(guide.size()):
			var a: Vector2 = guide[index]
			var b: Vector2 = guide[(index + 1) % guide.size()]
			if minf(a.y, b.y) <= first.y:
				upper_segments.append({"a": a, "b": b, "width": 0})
	for sample in range(ceili((last.x - first.x) / 6.0) + 1):
		var x: float = minf(last.x, first.x + sample * 6)
		var y: float = first.y
		for segment in upper_segments:
			var a: Vector2 = segment.a
			var b: Vector2 = segment.b
			if x < minf(a.x, b.x) - segment.width or x > maxf(a.x, b.x) + segment.width:
				continue
			var t: float = clampf((x - a.x) / (b.x - a.x), 0, 1) if absf(b.x - a.x) > 0.01 else 0
			y = minf(y, lerpf(a.y, b.y, t))
		cap.append(Vector2(x, y))
	cap = _talus_envelope(cap)
	cap.reverse()
	mountain.append_array(cap)


func _rock_shoulder(y: float, top: float, right: bool) -> float:
	var phase: float = 1.2 if right else 0.0
	return (y - top) * 0.035 + maxf(0, 14 + sin(y * 0.009 + phase) * 18
		+ sin(y * 0.023 + phase) * 9)


func _talus_envelope(supports: PackedVector2Array) -> PackedVector2Array:
	# Lower envelope of parabolas, evaluated in linear time. An unlimited reach
	# matters: truncating an upper stair's influence creates another vertical cut.
	const CURVATURE: float = 0.024
	var candidates: Array[int] = [0]
	var boundaries: Array[float] = [-INF, INF]
	for index in range(1, supports.size()):
		var q: Vector2 = supports[index]
		var crossing: float
		while true:
			var p: Vector2 = supports[candidates[-1]]
			crossing = ((q.y + CURVATURE * q.x * q.x) -
				(p.y + CURVATURE * p.x * p.x)) / (2 * CURVATURE * (q.x - p.x))
			if crossing > boundaries[-2] or candidates.size() == 1:
				break
			candidates.pop_back()
			boundaries.remove_at(boundaries.size() - 2)
		boundaries.insert(boundaries.size() - 1, crossing)
		candidates.append(index)
	var result: PackedVector2Array = supports.duplicate()
	var active: int = 0
	for index in range(result.size()):
		while boundaries[active + 1] < result[index].x:
			active += 1
		var origin: Vector2 = supports[candidates[active]]
		var dx: float = result[index].x - origin.x
		result[index].y = origin.y + CURVATURE * dx * dx
	return result


func _surface_chips(polygon: PackedVector2Array, spacing: int) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	for x in range(floori(bounds.position.x), ceili(bounds.end.x), spacing):
		for y in range(floori(bounds.position.y), ceili(bounds.end.y), spacing):
			var code: int = posmod(x * 17 + y * 31, 23)
			var chip := Vector2(x + code % 4, y)
			if code < 12 and Geometry2D.is_point_in_polygon(chip, polygon):
				draw_rect(Rect2(chip, Vector2(4 + code % 6, 2)),
					Color("#829064") if code < 4 else Color("#587653"))
				if code < 4:
					draw_rect(Rect2(chip + Vector2(1, -1), Vector2(4, 1)), Color("#a7ac80"))
				elif code < 8:
					draw_rect(Rect2(chip + Vector2(2, -2), Vector2(6, 2)), Color("#587653"))


func _draw_clearing(clearing: Dictionary) -> void:
	var front: PackedVector2Array = clearing.front
	var face: PackedVector2Array = front.duplicate()
	for index in range(front.size() - 1, -1, -1):
		face.append(front[index] + Vector2(0, 110 + sin(front[index].x * 0.016) * 12))
	_textured_cliff(face, Color.WHITE)
	draw_texture(clearing.texture, clearing.origin)
	# Keep the existing sparse props, independent of the denser shared contour samples.
	for offset in [-35, 40, 100, 165, 217] if not clearing.summit else [-8, 52, 98, 144]:
		var x: float = clearing.p.x + clearing.direction * offset
		var nearest: int = 0
		for index in range(clearing.back.size()):
			if absf(clearing.back[index].x - x) < absf(clearing.back[nearest].x - x):
				nearest = index
		var at: Vector2 = clearing.back[nearest]
		if offset in [-35, 100, 217, 52, 144]:
			_rock(at + Vector2(7, 10), 15 if clearing.summit else 10)
	if clearing.summit:
		var outcrop: Vector2 = clearing.p + Vector2(clearing.direction * 108, -15)
		_rock(outcrop, 35)
		_rock(outcrop + Vector2(-16, 4), 22)


func _draw_trailhead(p: Vector2) -> void:
	var log_start: Vector2 = p + Vector2(111, -6)
	draw_line(log_start, log_start + Vector2(64, -5), Color("#293f3a"), 12)
	draw_line(log_start + Vector2(1, -4), log_start + Vector2(62, -9), Color("#857853"), 5)
	draw_line(log_start + Vector2(7, -5), log_start + Vector2(52, -9), Color("#b3a273"), 1)
	draw_line(log_start + Vector2(19, -1), log_start + Vector2(42, -3), Color("#4d6547"), 4)
	_rock(p + Vector2(30, 17), 13)
