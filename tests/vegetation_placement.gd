extends SceneTree

var game
var checks: int = 0
var failures: int = 0
var review: bool = false
var images: Dictionary = {}
var review_dir: String = "res://builds/placement-review"


func image_of(texture: Texture2D) -> Image:
	var key: int = texture.get_instance_id()
	if not images.has(key):
		images[key] = texture.get_image()
	return images[key]


func _initialize() -> void:
	review = "--render-review" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-dir="):
			review_dir = argument.trim_prefix("--review-dir=")
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures < 12:
			push_error(message)


func place(index: int) -> void:
	game.player.set_physics_process(false)
	game.player._segment = index
	game.player._distance = 0
	game.player.advance(0, 0)
	game.camera.snap_to_target()
	game._process(0)


func place_world(point: Vector2, climb) -> void:
	var nearest: int = climb.first_point
	for index in range(climb.first_point, climb.last_point):
		if game.trail.points[index].distance_to(point) < game.trail.points[nearest].distance_to(point):
			nearest = index
	place(nearest)


func capture(label: String) -> void:
	if not review:
		return
	for tick in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("%s/%s.png" % [review_dir, label]) == OK,
		"Native viewport capture saved")


func tree_pixels(tree: Dictionary) -> void:
	var library = game.landscape.Library
	var polygon: PackedVector2Array = game.landscape.placement.surfaces[tree.support].polygon
	var frame: Rect2 = library.tree_rect(tree.p, tree.height, tree.variant)
	var anchor: Vector2 = library.tree_roots[tree.variant]
	var size: Vector2 = library.tree_frames[tree.variant][0].get_size()
	var scale_value: Vector2 = frame.size / size
	check((frame.position + anchor * scale_value).distance_to(tree.p) < 0.001,
		"Actual measured sprite root transforms onto terrain anchor")
	for wind in range(3):
		var image: Image = image_of(library.tree_frames[tree.variant][wind])
		var used: Rect2i = image.get_used_rect()
		for y in range(used.end.y - 2, used.end.y):
			for x in range(used.position.x, used.end.x):
				if image.get_pixel(x, y).a < 0.5:
					continue
				var pixel: Vector2 = frame.position + (Vector2(x, y) + Vector2.ONE * 0.5) * scale_value
				pixel = library.grounded_tree_pixel(pixel, tree.p, tree.height,
					tree.variant, tree.get("root_gradient", 0.0))
				check(rendered_support(tree.support, pixel),
					"Opaque root support: root=%s pixel=%s variant=%d height=%.1f gradient=%.3f half=%s span=%s inside=%s surface=%d" % [
						tree.p, pixel, tree.variant, tree.height, tree.get("root_gradient", 0.0), tree.half,
						game.landscape.placement.span_at_x(tree.support, pixel.x),
						Geometry2D.is_point_in_polygon(pixel, polygon), tree.support])
				if tree.has("root_gradient"):
					var lane: Vector2 = game.landscape.placement.walking_span(tree.support, pixel.x)
					check(pixel.y < lane.x or pixel.y > lane.y,
						"Actual opaque root pixels stay outside the surface walking lane in every wind frame")
				var surface: Dictionary = game.landscape.placement.surfaces[tree.support]
				if surface.kind == "ribbon":
					var span: Vector2 = game.landscape.placement.span_at_x(tree.support, pixel.x)
					check((pixel.y - span.x) / (span.y - span.x) < 0.23,
						"Interior opaque roots occupy the rear outer band of the actual ribbon, never its center")
					for segment in game.landscape.Placement.segments_in(
							surface.route_index, pixel.x, pixel.x):
						var a: Vector2 = surface.route[segment]
						var b: Vector2 = surface.route[segment + 1]
						if pixel.x < minf(a.x, b.x) or pixel.x > maxf(a.x, b.x):
							continue
						var route_y: float = lerpf(a.y, b.y, (pixel.x - a.x) / (b.x - a.x))
						var grade: float = (b.y - a.y) / (b.x - a.x)
						check((route_y - pixel.y) / sqrt(1 + grade * grade) >= 3.0,
							"Actual root pixels leave at least three world pixels of signed-normal boot clearance")


func rendered_support(surface_id: int, pixel: Vector2) -> bool:
	var surface: Dictionary = game.landscape.placement.surfaces[surface_id]
	var polygon: PackedVector2Array = surface.polygon
	if not surface.has("triangles"):
		surface["triangles"] = Geometry2D.triangulate_polygon(polygon)
	var triangles: PackedInt32Array = surface.triangles
	for index in range(0, triangles.size(), 3):
		if Geometry2D.point_is_inside_triangle(pixel, polygon[triangles[index]],
				polygon[triangles[index + 1]], polygon[triangles[index + 2]]):
			return true
	return false


func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	root.gui_disable_input = true
	game.set_process_unhandled_key_input(false)
	game.set_process_unhandled_input(false)
	game.set_process(false)
	game.camera.set_physics_process(false)
	var personalities: Dictionary = {}
	var parity: Dictionary = {}
	var near_count: int = 0
	var seeds: Array = range(25)
	seeds.append_array([72, 127, 1024, 99991, 314159, 2147483647, 4294967295])
	if review:
		seeds = [0, 1, 2, 8]
	for seed_value in seeds:
		game.trail.generate(seed_value)
		var geometry: PackedVector2Array = game.trail.points.duplicate()
		game._begin_hike()
		game.player.set_physics_process(false)
		game.camera.set_physics_process(false)
		var land = game.landscape
		var support = land.placement
		personalities[game.trail.personality] = true
		parity[game.trail.climbs.size() % 2] = true
		check(game.trail.points == geometry, "Planting never changes route geometry")
		check(land.grove_floors.is_empty(), "No invented wide soil ribbons behind narrow ledges")
		check(not land.trees.is_empty() and not land.reeds.is_empty(), "Clearing groves and supported low cover survive")
		check(land.foreground_trees.size() <= 2, "At most one near tree at each broad endpoint")
		check(land.distant_canvas.show_behind_parent and land.distant_canvas.get_index() >
			land.rock_canvases[0].get_index() and land.distant_canvas.get_index() <
			land.rock_canvases[-1].get_index(), "Distant bases are behind ledge lips but above the mountain band")
		near_count += land.foreground_trees.size()
		var recorded: int = hash(var_to_str(land.vegetation))
		var wooded_legs: int = 0
		var mature_total: int = 0
		for climb_index in range(land.ledges.size()):
			var mature: int = 0
			var groves: Dictionary = {}
			for tree in land.trees:
				if tree.get("climb", -1) == climb_index and tree.height >= 250:
					mature += 1
					groves[tree.patch_start] = groves.get(tree.patch_start, 0) + 1
					check(tree.height / 50.0 >= 5 and tree.height / 50.0 <= 12,
						"Interior mature trees remain 5-12 hiker heights, not miniature saplings")
			var substantial_groves: int = 0
			for members in groves.values():
				if members >= 3:
					substantial_groves += 1
			if mature >= 6 and substantial_groves >= 2:
				wooded_legs += 1
			mature_total += mature
			check(mature >= 3, "Each leg retains a mature grove: seed=%d leg=%d mature=%d" % [
				seed_value, climb_index, mature])
		check(wooded_legs >= ceili(land.ledges.size() * 0.6),
			"Most legs have multiple substantial mature groves: seed=%d wooded=%d/%d" % [
				seed_value, wooded_legs, land.ledges.size()])
		var openings: int = 0
		for stretch in land.forest_stretches:
			if stretch.weight != 0:
				continue
			openings += 1
			var surface_id: int = land.ledges[stretch.climb].support
			for plant in land.vegetation:
				if plant.support == surface_id:
					check(absf(plant.p.x - stretch.p.x) > 5 or absf(
						plant.p.y - stretch.p.y) > 20, "Gaps between patches remain genuinely unplanted")
		check(openings > land.forest_stretches.size() / 5, "Selected groves leave substantial ridge openings")
		check(openings < land.forest_stretches.size() * 0.55,
			"Openings cannot replace most of the hike with bare rock")
		for plant in land.vegetation:
			check(support.supported(plant.support, plant.p + plant.get("root_offset", Vector2.ZERO),
				plant.half, plant.get("margin", 1.0), plant.get("root_gradient", 0.0)),
				"Full physical footprint has cross-sectional top-surface support")
			check(land._stairs_clear(plant.p, plant.half.y) if plant.kind == "tree" else
				land._boot_clear(plant.p, plant.half.y),
				"No planted roots inside boot corridor, stair treads or landing joins")
			var surface: Dictionary = support.surfaces[plant.support]
			if plant.kind == "tree":
				check(surface.kind in ["clearing", "ribbon"], "Tree roots require rendered ground, never cliff faces")
				check(support.supported(plant.support, plant.p + plant.root_offset, plant.reserve,
					plant.margin, plant.root_gradient),
					"Tree support follows physical roots and margin, not canopy width or arbitrary flat soil")
				check(support.tree_footprint_clear(plant.support, plant.p + plant.root_offset,
					plant.half, plant.margin, plant.root_gradient),
					"Whole projected root footprint and margin exclude the surface-derived walking lane")
				check(land._tree_clearance(plant.p, plant.height, plant.variant) >= plant.height,
					"Tree canopy respects elevated traverses")
				tree_pixels(plant)
			elif surface.kind == "ribbon":
				var nearest: Vector2 = surface.route[0]
				var distance: float = INF
				for index in range(surface.route.size() - 1):
					var candidate := Geometry2D.get_closest_point_to_segment(plant.p,
						surface.route[index], surface.route[index + 1])
					if candidate.distance_to(plant.p) < distance:
						nearest = candidate
						distance = candidate.distance_to(plant.p)
				var stretch_found: bool = false
				for stretch in land.forest_stretches:
					if stretch.p.distance_to(nearest) < 25 and stretch.weight > 0.08:
						stretch_found = true
				check(stretch_found, "Low plants belong to selected patches, not uniform random scatter")
			if plant.kind == "fern":
				for wind in range(3):
					var variant: int = absi(int(plant.p.x)) % 4
					var image: Image = image_of(land.fern_frames[variant][wind])
					for y in range(28, 32):
						for x in range(48):
							if image.get_pixel(x, y).a > 0.5:
								var pixel: Vector2 = plant.p + (
									Vector2(x, y) + Vector2.ONE * 0.5 - Vector2(24, 31)) * plant.scale
								check(rendered_support(plant.support, pixel),
									"Real fern stalk support: seed=%d root=%s pixel=%s scale=%s kind=%s span=%s" % [
										seed_value, plant.p, pixel, plant.scale, surface.kind,
										support.span_at_x(plant.support, pixel.x)])
			elif plant.kind == "grass":
				for wind in range(3):
					var image: Image = image_of(land.grass_frames[plant.variant][wind])
					for x in range(28):
						if image.get_pixel(x, 15).a > 0.5:
							var pixel: Vector2 = plant.p + (
								Vector2(x, 15) + Vector2.ONE * 0.5 - Vector2(14, 15)) * plant.scale
							check(rendered_support(plant.support, pixel),
								"Actual grass-root pixels cannot extend into cliff void")
		for tree in land.distant_trees:
			tree_pixels(tree)
			var span: Vector2 = support.span_at_x(tree.support, tree.p.x)
			check(tree.p.y >= span.x and tree.p.y - span.x <= 9,
				"Distant roots meet the mountain band silhouette")
		for surface_id in range(support.surfaces.size()):
			var surface: Dictionary = support.surfaces[surface_id]
			if surface.kind == "distant_ridge":
				continue
			var center: Vector2 = surface.bounds.get_center()
			check(not support.supported(surface_id, center + Vector2(0, surface.bounds.size.y + 80),
				Vector2(10, 3)), "Reject void and cliff-face planting")
			check(not support.supported(surface_id, surface.bounds.position, Vector2(8, 3)),
				"An anchor at the edge does not imply supported root spread")
		check(land.Placement.tree_site_allowed("ribbon", 0.45, 350),
			"Normal sloped ledges may support mature trunks with overhanging canopies")
		check(not land.Placement.tree_site_allowed("stone", 0, 350),
			"Stair stone never becomes a tree site")
		check(not land.Placement.tree_site_allowed("clearing", 0.8, 350),
			"Beyond-route cliff grades remain ineligible")
		for tree in land.foreground_trees:
			check(game.get_node("Foreground").tree_rect(tree, Vector2.ZERO) ==
				game.get_node("Foreground").tree_rect(tree, Vector2(100, 300)),
				"Camera movement cannot detach near roots")
			var frame: Rect2 = land.Library.tree_rect(tree.p, tree.height, tree.variant)
			game.player.position = tree.p
			check(game.get_node("Foreground").foliage_opacity(frame, tree.variant) <= 0.06,
				"Actual root-overlapping foreground fades away from the hiker")
		if seed_value in [0, 1, 2, 8]:
			print("seed %d: trees=%d near=%d distant=%d low=%d personality=%d mature=%d wooded=%d/%d rejected=%s" % [
				seed_value, land.trees.size(), land.foreground_trees.size(),
				land.distant_trees.size(), land.reeds.size() + land.grasses.size(), game.trail.personality,
				mature_total, wooded_legs, land.ledges.size(), land.tree_rejections])
			place(0)
			await capture("%d-trailhead" % seed_value)
			for wind in [0.0, 1.0, 2.0]:
				land.wind_clock = wind
				land.queue_redraw()
				await capture("%d-root-motion-%d" % [seed_value, int(wind)])
			for phase in range(4):
				game.player.moving = true
				game.player.phase = TAU * phase / 4.0
				game.player.queue_redraw()
				await capture("%d-walk-%d" % [seed_value, phase])
			game.player.moving = false
			for climb_index in range(land.ledges.size()):
				var members: Array[Dictionary] = []
				for tree in land.trees:
					if tree.get("climb", -1) == climb_index:
						members.append(tree)
				if not members.is_empty():
					place_world(members[members.size() / 2].p, game.trail.climbs[climb_index])
					await capture("%d-mature-grove-%d" % [seed_value, climb_index])
			for stair_index in [0, 1]:
				var stair: Dictionary = game.trail.stairs[stair_index]
				for point in [stair.first - 1, stair.tread_first + 22, stair.last + 1]:
					place(mini(point, geometry.size() - 2))
					await capture("%d-stair-%d-%d" % [seed_value, stair_index, point])
			place(geometry.size() - 2)
			await capture("%d-summit" % seed_value)
			for climb in game.trail.climbs:
				if not climb.rest_points.is_empty():
					place_world((climb.rest_points[0] + climb.rest_points[1]) * 0.5, climb)
					await capture("%d-clearing" % seed_value)
					break
			for opening in [false, true]:
				for stretch in land.forest_stretches:
					if not stretch.rest and ((stretch.weight == 0) if opening else (stretch.weight > 0.8)):
						place_world(stretch.p, game.trail.climbs[stretch.climb])
						await capture("%d-%s" % [seed_value, "opening" if opening else "patch"])
						break
			game.set_overview(true)
			game.camera.snap_to_target()
			await capture("%d-overview" % seed_value)
			game.set_overview(false)
			game.camera.snap_to_target()
			for size in [Vector2i(960, 720), Vector2i(1600, 900)]:
				root.size = size
				await process_frame
				place(0)
				game.camera.close_scale = 1.25 if size.x == 960 else 3.5
				game.camera.snap_to_target()
				await capture("%d-resize-%d" % [seed_value, size.x])
			root.size = Vector2i(1280, 720)
			game.camera.close_scale = 2.2
		land.rebuild()
		check(hash(var_to_str(land.vegetation)) == recorded, "Same seed retains exact patch and plant selection")
		check(game.trail.points == geometry, "Scenery rebuild leaves approved geometry untouched")
	check(personalities.size() == 3 and parity.size() == 2, "Both endpoint orientations and all personalities covered")
	check(near_count > 0, "Restrained foreground is not accidentally absent")
	var fixture = game.landscape.Placement.new()
	var notch := PackedVector2Array([Vector2(0, 0), Vector2(4.2, 0), Vector2(4.3, 8),
		Vector2(4.4, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)])
	var support_id: int = fixture.add_surface(notch, "clearing", PackedVector2Array())
	check(not fixture.supported(support_id, Vector2(5, 9), Vector2(3, 3), 0),
		"Sub-pixel unsupported notch is caught between regular samples")
	check(fixture.supported(support_id, Vector2(12, 10), Vector2(3, 3), 1),
		"Nearby solid interior still supports a full footprint")
	for variant in range(4):
		var still: Image = game.landscape.fern_frames[variant][0].get_image()
		var breeze: Image = game.landscape.fern_frames[variant][2].get_image()
		check(still.get_region(Rect2i(0, 28, 48, 4)).get_data() ==
			breeze.get_region(Rect2i(0, 28, 48, 4)).get_data(), "Shrub root and lower stalk stay fixed in all frames")
		check(still.get_data() != breeze.get_data(), "Shrub fronds retain breeze motion")
	print("%s: %d placement, alpha-root, patch, corridor and motion checks across %d sampled seeds" % [
		"PASS" if failures == 0 else "FAIL", checks, seeds.size()])
	game.free()
	quit(1 if failures else 0)
