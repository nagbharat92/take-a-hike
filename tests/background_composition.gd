extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 5:
			push_error(message)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.camera.set_physics_process(false)
	var backdrop = game.backdrop
	var textures: Array = backdrop.mountains.duplicate()
	check(textures.size() == 5, "Five cached distance planes")
	for texture in textures:
		var image: Image = texture.get_image()
		check(image.get_size() == Vector2i(1536, 480), "Overscanned original raster")
		for x in range(0, image.get_width(), 17):
			check(image.get_pixel(x, 0).a == 0, "Open sky above authored skyline")
			check(image.get_pixel(x, 478).a == 1, "Solid valley extends to panorama base")
	for x in [-1000000, -2000, 0, 2000, 1000000]:
		for y in [-1000000, -3000, 0, 1000000]:
			game.camera.position = Vector2(x, y)
			for layer in range(5):
				var rect: Rect2 = backdrop._mountain_rect(layer)
				check(rect.position.x <= 0 and rect.end.x >= 1280,
					"No wrap seam or uncovered horizontal camera bound")
				check(rect.end.y >= 720, "Valley covers bottom across full elevation range")
	var personalities: Dictionary = {}
	var foreground = game.get_node("Foreground")
	var visible_foreground: int = 0
	for viewport_size in [Vector2i(1280, 720), Vector2i(960, 720), Vector2i(1600, 900)]:
		root.size = viewport_size
		await process_frame
		for seed_value in [1, 2, 8]:
			game.trail.generate(seed_value)
			game._begin_hike()
			textures = backdrop.mountains.duplicate()
			game.player.set_physics_process(false)
			game.camera.set_physics_process(false)
			personalities[game.trail.personality] = true
			var points: PackedVector2Array = game.trail.points.duplicate()
			check(not game.landscape.trees.is_empty(), "Supported clearing groves remain visible")
			check(game.landscape.foreground_trees.size() <= 2, "Near framing is intermittent, not a wall on each traverse")
			check(not game.landscape.distant_trees.is_empty(), "Distant groves meet the existing ridge silhouette")
			var kinds: Dictionary = {}
			for stretch in game.landscape.forest_stretches:
				kinds[stretch.kind] = true
			check(kinds.size() == 3, "Woodland, sheltered ferns and open ridge stretches in one hike")
			for tree in game.landscape.foreground_trees:
				var at: Rect2 = foreground.tree_rect(tree, Vector2.ZERO)
				var shifted: Rect2 = foreground.tree_rect(tree, Vector2(10, 0))
				check(shifted == at, "Grounded near trees never slide relative to their soil")
			for climb in game.trail.climbs:
				if climb.rest_points.is_empty():
					continue
				var center: Vector2 = (climb.rest_points[0] + climb.rest_points[1]) * 0.5
				for tree in game.landscape.trees:
					check(absf(tree.p.x - center.x) > 70 or absf(tree.p.y - center.y) > 110,
						"Resting clearing opens naturally around the bench")
			for index in range(0, points.size() - 1, 7):
				game.player._segment = index
				game.player._distance = 0
				game.player.advance(0, 0)
				game.camera.snap_to_target()
				var size: Vector2 = root.get_visible_rect().size / game.camera.zoom
				var view := Rect2(game.camera.position - size * 0.5, size)
				if index % 49 == 0:
					for tree in game.landscape.foreground_trees:
						var frame: Rect2 = foreground.tree_rect(tree, game.camera.position)
						if not frame.intersects(view):
							continue
						visible_foreground += 1
						var body := Rect2(game.player.position + Vector2(-27, -68), Vector2(54, 86))
						if frame.intersects(body):
							check(foreground.foliage_opacity(frame) <= 0.06,
								"Foreground protects hiker, head and boots in both travel directions")
						for segment in range(0, points.size() - 1, 11):
							if frame.has_point(points[segment]):
								check(foreground.foliage_opacity(frame) <= 0.44,
									"Foreground route crossings stay translucent")
				for layer in range(5):
					check(backdrop.mountains[layer] == textures[layer],
						"Traversal and rebuild retain cached background assets")
			game.set_overview(true)
			check(game.camera.overview_enabled, "Map suppresses foreground grove drawing")
			game.set_overview(false)
			game.trail.generate(seed_value)
			check(game.trail.points == points, "Composition leaves deterministic geometry unchanged")
	check(personalities.size() == 3, "Gentle, steady and rugged routes covered")
	check(visible_foreground > 0, "Sparse near foreground is actually inside sampled viewports")
	print("PASS: %d background coverage, framing, cache and geometry checks; three sizes and personalities" % checks)
	game.free()
	quit(1 if failures else 0)
