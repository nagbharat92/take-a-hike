extends RefCounted

const Scatter = preload("res://addons/scatter2d/src/scatter2d.gd")
const Edge = preload("res://addons/scatter2d/src/modifiers/mod_create_along_edge_even.gd")
const Domain = preload("res://addons/scatter2d/src/common/domain.gd")
const Transforms = preload("res://addons/scatter2d/src/common/transform_list.gd")
const Polygon = preload("res://addons/scatter2d/src/shapes/shape_polygon.gd")
const SCATTER_VERSION: int = 1

var scatter
var modifier = Edge.new()
var generated_candidates: int = 0


func attach(parent: Node2D) -> void:
	scatter = Scatter.new()
	scatter.name = "HikeScatter2D"
	scatter.force_rebuild_on_load = false
	scatter.enabled = false
	parent.add_child(scatter)
	scatter.set_process(false)
	modifier.use_local_space_by_default()


func grove(start: float, end: float, spacing: float, seed_value: int,
		exclusions: Array[Vector2]) -> PackedFloat32Array:
	# Sample each disconnected grove independently. Curve X is ground arc distance,
	# not screen X. These include/exclude domains describe grove/rest intervals,
	# not a walking surface: callers must project onto an authoritative shoulder
	# and validate the full root footprint against support and the walking mask.
	var domain = Domain.new()
	domain.root = scatter
	domain.positive_shapes.append(_shape(Vector2(start, end)))
	for interval in exclusions:
		domain.negative_shapes.append(_shape(interval))
	var curve := Curve2D.new()
	curve.add_point(Vector2(start, 0))
	curve.add_point(Vector2(end, 0))
	domain.edges.append(curve)
	var transforms = Transforms.new()
	modifier.spacing = spacing
	modifier.process_transforms(transforms, domain, seed_value)
	var distances := PackedFloat32Array()
	for transform in transforms.list:
		if domain.is_point_inside(transform.origin):
			distances.append(transform.origin.x)
	distances.sort()
	generated_candidates += distances.size()
	return distances


func _shape(interval: Vector2):
	var info = Domain.DomainShapeInfo.new()
	info.node = scatter
	var polygon = Polygon.new()
	polygon.polygon_points = PackedVector2Array([
		Vector2(interval.x, -2), Vector2(interval.y, -2),
		Vector2(interval.y, 2), Vector2(interval.x, 2)])
	info.shape = polygon
	return info
