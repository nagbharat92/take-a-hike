extends SceneTree

var game
var checks: int = 0
var review: bool = false
var failures: int = 0

func _initialize() -> void:
	review = "--render-review" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 3:
			push_error("%s, viewport=%s window=%s" % [message, root.get_visible_rect().size, root.size])

func settle() -> void:
	for tick in range(100):
		game.camera._physics_process(0.016)

func capture(label: String) -> void:
	if not review:
		return
	game._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://builds/forest-review/%s.png" % label
	check(root.get_texture().get_image().save_png(path) == OK, "Viewport image saved")

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func native_input() -> void:
	var p = game.player
	place(4)
	p.set_physics_process(true)
	var before: Vector2 = p.position
	key(KEY_A, true)
	for i in range(5):
		await physics_frame
	key(KEY_A, false)
	check(p.position.x < before.x, "Native A input drives profile walking")
	p.set_physics_process(false)
	place(game.trail.stairs[0].first + 34)
	for code in [KEY_W, KEY_S]:
		before = p.position
		p.set_physics_process(true)
		key(code, true)
		for i in range(5):
			await physics_frame
		key(code, false)
		check(p.position.y < before.y if code == KEY_W else p.position.y > before.y,
			"Native W/S inputs ascend and descend real stairs")
		check(p.depth_facing == (1 if code == KEY_W else -1), "Depth pose follows native input")
		p.set_physics_process(false)
		game.camera.snap_to_target()
		await capture("native-%s" % code)
	p.reset()
	p.set_physics_process(false)

func place(index: int, fraction: float = 0.5) -> void:
	game.player._segment = index
	game.player._distance = game.trail.points[index].distance_to(
		game.trail.points[index + 1]) * fraction
	game.player.advance(0, 0)
	game.camera.snap_to_target()
	game._process(0)


func direct_transition(enabled: bool) -> void:
	var camera = game.camera
	var probes: Array[Vector2] = [game.player.position, game.trail.points[0], game.trail.points[-1]]
	var starts: Array[Vector2] = []
	for point in probes:
		starts.append((point - camera.position) * camera.zoom)
	game.set_overview(enabled)
	var ends: Array[Vector2] = []
	for point in probes:
		ends.append((point - camera._transition_destination) * camera._transition_destination_zoom)
	for tick in range(45):
		camera._physics_process(0.016)
		var weight: float = smoothstep(0, 1, camera._transition_time / camera.TRANSITION_SECONDS)
		for index in range(probes.size()):
			var actual: Vector2 = (probes[index] - camera.position) * camera.zoom
			check(actual.distance_to(starts[index].lerp(ends[index], weight)) < 0.02,
				"Every focal probe follows a direct screen-space path with synchronized scale")
		if review and tick in [8, 22, 36]:
			await capture("zoom-%s-%02d" % [enabled, tick])
	check(not camera.transitioning, "Deliberate view transition finishes exactly")


func stationary_reset(message: String) -> void:
	check(not game.camera.transitioning, message + " is settled immediately")
	check(not game.player.visible and not game.player.is_physics_processing(),
		message + " keeps overview hiker hidden and paused")
	var position: Vector2 = game.camera.position
	var zoom: Vector2 = game.camera.zoom
	for tick in range(40):
		game.camera._physics_process(0.016)
		check(game.camera.position == position and game.camera.zoom == zoom,
			message + " has no drift on following frames")

func run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://builds/forest-review")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.camera.set_physics_process(false)
	game.player.set_physics_process(false)
	for seed_value in range(1, 11):
		game.trail.generate(seed_value)
		game._begin_hike()
		game.camera.set_physics_process(false)
		game.player.set_physics_process(false)
		var original: PackedVector2Array = game.trail.points.duplicate()
		game.camera.snap_to_target()
		game._process(0)
		if review and seed_value == 8:
			await native_input()
			game.camera.snap_to_target()
		await capture("%02d-trailhead" % seed_value)
		var start: Vector2 = game.player.position
		var before: Vector2 = game.camera.position
		var before_zoom: Vector2 = game.camera.zoom
		game.player.set_physics_process(true)
		game.set_overview(true)
		game._process(0)
		check(game.camera.position == before and game.camera.zoom == before_zoom,
			"Mode switch does not snap")
		check(not game.player.visible and not game.player.is_physics_processing(),
			"Overview hides and pauses player")
		game.camera._physics_process(0.12)
		before = game.camera.position
		before_zoom = game.camera.zoom
		game.set_overview(false)
		check(game.player.is_physics_processing(), "Return resumes active walking")
		game._process(0)
		game.player.set_physics_process(false)
		check(game.camera.position == before and game.camera.zoom == before_zoom,
			"Interrupted transition starts at its displayed transform")
		game.set_overview(true)
		settle()
		for point in original:
			var screen: Vector2 = (point - game.camera.position) * game.camera.zoom + Vector2(root.size) * 0.5
			check(screen.x >= 340 and screen.x <= root.size.x - 20 and
				screen.y >= 40 and screen.y <= root.size.y - 90,
				"Entire route fits clear of UI")
		await capture("%02d-overview" % seed_value)
		for steps in [-100.0, 200.0]:
			game.camera.manual_zoom(steps)
			settle()
			check(game.camera.map_scale >= 0.65 and game.camera.map_scale <= 2.5,
				"Map zoom is bounded")
		game.camera.map_scale = 1
		for size in [Vector2i(960, 720), Vector2i(1600, 900), Vector2i(1280, 720)]:
			root.size = size
			await process_frame
			settle()
			check(game.camera.zoom.is_finite() and game.camera.position.is_finite(),
				"Resize remains finite")
			for point in original:
				var logical: Vector2 = root.get_visible_rect().size
				var screen: Vector2 = (point - game.camera.position) * game.camera.zoom + logical * 0.5
				check(screen.x > 330 and screen.x < logical.x and screen.y > 0 and screen.y < logical.y - 65,
					"Resized overview clears controls")
		game.replay_hike()
		stationary_reset("Overview Replay")
		game.camera.set_physics_process(false)
		game.player.set_physics_process(false)
		check(game.overview and game.camera.overview_enabled, "Replay retains overview")
		game.set_overview(false)
		game.player.set_physics_process(false)
		settle()
		check(game.player.position == start and game.player.visible, "Same-position return")
		for steps in [-100.0, 200.0]:
			game.camera.manual_zoom(steps)
			settle()
			check(game.camera.close_scale >= 1.25 and game.camera.close_scale <= 3.5,
				"Trail zoom is bounded")
		game.camera.close_scale = 2.2
		settle()
		# Full forward and reverse traversal uses the actual route intents.
		for forward in [true, false]:
			var ticks: int = 0
			while ticks < 3000:
				var p = game.player
				var segment: int = p._segment
				var sign_value: float = 1 if forward else -1
				var stairs: bool = game.trail.segment_kinds[segment] == "stairs"
				var horizontal: float = signf(original[segment + 1].x - original[segment].x) * sign_value
				p.advance(0 if stairs else horizontal, 0.20, sign_value if stairs else 0)
				# At a mode boundary the next section needs its own input.
				var next: int = segment + (1 if forward else -1)
				var length: float = original[p._segment].distance_to(original[p._segment + 1])
				if (p._distance >= length - 0.001 if forward else p._distance <= 0.001) and \
						next >= 0 and next < game.trail.segment_kinds.size():
					stairs = game.trail.segment_kinds[next] == "stairs"
					horizontal = signf(original[next + 1].x - original[next].x) * sign_value
					p.advance(0 if stairs else horizontal, 0.01, sign_value if stairs else 0)
				ticks += 1
				if (forward and p.at_summit()) or (not forward and p._segment == 0 and p._distance <= 0.001):
					break
			check(ticks < 3000, "Complete route traversable in both directions")
		check(game.player.position.distance_to(original[0]) < 0.01, "Return reaches trailhead")
		check(game.trail.points == original, "Presentation preserves route geometry")
		if seed_value in [1, 2, 8]:
			for climb_index in range(game.trail.climbs.size()):
				var climb = game.trail.climbs[climb_index]
				if not climb.rest_points.is_empty():
					var mid: Vector2 = (climb.rest_points[0] + climb.rest_points[1]) * 0.5
					var nearest: int = climb.first_point
					for index in range(climb.first_point, climb.last_point):
						if original[index].distance_to(mid) < original[nearest].distance_to(mid):
							nearest = index
					place(nearest)
					await capture("%02d-rest-%d" % [seed_value, climb_index])
				for fraction in [0.18, 0.48, 0.78]:
					place(clampi(climb.first_point + int((climb.last_point - climb.first_point) * fraction),
						climb.first_point, climb.last_point - 1))
					await capture("%02d-woodland-%d-%02d" % [seed_value, climb_index, int(fraction * 100)])
			for stairs_index in range(mini(2, game.trail.stairs.size())):
				var stair: Dictionary = game.trail.stairs[stairs_index]
				for sample in [0, 34, 69]:
					place(mini(stair.first + sample, stair.last - 1))
					game.player.advance(0, 0.012, 1)
					await capture("%02d-stair-%d-%d" % [seed_value, stairs_index, sample])
				game.player.advance(0, 0.012, -1)
				await capture("%02d-stair-%d-descend" % [seed_value, stairs_index])
			place(original.size() - 2, 0.98)
			await capture("%02d-summit" % seed_value)
			if review and seed_value == 8:
				place(game.trail.climbs[0].first_point + 4)
				game._process(0)
				var hover: Button = game.bottom.get_child(2)
				Input.warp_mouse(hover.get_global_rect().get_center())
				var motion := InputEventMouseMotion.new()
				motion.position = hover.get_global_rect().get_center()
				motion.global_position = motion.position
				Input.parse_input_event(motion)
				await process_frame
				await process_frame
				check(hover.is_hovered(), "Native pointer activates actual hover state")
				await capture("08-ui-hover")
				game.toggle_pause()
				await capture("08-paused")
				game.resume_hike()
				game.player.set_physics_process(false)
	var completed_before: int = game.completed_count
	place(game.trail.points.size() - 2, 1.0)
	game._process(0)
	check(game.state == game.State.COMPLETE and game.pause_button.disabled,
		"Summit completes and disables pause")
	game.complete_hike()
	check(game.completed_count == completed_before + 1, "Completion is idempotent")
	await capture("complete")
	game.replay_hike()
	check(game.state == game.State.HIKE and not game.paused, "Replay returns to active hike")
	game.toggle_pause()
	check(game.paused and not game.player.is_physics_processing(), "Pause stops movement")
	game.toggle_credits()
	check(game.credits.visible and game.paused, "Credits open without resuming the hike")
	check("rvros" in game.credits.text and "Anokolisa" in game.credits.text
		and "Lynn Evers" in game.credits.text and "HungryProton" in game.credits.text,
		"Credits name all imported artwork and Scatter2D authors")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_key_input(escape)
	check(not game.credits.visible and game.paused, "Escape closes credits before resuming")
	game.toggle_credits()
	game.resume_hike()
	check(not game.paused and game.player.is_physics_processing()
		and not game.credits.visible, "Resume restores movement and closes credits")
	game.player.set_physics_process(false)
	if review:
		var frame_times: Array[float] = []
		for sample in range(45):
			var started: int = Time.get_ticks_usec()
			await process_frame
			await RenderingServer.frame_post_draw
			frame_times.append((Time.get_ticks_usec() - started) / 1000.0)
		frame_times.sort()
		print("Native steady viewport sample: median %.2f ms, max %.2f ms, %d draw calls" %
			[frame_times[22], frame_times[-1], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	game.set_overview(true)
	settle()
	await direct_transition(false)
	await direct_transition(true)
	game.camera.manual_zoom(1)
	var map_zoom: float = game.camera.map_scale
	game.replay_hike()
	stationary_reset("Manually zoomed overview Replay")
	check(game.camera.map_scale == map_zoom, "Replay retains intentional manual map zoom")
	game.new_hike()
	stationary_reset("Overview New hike")
	check(game.camera.map_scale == map_zoom, "New hike retains intentional manual map zoom")
	game.camera.set_physics_process(false)
	game.player.set_physics_process(false)
	check(game.overview and game.camera.overview_enabled, "New hike retains overview")
	check(game.summary.text.find("seed") < 0 and game.subtitle.text.find("scale") < 0,
		"Main UI excludes technical details")
	print("%s: %d presentation checks, %d failures; ten complete reversible hikes, zoom, interruption, resize and fit" %
		["PASS" if failures == 0 else "FAIL", checks, failures])
	game.free()
	quit(0 if failures == 0 else 1)
