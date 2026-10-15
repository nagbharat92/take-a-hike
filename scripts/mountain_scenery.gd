extends RefCounted

const Art = preload("res://scripts/pixel_art.gd")
const STYLE_NAMES = ["Needle spire", "Angular peak", "Broad dome", "Twin shoulder"]
const CACHE_LIMIT: int = 2
static var cache: Dictionary = {}
static var order: Array[int] = []
static var supporting_ranges: Dictionary = {}


static func recipe(hike_id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hike_id ^ 67867967
	return {"style": posmod(hike_id, STYLE_NAMES.size()),
		"center": rng.randf_range(665, 795), "width": rng.randf_range(0.93, 1.07),
		"height": rng.randf_range(0.94, 1.06), "shoulder": rng.randf_range(-12, 12),
		"phase": rng.randf_range(0, TAU)}


static func layers(hike_id: int) -> Array[Texture2D]:
	if cache.has(hike_id):
		return cache[hike_id]
	var result: Array[Texture2D] = []
	var design: Dictionary = recipe(hike_id)
	result.append(_raster(0, design))
	var family: int = design.style % 2
	if not supporting_ranges.has(family):
		var quiet: Dictionary = design.duplicate()
		quiet.phase = family * PI
		quiet.shoulder = 0
		var range_layers: Array[Texture2D] = []
		for layer in range(1, 5):
			range_layers.append(_raster(layer, quiet))
		supporting_ranges[family] = range_layers
	result.append_array(supporting_ranges[family])
	cache[hike_id] = result
	order.append(hike_id)
	while order.size() > CACHE_LIMIT:
		cache.erase(order.pop_front())
	return result


static func hero_profile(design: Dictionary) -> Array:
	# Common low shoulders keep the summit readable, not a row of equal peaks.
	var recipes: Array = [
		[[-270, 207], [-180, 181], [-101, 157], [-46, 128],
			[-18, 53], [-4, 29], [3, 39], [17, 99], [39, 145],
			[97, 172], [178, 184], [270, 211]],
		[[-290, 208], [-203, 179], [-132, 155], [-82, 109],
			[-29, 62], [0, 31], [24, 66], [55, 89], [72, 119],
			[142, 164], [208, 190], [290, 212]],
		[[-330, 211], [-270, 183], [-211, 137], [-155, 90],
			[-98, 60], [-47, 46], [0, 43], [54, 50], [111, 73],
			[171, 110], [223, 154], [278, 186], [330, 212]],
		[[-300, 210], [-223, 183], [-156, 133], [-103, 67],
			[-77, 42], [-47, 62], [-19, 95], [15, 85], [51, 52],
			[80, 37], [110, 64], [168, 148], [230, 188], [300, 211]]]
	var points: Array = []
	var source: Array = recipes[design.style]
	for index in range(source.size() - 1):
		var p: Array = source[index]
		var q: Array = source[index + 1]
		var count: int = maxi(1, ceili((q[0] - p[0]) / 6.0))
		for sample in range(count):
			var t: float = sample / float(count)
			# Dome slopes ease through every shoulder; crags keep their rock breaks.
			var y: float = lerpf(p[1], q[1], t)
			if design.style == 2:
				var previous: float = source[maxi(0, index - 1)][1]
				var following: float = source[mini(source.size() - 1, index + 2)][1]
				y = 0.5 * ((2 * p[1]) + (-previous + q[1]) * t
					+ (2 * previous - 5 * p[1] + 4 * q[1] - following) * t * t
					+ (-previous + 3 * p[1] - 3 * q[1] + following) * t * t * t)
			var x: float = lerpf(p[0], q[0], t)
			var roughness: float = sin(x * 0.049 + design.phase) * sin(PI * t)
			y += roughness * (0.6 if design.style == 2 else 1.7)
			points.append([roundi(design.center + x * design.width),
				roundi(214 - (214 - y) * design.height)])
	points.append([roundi(design.center + source[-1][0] * design.width), 212])
	return points


static func _raster(layer: int, design: Dictionary) -> ImageTexture:
	var art = Art.new(1536, 480)
	var bases: Array[String] = ["#92aaa0", "#a4b6ab", "#78988d", "#608379", "#4c7168"]
	var lights: Array[String] = ["#aebdad", "#b5c1b1", "#8ba392", "#739080", "#60816f"]
	var shadows: Array[String] = ["#809f96", "#98afa6", "#6d8e85", "#587d74", "#436b64"]
	var crest: Array = []
	if layer == 0:
		var hero: Array = hero_profile(design)
		crest = [[0, 222], [170, 198], [290, 213], [hero[0][0] - 35, 220]]
		crest.append_array(hero)
		crest.append_array([[hero[-1][0] + 65, 229], [1270, 203], [1400, 215], [1536, 226]])
	else:
		for x in range(0, 1537, 48):
			var y: float = 207 + layer * 37
			y += sin(x * (0.008 - layer * 0.0006) + design.phase + layer) * (18 - layer * 2)
			y += sin(x * 0.017 + design.phase * 0.7 + layer) * 5
			crest.append([x, roundi(y + design.shoulder)])
	var section: int = 0
	var base := Color(bases[layer])
	for x in range(1536):
		while section < crest.size() - 2 and x > crest[section + 1][0]:
			section += 1
		var p: Array = crest[section]
		var q: Array = crest[section + 1]
		var y: int = roundi(lerpf(p[1], q[1], (x - p[0]) / float(q[0] - p[0])))
		art.image.fill_rect(Rect2i(x, y, 1, 480 - y), base)
	# Faces share the silhouette exactly. Long ribs descend to quiet broad feet.
	var top_index: int = 0
	for index in range(crest.size()):
		if crest[index][1] < crest[top_index][1]:
			top_index = index
	if layer == 0:
		var peak: Array = crest[top_index]
		var lit: Array = crest.slice(maxi(0, top_index - 18), top_index + 1)
		lit.append_array([[peak[0] - 15, peak[1] + 48],
			[peak[0] - 40, peak[1] + 92], [peak[0] - 62, 192], [peak[0] - 151, 231]])
		art.poly(lit, lights[layer])
		var shade: Array = crest.slice(top_index, mini(crest.size(), top_index + 23))
		shade.append_array([[peak[0] + 155, 238], [peak[0] + 58, 191],
			[peak[0] + 37, peak[1] + 98], [peak[0] + 12, peak[1] + 56]])
		art.poly(shade, shadows[layer])
		for rib in range(3):
			var x: int = peak[0] - 28 - rib * 17
			var y: int = peak[1] + 90 + rib * 21
			art.line(x, y, x - 13, y + 18, lights[layer])
	else:
		for index in range(2, crest.size() - 3, 7):
			var plane: Array = crest.slice(index, index + 3)
			plane.append_array([[crest[index + 2][0] - 32, crest[index + 2][1] + 40],
				[crest[index][0] - 24, crest[index][1] + 61]])
			art.poly(plane, lights[layer])
	return art.texture()
