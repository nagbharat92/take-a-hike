extends RefCounted

# Only rendered top surfaces belong here. Cliff faces are not planting ground.
var surfaces: Array[Dictionary] = []
var patches: Array[Dictionary] = []
const COLUMN_WIDTH: float = 16.0
const TREE_ROOT_MARGIN: float = 0.35
var grove_noise := FastNoiseLite.new()


func configure(seed_value: int) -> void:
	grove_noise.seed = seed_value ^ 49979687
	grove_noise.frequency = 0.0018
	grove_noise.fractal_octaves = 2


func add_surface(polygon: PackedVector2Array, kind: String, route: PackedVector2Array) -> int:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	# Index, don't simplify, the authored contours. Exact crossings and notch tests remain.
	var edges: Dictionary = {}
	var vertices: Dictionary = {}
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var column: int = floori(a.x / COLUMN_WIDTH)
		if not vertices.has(column):
			vertices[column] = PackedVector2Array()
		vertices[column].append(a)
		for cell in range(floori(minf(a.x, b.x) / COLUMN_WIDTH),
				floori(maxf(a.x, b.x) / COLUMN_WIDTH) + 1):
			if not edges.has(cell):
				edges[cell] = PackedInt32Array()
			edges[cell].append(index)
	surfaces.append({"polygon": polygon, "kind": kind, "route": route, "bounds": bounds,
		"edges": edges, "vertices": vertices, "route_index": index_segments(route)})
	return surfaces.size() - 1


func supported(surface_id: int, root: Vector2, half: Vector2, margin: float = 1.0,
		gradient: float = 0.0) -> bool:
	var surface: Dictionary = surfaces[surface_id]
	var extent := half + Vector2.ONE * margin
	var bounds_half := Vector2(extent.x, extent.y + absf(gradient) * extent.x)
	if not surface.bounds.encloses(Rect2(root - bounds_half, bounds_half * 2)):
		return false
	# Each entire vertical cross-section must fit one interior interval. Also
	# inspect contour vertices so a sub-pixel notch cannot slip between samples.
	var columns: int = maxi(2, ceili(extent.x * 2))
	for x in range(columns + 1):
		var at_x: float = root.x - extent.x + extent.x * 2 * float(x) / columns
		var at_y: float = root.y + gradient * (at_x - root.x)
		if not _section_fits(surface_id, at_x, at_y - extent.y, at_y + extent.y):
			return false
	for cell in range(floori((root.x - extent.x) / COLUMN_WIDTH),
			floori((root.x + extent.x) / COLUMN_WIDTH) + 1):
		for vertex in surface.vertices.get(cell, PackedVector2Array()):
			if vertex.x > root.x - extent.x and vertex.x < root.x + extent.x:
				for offset in [-0.001, 0.0, 0.001]:
					var at_y: float = root.y + gradient * (vertex.x + offset - root.x)
					if not _section_fits(surface_id, vertex.x + offset, at_y - extent.y, at_y + extent.y):
						return false
	return true


func _crossings(surface_id: int, x: float) -> Array[float]:
	var polygon: PackedVector2Array = surfaces[surface_id].polygon
	var hits: Array[float] = []
	for i in surfaces[surface_id].edges.get(floori(x / COLUMN_WIDTH), PackedInt32Array()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		if (a.x <= x and b.x > x) or (b.x <= x and a.x > x):
			hits.append(lerpf(a.y, b.y, (x - a.x) / (b.x - a.x)))
	hits.sort()
	return hits


func _section_fits(surface_id: int, x: float, top: float, bottom: float) -> bool:
	var hits: Array[float] = _crossings(surface_id, x)
	for index in range(0, hits.size() - 1, 2):
		if top > hits[index] + 0.001 and bottom < hits[index + 1] - 0.001:
			return true
	return false


func span_at_x(surface_id: int, x: float) -> Vector2:
	var hits: Array[float] = _crossings(surface_id, x)
	if hits.size() < 2:
		return Vector2(INF, -INF)
	return Vector2(hits[0], hits[-1])


func walking_span(surface_id: int, x: float) -> Vector2:
	var surface: Dictionary = surfaces[surface_id]
	var span: Vector2 = span_at_x(surface_id, x)
	var route_y: float = _route_height(surface.route, x, surface.route_index)
	if not is_finite(route_y):
		return Vector2(-INF, INF)
	# The route is not the middle of its pseudo-depth surface. Keep the complete
	# boot lane clear, including the front half of the visible walking ribbon.
	return Vector2(minf(route_y - 3.5, lerpf(span.x, span.y, 0.23)),
		maxf(route_y + 5, lerpf(span.x, span.y, 0.625)))


func tree_footprint_clear(surface_id: int, root: Vector2, half: Vector2,
		margin: float = TREE_ROOT_MARGIN, gradient: float = 0.0) -> bool:
	var extent := half + Vector2.ONE * margin
	var back: bool = true
	var front: bool = true
	var columns: int = maxi(2, ceili(extent.x * 2))
	for column in range(columns + 1):
		var x: float = root.x - extent.x + extent.x * 2 * float(column) / columns
		var y: float = root.y + gradient * (x - root.x)
		var lane: Vector2 = walking_span(surface_id, x)
		back = back and y + extent.y <= lane.x
		front = front and y - extent.y >= lane.y
		if not back and not front:
			return false
	for cell in range(floori((root.x - extent.x) / COLUMN_WIDTH),
			floori((root.x + extent.x) / COLUMN_WIDTH) + 1):
		for vertex in surfaces[surface_id].vertices.get(cell, PackedVector2Array()):
			if vertex.x <= root.x - extent.x or vertex.x >= root.x + extent.x:
				continue
			var y: float = root.y + gradient * (vertex.x - root.x)
			var lane: Vector2 = walking_span(surface_id, vertex.x)
			back = back and y + extent.y <= lane.x
			front = front and y - extent.y >= lane.y
			if not back and not front:
				return false
	return true


func shoulder_roots(surface_id: int, x: float, half: Vector2,
		root_offset: Vector2, margin: float = TREE_ROOT_MARGIN, gradient: float = 0.0) -> PackedVector2Array:
	var extent := half + Vector2.ONE * margin
	var rear: float = -INF
	var front: float = INF
	# Fit the physical root rectangle against the actual contours across its
	# width. Direction, grade and asymmetric sprite padding do not change this.
	var columns: int = maxi(2, ceili(extent.x * 2))
	for column in range(columns + 1):
		var at_x: float = x - extent.x + extent.x * 2 * float(column) / columns
		var span: Vector2 = span_at_x(surface_id, at_x)
		rear = maxf(rear, span.x + extent.y + 0.02 - gradient * (at_x - x))
		front = minf(front, span.y - extent.y - 0.02 - gradient * (at_x - x))
	return PackedVector2Array([
		Vector2(x, rear) - root_offset, Vector2(x, front) - root_offset])


func gradient_at(surface_id: int, x: float, radius: float = 8) -> float:
	var surface: Dictionary = surfaces[surface_id]
	var left: float = _route_height(surface.route, x - radius, surface.route_index)
	var right: float = _route_height(surface.route, x + radius, surface.route_index)
	return (right - left) / (radius * 2) if is_finite(left) and is_finite(right) else 0.0


func slope_at(surface_id: int, x: float, radius: float = 8) -> float:
	var route: PackedVector2Array = surfaces[surface_id].route
	if not route.is_empty():
		var left: float = _route_height(route, x - radius, surfaces[surface_id].route_index)
		var right: float = _route_height(route, x + radius, surfaces[surface_id].route_index)
		if not is_finite(left) or not is_finite(right):
			return INF
		return absf(right - left) / (radius * 2)
	var a: Vector2 = span_at_x(surface_id, x - radius)
	var b: Vector2 = span_at_x(surface_id, x + radius)
	if not is_finite(a.x) or not is_finite(b.x):
		return INF
	return absf(b.x - a.x) / (radius * 2)


func _route_height(route: PackedVector2Array, x: float, index_by_x: Dictionary) -> float:
	for index in index_by_x.get(floori(x / COLUMN_WIDTH), PackedInt32Array()):
		var a: Vector2 = route[index]
		var b: Vector2 = route[index + 1]
		if x >= minf(a.x, b.x) and x <= maxf(a.x, b.x) and absf(b.x - a.x) > 0.001:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return INF


static func index_segments(points: PackedVector2Array) -> Dictionary:
	var result: Dictionary = {}
	for index in range(points.size() - 1):
		for cell in range(floori(minf(points[index].x, points[index + 1].x) / COLUMN_WIDTH),
				floori(maxf(points[index].x, points[index + 1].x) / COLUMN_WIDTH) + 1):
			if not result.has(cell):
				result[cell] = PackedInt32Array()
			result[cell].append(index)
	return result


static func segments_in(index_by_x: Dictionary, left: float, right: float) -> Dictionary:
	var result: Dictionary = {}
	for cell in range(floori(left / COLUMN_WIDTH), floori(right / COLUMN_WIDTH) + 1):
		for index in index_by_x.get(cell, PackedInt32Array()):
			result[index] = true
	return result


func seed_patches(length: float, rng: RandomNumberGenerator, personality: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cursor: float = 40 + rng.randf_range(0, 70)
	while cursor < length - 50:
		var coherence: float = grove_noise.get_noise_1d(cursor)
		var width: float = rng.randf_range(280, 390) * [1.12, 1.0, 0.9][personality] * (
			1.0 + coherence * 0.12)
		var patch := {"start": cursor, "end": minf(length - 45, cursor + width),
			"kind": rng.randi_range(0, 1)}
		result.append(patch)
		patches.append(patch)
		cursor += width + rng.randf_range(110, 175)
	return result


func patch_weight(distance: float, patch: Dictionary) -> float:
	return smoothstep(patch.start, patch.start + 38, distance) * (
		1.0 - smoothstep(patch.end - 38, patch.end, distance))


static func tree_site_allowed(kind: String, slope: float, height: float) -> bool:
	if kind == "ribbon":
		return slope <= 0.63
	return kind == "clearing" and slope <= 0.63
