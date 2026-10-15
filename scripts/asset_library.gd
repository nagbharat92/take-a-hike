extends RefCounted

static var tree_frames: Array = []
static var tree_masks: Array[Image] = []
static var tree_roots: Array[Vector2] = []
static var tree_root_spans: Array[float] = []
static var tree_used_heights: Array[float] = []
static var canopy: Texture2D
static var walk: Array[Image] = []
static var idle: Array[Image] = []
static var bodies: Dictionary = {}
const WALK_POSES: Array[int] = [0, 1, 2, 2, 3, 4, 5, 5]
# Authored head crowns in the original 50x37 sheets, including actual pose rise.
const IDLE_HEADS: Array[Vector2i] = [
	Vector2i(22, 7), Vector2i(22, 6), Vector2i(22, 6), Vector2i(22, 7)]
const WALK_HEADS: Array[Vector2i] = [
	Vector2i(28, 8), Vector2i(28, 8), Vector2i(28, 7),
	Vector2i(28, 8), Vector2i(28, 8), Vector2i(28, 7)]


static func attachment_anchors(frame: int, mode: String) -> Dictionary:
	var pose: int = frame % 4 if mode == "idle" else WALK_POSES[frame % 8]
	var head: Vector2i = IDLE_HEADS[pose] if mode == "idle" else WALK_HEADS[pose]
	var crop_x: int = 15 if mode == "idle" else 21
	var crown := Vector2i(3 + roundi((head.x - crop_x) * 30.0 / 22.0),
		9 + roundi((head.y - 6) * 30.0 / 21.0))
	return {"source_head": head, "crop_x": crop_x, "crown": crown,
		"shoulder": crown + Vector2i(-3, 12)}


static func prepare() -> void:
	if not tree_frames.is_empty():
		return
	for variant in range(5):
		var source: Image = load("res://assets/forest/tree-%d.png" % variant).get_image()
		source.convert(Image.FORMAT_RGBA8)
		tree_masks.append(source)
		var used: Rect2i = source.get_used_rect()
		tree_used_heights.append(float(used.size.y))
		var root_x: Array[int] = []
		for x in range(source.get_width()):
			if source.get_pixel(x, used.end.y - 1).a > 0.5:
				root_x.append(x)
		var anchor := Vector2((root_x[0] + root_x[-1]) * 0.5 + 2.5, used.end.y - 0.5)
		tree_roots.append(anchor)
		var root_span: float = 0
		for y in range(used.end.y - 2, used.end.y):
			for x in range(source.get_width()):
				if source.get_pixel(x, y).a > 0.5:
					root_span = maxf(root_span, absf(x + 2.5 - anchor.x) + 0.5)
		tree_root_spans.append(root_span)
		var frames: Array[Texture2D] = []
		for wind in [-1, 0, 1]:
			var image := Image.create(source.get_width() + 4, source.get_height(),
				false, Image.FORMAT_RGBA8)
			for y in range(source.get_height()):
				for x in range(source.get_width()):
					var pixel: Color = source.get_pixel(x, y)
					if pixel.a == 0:
						continue
					var foliage: bool = pixel.g > pixel.r * 1.14 and pixel.g > pixel.b * 1.06
					var offset: int = 0
					if foliage and absf(x - source.get_width() * 0.5) > 5:
						offset = roundi(wind * pow(1.0 - float(y) / source.get_height(), 1.8))
					image.set_pixel(x + 2 + offset, y, pixel)
			frames.append(ImageTexture.create_from_image(image))
		tree_frames.append(frames)
	canopy = load("res://assets/forest/canopy.png")
	for i in range(6):
		walk.append(load("res://assets/hiker/walk-%d.png" % i).get_image())
	for i in range(4):
		idle.append(load("res://assets/hiker/idle-%d.png" % i).get_image())


static func tree_rect(root: Vector2, height: float, variant: int) -> Rect2:
	var size: Vector2 = tree_frames[variant][0].get_size()
	var scale_value: float = height / tree_used_heights[variant]
	return Rect2(root - tree_roots[variant] * scale_value, size * scale_value)


static func tree_footprint(height: float, variant: int) -> Vector2:
	var scale_value: float = height / tree_used_heights[variant]
	return Vector2(tree_root_spans[variant] * scale_value, scale_value)


static func tree_root_offset(height: float, variant: int) -> Vector2:
	# Anchor is the last opaque row's center; two root rows extend mostly upward.
	return Vector2(0, -0.5 * height / tree_used_heights[variant])


static func grounded_tree_pixel(pixel: Vector2, root: Vector2, height: float,
		variant: int, gradient: float) -> Vector2:
	# Only the lowest trunk conforms to the ground plane. The upper tree keeps
	# its authored upright silhouette, and this mesh never depends on wind.
	var scale_value: float = height / tree_used_heights[variant]
	var weight: float = clampf((pixel.y - root.y + 12 * scale_value) / (9 * scale_value), 0, 1)
	return pixel + Vector2(0, (pixel.x - root.x) * gradient * weight)


static func tree_mesh(root: Vector2, height: float, variant: int, gradient: float) -> ArrayMesh:
	var frame: Rect2 = tree_rect(root, height, variant)
	var size: Vector2 = tree_frames[variant][0].get_size()
	var anchor: Vector2 = tree_roots[variant]
	var scale_value: float = height / tree_used_heights[variant]
	var columns: Array[float] = [0, anchor.x - tree_root_spans[variant] - 2,
		anchor.x, anchor.x + tree_root_spans[variant] + 2, size.x]
	var rows: Array[float] = [0, anchor.y - 12, anchor.y - 3, size.y]
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for y in rows:
		for x in columns:
			var point: Vector2 = grounded_tree_pixel(frame.position + Vector2(x, y) * scale_value,
				root, height, variant, gradient)
			vertices.append(Vector3(point.x, point.y, 0))
			uv.append(Vector2(x, y) / size)
	for y in range(rows.size() - 1):
		for x in range(columns.size() - 1):
			var index: int = y * columns.size() + x
			indices.append_array(PackedInt32Array([index, index + 1, index + columns.size(),
				index + 1, index + columns.size() + 1, index + columns.size()]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func hiker(frame: int, mode: String) -> Texture2D:
	prepare()
	var key := "%s-%d" % [mode, frame]
	if bodies.has(key):
		return bodies[key]
	var source: Image = idle[frame % 4] if mode == "idle" else walk[WALK_POSES[frame % 8]]
	source = source.duplicate()
	source.convert(Image.FORMAT_RGBA8)
	# Crop above the hips: source knees are retargeted to planted route contacts.
	var anchors: Dictionary = attachment_anchors(frame, mode)
	# Normalize the six-pixel horizontal difference between source Idle and Walk.
	# Remove the source sword above the far shoulder, not the animated head.
	for y in range(6, 16):
		for x in range(anchors.source_head.x - 4):
			source.set_pixel(x, y, Color.TRANSPARENT)
	var torso: Image = source.get_region(Rect2i(anchors.crop_x, 6, 22, 21))
	torso.resize(30, 30, Image.INTERPOLATE_NEAREST)
	var art = preload("res://scripts/pixel_art.gd").new(36, 60)
	art.image.blit_rect(torso, Rect2i(0, 0, 30, 30), Vector2i(3, 9))
	var crown: Vector2i = anchors.crown
	var head_x: int = crown.x
	var head_y: int = crown.y
	if mode == "back":
		art.box(head_x, head_y, 11, 12, "#00000000")
		art.box(head_x + 1, head_y + 3, 9, 8, "#4a5145")
		art.box(head_x + 2, head_y + 3, 7, 3, "#79785a")
	elif mode == "front":
		art.box(head_x, head_y, 11, 12, "#00000000")
		art.box(head_x + 1, head_y + 3, 8, 8, "#d8ab7c")
		art.dot(head_x + 2, head_y + 5, "#263f42")
		art.dot(head_x + 7, head_y + 5, "#263f42")
		art.box(head_x + 4, head_y + 9, 3, 1, "#9a6b51")
	if mode != "front":
		preload("res://scripts/pixel_art.gd")._hiker_pack(art,
			anchors.shoulder.x if mode != "back" else head_x + 1,
			anchors.shoulder.y, frame)
	else:
		art.line(head_x + 1, head_y + 16, head_x + 2, head_y + 27, "#b9ac7a", 2)
		art.line(head_x + 10, head_y + 16, head_x + 9, head_y + 27, "#b9ac7a", 2)
	art.poly([[head_x, head_y + 1], [head_x + 7, head_y],
		[head_x + 11, head_y + 5], [head_x - 1, head_y + 5]], "#4b7065")
	art.box(head_x + 2, head_y + 1, 5, 2, "#92a28a")
	art.box(head_x - 2, head_y + 5, 15, 2, "#29443f")
	bodies[key] = art.texture()
	return bodies[key]


static func panel(pressed: bool = false) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://assets/vendor/kenney/9-Slice/Ancient/grey%s.png" %
		("_pressed" if pressed else ""))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 12)
		style.set_content_margin(side, 16 if side in [SIDE_LEFT, SIDE_RIGHT] else 12)
	style.modulate_color = Color("#547367") if not pressed else Color("#819877")
	return style
