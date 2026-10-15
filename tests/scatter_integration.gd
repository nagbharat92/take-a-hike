extends SceneTree

const Placement = preload("res://scripts/vegetation_placement.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func full_crossings(polygon: PackedVector2Array, x: float) -> Array[float]:
	var hits: Array[float] = []
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		if (a.x <= x and b.x > x) or (b.x <= x and a.x > x):
			hits.append(lerpf(a.y, b.y, (x - a.x) / (b.x - a.x)))
	hits.sort()
	return hits


func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.player.set_physics_process(false)
	game.camera.set_physics_process(false)
	var adapter = game.landscape.scatter
	check(adapter.modifier.get_script().resource_path.begins_with("res://addons/scatter2d/"),
		"The executed modifier must be the actual upstream library")
	var exclusions: Array[Vector2] = [Vector2(90, 180)]
	seed(98765)
	var expected_random: int = randi()
	seed(98765)
	var first: PackedFloat32Array = adapter.grove(28, 350, 27, 1234, exclusions)
	check(randi() == expected_random, "Library sampling does not consume the global route-seed stream")
	check(first == adapter.grove(28, 350, 27, 1234, exclusions), "Stable seeded library sampling")
	check(not first.is_empty(), "The first connected grove fills")
	for distance in first:
		check(distance >= 28 and distance <= 350 and not (distance >= 90 and distance <= 180),
			"Library inclusion and exclusion domains are honored")
	var no_exclusions: Array[Vector2] = []
	var second: PackedFloat32Array = adapter.grove(900, 1250, 27, 4321, no_exclusions)
	check(second.size() >= 10, "Disconnected grove sampled independently, not stranded by Poisson")
	var support = Placement.new()
	var polygon := PackedVector2Array([
		Vector2(-42, -10), Vector2(42, -10), Vector2(42, 20),
		Vector2(0.3, 20), Vector2(0.3, -3), Vector2(-0.3, -3),
		Vector2(-0.3, 20), Vector2(-42, 20)])
	var id: int = support.add_surface(polygon, "clearing", PackedVector2Array())
	for x in [-48.0, -42.0, -32.0, -16.0, -0.301, -0.3, 0.0, 0.3, 0.301, 16.0, 32.0, 42.0]:
		check(support._crossings(id, x) == full_crossings(polygon, x),
			"Indexed support retains exact negative-coordinate, boundary and notch crossings")
	check(not support.supported(id, Vector2(0, 4), Vector2(3, 2), 0),
		"Subpixel notch cannot be bypassed by indexed support")
	for grade in [-0.45, 0.0, 0.45]:
		for reversed in [false, true]:
			var route := PackedVector2Array([Vector2(-40, -40 * grade), Vector2(40, 40 * grade)])
			var ribbon := PackedVector2Array([
				route[0] + Vector2(0, -9), route[1] + Vector2(0, -9),
				route[1] + Vector2(0, 15), route[0] + Vector2(0, 15)])
			if reversed:
				route.reverse()
			var ribbon_id: int = support.add_surface(ribbon, "ribbon", route)
			var half := Vector2(10, 1.5)
			var offset := Vector2(0, -0.75)
			var gradient: float = support.gradient_at(ribbon_id, 0, half.x)
			check(is_equal_approx(gradient, grade), "Ground grade follows screen normal, not walking direction")
			var roots: PackedVector2Array = support.shoulder_roots(ribbon_id, 0, half, offset,
				support.TREE_ROOT_MARGIN, gradient)
			check(support.supported(ribbon_id, roots[0] + offset, half,
				support.TREE_ROOT_MARGIN, gradient), "The outer rear root band is physically supported")
			check(support.tree_footprint_clear(ribbon_id, roots[0] + offset, half,
				support.TREE_ROOT_MARGIN, gradient), "Rear roots exclude the complete ribbon walking lane")
			check(not support.tree_footprint_clear(ribbon_id, Vector2(0, 7.5) + offset, half,
				support.TREE_ROOT_MARGIN, gradient),
				"Old centerline-radius-valid front-center roots fail the actual footprint exclusion")
			check(not support.tree_footprint_clear(ribbon_id, Vector2.ZERO, half,
				support.TREE_ROOT_MARGIN, gradient), "The ribbon center can never become a tree domain")
	var tree_library = game.landscape.Library
	var tree_texture: int = tree_library.tree_frames[0][0].get_instance_id()
	var background_texture: int = game.backdrop.mountains[0].get_instance_id()
	for variant in range(5):
		check(tree_library.tree_used_heights[variant] ==
			float(tree_library.tree_masks[variant].get_used_rect().size.y),
			"Cached imported dimensions exactly match opaque artwork")
	game.set_overview(true)
	game.camera.manual_zoom(1)
	var map_scale: float = game.camera.map_scale
	for request in range(12):
		game.request_new_hike()
	check(game._new_hike_pending, "Rapid input is queued once")
	await process_frame
	check(not game._new_hike_pending and game.overview and not game.camera.transitioning,
		"Coalesced R retains map mode with an immediate static reframe")
	check(game.camera.map_scale == map_scale, "R preserves deliberate manual zoom")
	check(tree_library.tree_frames[0][0].get_instance_id() == tree_texture,
		"R reuses imported sprite textures without decoding again")
	check(game.backdrop.mountains[0].get_instance_id() != background_texture,
		"R builds a distinct seeded mountain panorama")
	check(game.player.WALK_SPEED == 180.0, "Fixed movement speed is unchanged")
	print("Scatter integration: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	game.free()
	quit(1 if failures else 0)
