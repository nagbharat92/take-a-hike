extends SceneTree

var game
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func gait_case(index: int, forward: bool, leg: int) -> void:
	var p = game.player
	var points: PackedVector2Array = game.trail.points
	p._segment = index
	p._distance = points[index].distance_to(points[index + 1]) * 0.5
	p.advance(0, 0)
	p._gait_direction = 1.0 if forward else -1.0
	p.phase = TAU * fposmod(0.08 - leg * 0.5, 1)
	var direction: float = signf(points[index + 1].x - points[index].x) * p._gait_direction
	var depth: bool = game.trail.segment_kinds[index] == "stairs"
	var controls := Vector2(0, p._gait_direction) if depth else Vector2(direction, 0)
	p.advance(controls.x, 0.001, controls.y)
	var anchor: Vector2 = p.global_position + p.foot_position(leg)
	var relative_before: Vector2 = p.foot_position(leg)
	var body_before: Vector2 = p.global_position
	for tick in range(12):
		p.advance(controls.x, 0.001, controls.y)
		check((p.global_position + p.foot_position(leg)).distance_to(anchor) < 0.002,
			"Planted boot stays fixed across route and tread/riser joins")
	var travel: Vector2 = p.global_position - body_before
	check((p.foot_position(leg) - relative_before).dot(travel) < 0,
		"Stance boot moves backward relative to actual travel")
	if not depth:
		check(p.facing == direction, "Profile face follows travel")
	p.phase = TAU * fposmod(0.6 - leg * 0.5, 1)
	var swing_before: Vector2 = p.foot_position(leg)
	body_before = p.global_position
	for tick in range(12):
		p.advance(controls.x, 0.001, controls.y)
	travel = p.global_position - body_before
	check((p.foot_position(leg) - swing_before).dot(travel) > 0,
		"Swing boot advances relative to actual travel")
	var facing_before: float = p.facing
	p.advance(0, 0)
	check(p.facing == facing_before, "Idle retains facing")

func run() -> void:
	root.size = Vector2i(1280, 720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.trail.generate(8)
	game._begin_hike()
	game.set_process(false)
	game.player.set_physics_process(false)
	for climb_index in [0, 1]:
		for forward in [true, false]:
			for leg in [0, 1]:
				gait_case(game.trail.climbs[climb_index].first_point + 4, forward, leg)
				gait_case(game.trail.stairs[climb_index].first + 34, forward, leg)
				gait_case(game.trail.stairs[climb_index].first + 35, forward, leg)
			var p = game.player
			p._segment = game.trail.stairs[climb_index].first + 34
			p._distance = 1
			p.advance(0, 0)
			p.moving = true
			p._gait_direction = 1 if forward else -1
			var poses: Dictionary = {}
			for frame in range(8):
				p.phase = TAU * frame / 8.0
				var feet: Array[Vector2] = []
				for leg in range(2):
					feet.append(Vector2(18, 58) + p.foot_position(leg) / p.PIXEL_SCALE)
				var image: Image = p.Art.hiker_legs(feet, frame * 2, 1 if forward else -1)
				poses[hash(image.get_data())] = true
			check(poses.size() == 8, "Eight distinct retargeted leg poses on both stair orientations and directions")
	var library = load("res://scripts/asset_library.gd")
	check(library.walk.size() == 6 and library.idle.size() == 4,
		"Actual imported Walk and Idle source frames are loaded")
	check(library.tree_frames.size() == 5, "Five actual authored forest silhouettes")
	for mode in ["idle", "walk", "back", "front"]:
		for frame in range(8):
			var anchors: Dictionary = library.attachment_anchors(frame, mode)
			var image: Image = library.hiker(frame, mode).get_image()
			var crown: Vector2i = anchors.crown
			var source_pose: int = frame % 4 if mode == "idle" else [0, 1, 2, 2, 3, 4, 5, 5][frame]
			var source: Image = library.idle[source_pose] if mode == "idle" else library.walk[source_pose]
			var expected_y: int = [7, 6, 6, 7][source_pose] if mode == "idle" else [8, 8, 7, 8, 8, 7][source_pose]
			check(anchors.source_head == Vector2i(22 if mode == "idle" else 28, expected_y),
				"Attachment follows measured source head, not an independent bob")
			check(source.get_region(Rect2i(anchors.source_head, Vector2i(7, 8))).get_used_rect().has_area(),
				"Measured head anchor contains original animated head pixels")
			check(image.get_pixelv(crown + Vector2i(4, 5)).is_equal_approx(Color("#29443f")),
				"Cap brim is rasterized on this frame's actual head")
			for y in range(6, 10):
				check(image.get_pixelv(crown + Vector2i(5, y)).a > 0.9,
					"No transparent gap between hat and animated head")
			check(anchors.shoulder - crown == Vector2i(-3, 12),
				"Backpack and cap share the same frame attachment transform")
			for facing in [-1, 1]:
				var cap_screen: Vector2 = Vector2(crown + Vector2i(4, 5)) * game.player.PIXEL_SCALE
				var head_screen: Vector2 = Vector2(crown + Vector2i(4, 8)) * game.player.PIXEL_SCALE
				cap_screen.x *= facing
				head_screen.x *= facing
				check(is_equal_approx(cap_screen.distance_to(head_screen), 3 * game.player.PIXEL_SCALE.y),
					"Profile flip preserves cap/head screen attachment in both directions")
	for tree in library.tree_frames:
		var still: Image = tree[0].get_image()
		var breeze: Image = tree[2].get_image()
		check(still.get_region(Rect2i(0, still.get_height() - 8, still.get_width(), 8)).get_data() ==
			breeze.get_region(Rect2i(0, breeze.get_height() - 8, breeze.get_width(), 8)).get_data(),
			"Breeze never moves imported tree roots")
		check(still.get_data() != breeze.get_data(), "Imported canopy visibly responds to breeze")
		var center: int = still.get_width() / 2
		check(still.get_region(Rect2i(center - 2, 0, 4, still.get_height())).get_data() ==
			breeze.get_region(Rect2i(center - 2, 0, 4, breeze.get_height())).get_data(),
			"Central trunk stays fixed, not a floating whole-tree texture")
	for variant in range(4):
		var still: Image = game.landscape.grass_frames[variant][0].get_image()
		var breeze: Image = game.landscape.grass_frames[variant][2].get_image()
		check(still.get_region(Rect2i(0, 15, 28, 1)).get_data() ==
			breeze.get_region(Rect2i(0, 15, 28, 1)).get_data(), "Grass roots stay fixed")
		check(still.get_data() != breeze.get_data(), "Grass blades move independently")
	var p = game.player
	for t in [0.15, 0.65]:
		p.moving = true
		p.phase = TAU * t
		var before: Vector2 = p.foot_position(0)
		p.phase += fposmod(PI - 2 * p.phase, TAU)
		p._gait_direction *= -1
		check(p.foot_position(0).distance_to(before) < 0.001, "Return pivot preserves foot pose")
	print("PASS: %d contact, swing, facing and return-pivot checks" % checks)
	game.free()
	quit()
