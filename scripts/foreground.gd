extends Node2D

const Art = preload("res://scripts/pixel_art.gd")
var banners: Array[Texture2D] = []
@onready var landscape = $"../Landscape"
@onready var player = $"../Player"
@onready var trail = $"../Trail"

func _ready() -> void:
	for frame in range(6):
		banners.append(Art.banner(frame))


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var end: Vector2 = trail.points[-1]
	draw_texture_rect(banners[int(player.elapsed * 6) % 6],
		Rect2(end + Vector2(37, -73), Vector2(28, 20)), false)
	for stair in trail.stairs:
		var camera: Camera2D = $"../Camera2D"
		var visible_size: Vector2 = get_viewport_rect().size / camera.zoom
		if not Rect2(camera.get_screen_center_position() - visible_size * 0.5,
				visible_size).intersects(Rect2(stair.lower[0], Vector2.ZERO).expand(
				stair.upper[-1]).grow(70)):
			continue
		for index in range(0, stair.steps.size(), 4):
			var p: Vector2 = stair.steps[index]
			# Far posts are in the landscape; near posts cover the walker at the edge.
			draw_line(p + Vector2(-32, 7), p + Vector2(-32, -18), Color("#384d40"), 4)
			draw_line(p + Vector2(-33, 5), p + Vector2(-33, -17), Color("#849271"), 1)
			draw_circle(p + Vector2(-32, -19), 3, Color("#a2a584"))
			if index + 4 < stair.steps.size():
				var next: Vector2 = stair.steps[index + 4]
				draw_line(p + Vector2(-32, -14), next + Vector2(-32, -14),
					Color("#76866a"), 2)
	var camera: Camera2D = $"../Camera2D"
	if camera.overview_enabled:
		return
	var size: Vector2 = get_viewport_rect().size / camera.zoom
	var center: Vector2 = camera.get_screen_center_position()
	var view := Rect2(center - size * 0.5, size)
	for tree in landscape.foreground_trees:
		var frame: Rect2 = tree_rect(tree, center)
		if not view.intersects(frame.grow(20)):
			continue
		var opacity: float = foliage_opacity(frame, tree.variant)
		var tint := Color("#657d68")
		tint.a = opacity
		var wind: int = 1 + roundi(sin(player.elapsed * 1.07 + tree.phase))
		draw_mesh(landscape.tree_meshes[tree.mesh_index], landscape.pine_frames[tree.variant][wind],
			Transform2D.IDENTITY, tint)


func tree_rect(tree: Dictionary, _center: Vector2) -> Rect2:
	# A grounded near tree shares the terrain transform. Only distant art has parallax.
	return landscape.Library.tree_rect(tree.p, tree.height, tree.variant)


func foliage_opacity(frame: Rect2, variant: int = -1) -> float:
	# A protected body/boot window also works while paused or standing on stairs.
	var body := Rect2(player.position + Vector2(-27, -68), Vector2(54, 86))
	if frame.intersects(body):
		if variant < 0:
			return 0.06
		var mask: Image = landscape.Library.tree_masks[variant]
		for x in range(5):
			for y in range(7):
				var point: Vector2 = body.position + body.size * Vector2(x / 4.0, y / 6.0)
				var uv: Vector2 = (point - frame.position) / frame.size
				var pixel := Vector2i(uv * Vector2(mask.get_size() + Vector2i(4, 0))) - Vector2i(2, 0)
				if pixel.x >= 0 and pixel.y >= 0 and pixel.x < mask.get_width() and pixel.y < mask.get_height():
					if mask.get_pixelv(pixel).a > 0.1:
						return 0.06
	var opacity: float = 1.0
	for index in range(trail.points.size() - 1):
		var a: Vector2 = trail.points[index]
		var b: Vector2 = trail.points[index + 1]
		if frame.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(16)):
			opacity = minf(opacity, 0.20 if trail.segment_kinds[index] == "stairs" else 0.44)
	return opacity
