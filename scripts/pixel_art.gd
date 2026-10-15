extends RefCounted

# Original raster artwork. All coordinates are source pixels, never filtered vectors.
var image: Image
var origin := Vector2i.ZERO


func _init(width: int = 32, height: int = 56) -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)


func dot(x: int, y: int, color: String) -> void:
	var p := Vector2i(x, y) + origin
	if p.x >= 0 and p.y >= 0 and p.x < image.get_width() and p.y < image.get_height():
		image.set_pixelv(p, Color(color))


func box(x: int, y: int, w: int, h: int, color: String) -> void:
	var rect := Rect2i(Vector2i(x, y) + origin, Vector2i(w, h))
	rect = rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if rect.has_area():
		image.fill_rect(rect, Color(color))


func line(x: int, y: int, ex: int, ey: int, color: String, width: int = 1) -> void:
	var distance: int = maxi(absi(ex - x), absi(ey - y))
	for i in range(distance + 1):
		var t: float = float(i) / maxi(1, distance)
		box(roundi(lerpf(x, ex, t)), roundi(lerpf(y, ey, t)), width, width, color)


func poly(points: Array, color: String) -> void:
	var low: int = points[0][1]
	var high: int = low
	for p in points:
		low = mini(low, p[1])
		high = maxi(high, p[1])
	for y in range(low, high + 1):
		var crossings: Array[float] = []
		for i in range(points.size()):
			var a: Array = points[i]
			var b: Array = points[(i + 1) % points.size()]
			if (a[1] <= y and b[1] > y) or (b[1] <= y and a[1] > y):
				crossings.append(a[0] + float(y - a[1]) / (b[1] - a[1]) * (b[0] - a[0]))
		crossings.sort()
		for i in range(0, crossings.size() - 1, 2):
			box(ceili(crossings[i]), y, floori(crossings[i + 1]) - ceili(crossings[i]) + 1, 1, color)


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)


static func hiker_legs(feet: Array[Vector2], frame: int, facing: float) -> Image:
	var a = new(72, 96)
	a.origin = Vector2i(18, 16)
	var hip: int = 42 - [0, 1, 2, 1, 0, 1, 2, 1][frame / 2]
	for leg in range(2):
		var foot := Vector2i(feet[leg].round())
		var hip_position := Vector2(17 + leg * 3, hip)
		var ankle := Vector2(foot) - Vector2(0, 2)
		var direction: Vector2 = ankle - hip_position
		var reach: float = minf(direction.length(), 23.9)
		var bend: float = minf(4.0, sqrt(maxf(0, 10.0 * 10.0 - reach * reach * 0.25)))
		var knee := Vector2i((hip_position + direction * 0.5 +
			Vector2(direction.y, -direction.x).normalized() * bend * facing).round())
		a.poly([[14 + leg * 3, hip], [19 + leg * 3, hip], [knee.x + 3, knee.y],
			[foot.x + 2, foot.y - 2], [foot.x - 2, foot.y - 2],
			[knee.x - 1, knee.y]], "#243b49" if leg == 0 else "#344e59")
		a.line(16 + leg * 3, hip + 2, knee.x, knee.y, "#617271")
		a.box(foot.x - 3, foot.y - 3, 7, 3, "#252d32")
		a.box(foot.x - 2, foot.y - 3, 4, 1, "#9b8465")
		a.box(foot.x - 4, foot.y, 8, 1, "#172831")
		a.dot(foot.x + roundi(facing * 3), foot.y - 2, "#d1b58a")
	return a.image


static func hiker(frame: int, mode: String) -> ImageTexture:
	var a = new(36, 60)
	frame = frame / 2
	var swing: Array[int] = [-5, -3, 0, 3, 5, 3, 0, -3]
	var bob: int = [0, 1, 2, 1, 0, 1, 2, 1][frame]
	var step: int = -swing[frame] if mode != "idle" else 1
	var climbing: bool = mode == "back" or mode == "front"
	if mode == "idle":
		bob = 1 if frame in [3, 4] else 0
	var lean: int = 1 if climbing else 0
	var y: int = 21 - bob
	if mode == "front":
		_hiker_pack(a, 13, y, frame)
	# Far hand, jacket side, fabric planes and seams.
	a.line(20 + lean, y + 4, 17 - roundi(step * 0.5), y + 17, "#6b6460", 3)
	a.poly([[14 + lean, y], [22 + lean, y + 1], [24, y + 17],
		[20, y + 22], [12, y + 20], [12, y + 6]], "#263f47")
	a.poly([[15 + lean, y + 1], [21 + lean, y + 2], [22, y + 16],
		[19, y + 20], [14, y + 18]], "#729991")
	a.box(15, y + 4, 3, 10, "#9cb5a0")
	a.line(20, y + 5, 20, y + 15, "#50766e")
	a.box(15, y + 17, 7, 2, "#44675f")
	a.dot(19, y + 8, "#c6c8a6")
	a.box(19, y + 16, 2, 2, "#d9bc79")
	# Head has hair, ear, nose, eye, cheek and a sunlit hat brim.
	a.poly([[15 + lean, 10 - bob], [22 + lean, 10 - bob], [23 + lean, 17 - bob],
		[21 + lean, 21 - bob], [16 + lean, 20 - bob]], "#ad795e")
	a.box(18 + lean, 12 - bob, 5, 6, "#e6ba86")
	a.box(21 + lean, 14 - bob, 4, 3, "#efc792")
	a.box(15 + lean, 11 - bob, 3, 7, "#4a3f3c")
	a.box(17 + lean, 16 - bob, 2, 2, "#d9a378")
	a.dot(22 + lean, 13 - bob, "#23343b")
	a.box(20 + lean, 18 - bob, 3, 1, "#8e5d4f")
	a.poly([[14 + lean, 7 - bob], [21 + lean, 6 - bob], [24 + lean, 11 - bob],
		[13 + lean, 12 - bob]], "#476b64")
	a.box(16 + lean, 7 - bob, 5, 2, "#819781")
	a.box(12 + lean, 11 - bob, 15, 2, "#263f42")
	a.box(19 + lean, 10 - bob, 6, 1, "#b7b38b")
	if mode == "back":
		a.box(14, 13 - bob, 12, 8, "#00000000")
		a.poly([[15, 13 - bob], [23, 13 - bob], [23, 18 - bob],
			[21, 20 - bob], [17, 19 - bob]], "#49483f")
		a.box(17, 14 - bob, 5, 2, "#746247")
		a.box(15, 16 - bob, 2, 2, "#d8a67d")
		a.box(23, 16 - bob, 1, 2, "#d8a67d")
		a.box(19, 19 - bob, 3, 2, "#ba8d68")
	elif mode == "front":
		a.box(15, 13 - bob, 10, 8, "#00000000")
		a.box(16, 13 - bob, 7, 6, "#e6ba86")
		a.dot(17, 14 - bob, "#273c41")
		a.dot(22, 14 - bob, "#273c41")
		a.box(19, 15 - bob, 1, 2, "#b9805d")
		a.box(18, 18 - bob, 4, 1, "#a26e53")
	var arm: int = roundi(step * 0.6)
	a.line(22, y + 4, 24 + arm, y + 11, "#4a776e", 3)
	a.line(24 + arm, y + 11, 23 + arm, y + 17, "#a9baa0", 2)
	a.box(23 + arm, y + 17, 3, 3, "#dfb084")
	# Pack lid, stitched pocket, straps, buckles and rolled blanket.
	var pack_x: int = 9 + (1 if frame in [2, 3, 6, 7] else 0)
	if climbing:
		pack_x = 13
	if mode != "front":
		_hiker_pack(a, pack_x, y, frame)
	a.box(15, y - 1, 9, 2, "#cf7754")
	a.line(14, y, 6, y + 2 + (frame % 3), "#ad5945", 2)
	a.line(7, y + 2 + (frame % 3), 3, y + (frame % 2), "#e49d69")
	return a.texture()


static func _hiker_pack(a, pack_x: int, y: int, _frame: int) -> void:
	a.poly([[pack_x, y + 1], [pack_x + 6, y], [pack_x + 9, y + 5],
		[pack_x + 8, y + 18], [pack_x + 1, y + 19], [pack_x - 1, y + 14]], "#443f3a")
	a.box(pack_x, y + 3, 7, 12, "#ac754c")
	a.box(pack_x + 1, y + 2, 5, 2, "#d0a16b")
	a.box(pack_x, y + 10, 6, 5, "#805a40")
	a.line(pack_x + 1, y + 10, pack_x + 5, y + 10, "#c39661")
	a.box(pack_x + 2, y + 4, 1, 12, "#dac494")
	a.box(pack_x + 2, y + 8, 2, 2, "#293c3e")
	a.box(pack_x - 2, y - 2, 10, 4, "#53746d")
	a.box(pack_x - 1, y - 2, 8, 1, "#abc0a3")
	a.box(pack_x, y - 2, 1, 4, "#d8bc82")
	a.box(pack_x + 5, y - 2, 1, 4, "#d8bc82")


static func pine(variant: int, breeze: int = 0) -> ImageTexture:
	var a = new(64, 192)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6703 + variant * 137
	a.poly([[30, 191], [31, 7], [33, 4], [35, 191]], "#293d3c")
	a.line(33, 77, 33, 189, "#876e50", 2)
	a.line(31, 150, 31, 190, "#48564a")
	for whorl in range(13, -1, -1):
		var y: int = 12 + whorl * 12
		var span: int = 2 + whorl * 2
		var bend: int = roundi(breeze * (1.0 - whorl / 16.0))
		for side in [-1, 1]:
			var end_x: int = 32 + side * span + bend
			var end_y: int = y + rng.randi_range(7, 12)
			a.line(32, y, end_x, end_y, "#384c40", 2)
			for branch in range(3):
				var t: float = branch / 2.0
				var x: int = roundi(lerpf(32, end_x, t))
				var by: int = roundi(lerpf(y, end_y, t))
				var w: int = rng.randi_range(4, 7)
				var h: int = rng.randi_range(7, 12)
				var shade: String = "#24423e" if side > 0 else "#315c4d"
				a.poly([[x - w, by + 3], [x - w + 2, by - 2], [x - 2, by - h + 3],
					[x, by - h], [x + 3, by - h + 5], [x + w, by + 2],
					[x + w - 2, by + 6], [x, by + 4]], shade)
				a.poly([[x - w + 1, by - 1], [x - 2, by - h + 3], [x, by - h],
					[x + 2, by - 5], [x - 1, by - 2]],
					"#53775a" if side < 0 else "#3c624e")
				if side < 0 and (branch + whorl) % 3 == 0:
					a.box(x - 2, by - h + 4, 3, 2, "#7d9363")
				a.box(x + 2, by + 1, 3, 2, "#24423e")
	return a.texture()


static func rock(variant: int) -> ImageTexture:
	var a = new(48, 32)
	var crowns: Array = [
		[[3, 23], [9, 12], [18, 7], [31, 6], [40, 14], [44, 25], [30, 29], [9, 28]],
		[[2, 24], [7, 17], [19, 14], [28, 9], [39, 11], [46, 24], [34, 28], [12, 28]],
		[[6, 26], [10, 9], [19, 3], [28, 4], [35, 14], [41, 25], [28, 30], [12, 29]],
		[[2, 25], [6, 16], [15, 10], [27, 11], [35, 17], [44, 18], [47, 26], [25, 29]]]
	var crown: Array = crowns[variant % 4]
	a.poly(crown, "#3c514c")
	a.poly([crown[0], crown[1], crown[2], crown[3], [26, 18], [14, 23]], "#8a9681")
	a.poly([crown[3], crown[4], crown[5], crown[6], [24, 24], [26, 18]], "#657b6c")
	a.line(crown[1][0], crown[1][1], crown[2][0], crown[2][1], "#b1b297")
	a.line(crown[2][0], crown[2][1], crown[3][0] - 2, crown[3][1], "#a3ad90")
	a.line(12, 20, 24, 18, "#6f816e")
	a.line(26, 18, 30, 23, "#486154")
	# Moss sits in one sheltered seam, rather than a repeated fringe.
	a.box(9 + variant * 3, 25, 12, 3, "#4b674b")
	a.box(10 + variant * 3, 24, 6, 1, "#899565")
	return a.texture()


static func fern(variant: int, breeze: int = 0) -> ImageTexture:
	var a = new(48, 32)
	a.line(24, 31, 24, 27, "#587d52")
	for side in [-1, 1]:
		for stem in range(3):
			var ex: int = 24 + side * (10 + stem * 5) + breeze
			var ey: int = 4 + stem * 5
			a.line(24, 27, ex, ey, "#587d52")
			for leaf in range(1, 7):
				var t: float = leaf / 8.0
				var x: int = roundi(lerpf(24, ex, t))
				var y: int = roundi(lerpf(27, ey, t))
				a.line(x, y, x + side * (5 - leaf / 2), y - 3, "#8caa6c" if stem == 0 else "#426d52", 2)
				a.line(x, y, x - side * 3, y - 4, "#618f5a", 2)
	if variant % 3 == 0:
		a.line(24, 30, 26, 13, "#9ca66a")
		a.box(24, 11, 4, 3, "#e6c58b")
	return a.texture()


static func grass(variant: int, breeze: int = 0) -> ImageTexture:
	var a = new(28, 16)
	for blade in range(7):
		var root: int = 5 + blade * 3
		var height: int = 5 + posmod(blade * 7 + variant * 3, 9)
		var lean: int = posmod(blade * 5 + variant, 7) - 3
		a.line(root, 15, root + lean, 15 - height / 2, "#42654c")
		a.line(root + lean, 15 - height / 2, root + lean * 2 + breeze,
			15 - height, "#79915e" if blade % 3 == 0 else "#547c52")
	a.box(4, 15, 22, 1, "#405b43")
	return a.texture()


static func mountain_layer(layer: int) -> ImageTexture:
	var a = new(1536, 480)
	var bases: Array[String] = ["#a4b6ab", "#8fa89e", "#78988d", "#608379", "#4c7168"]
	var lights: Array[String] = ["#b8c3b2", "#a3b6a6", "#8ba392", "#739080", "#60816f"]
	var shadows: Array[String] = ["#9cb0a7", "#839f97", "#6d8e85", "#587d74", "#436b64"]
	# Authored shoulders, saddles, broken summits and long spurs, not a periodic height wave.
	var profiles: Array = [
		[[0, 146], [83, 118], [137, 62], [155, 68], [173, 46], [194, 48],
			[229, 99], [263, 110], [302, 154], [370, 131], [426, 99],
			[458, 68], [481, 65], [499, 72], [524, 70], [552, 110],
			[601, 138], [659, 156], [713, 130], [771, 108], [802, 102],
			[825, 38], [839, 42], [855, 78], [901, 123], [962, 154],
			[1033, 133], [1108, 80], [1137, 87], [1161, 53], [1180, 55],
			[1214, 103], [1269, 137], [1349, 151], [1424, 104], [1536, 143]],
		[[0, 204], [91, 174], [154, 151], [209, 161], [267, 118],
			[294, 110], [321, 128], [356, 133], [393, 175], [455, 201],
			[510, 190], [566, 146], [593, 130], [616, 139], [648, 127],
			[678, 145], [717, 155], [759, 208], [829, 216], [904, 180],
			[963, 159], [1019, 181], [1076, 194], [1134, 159], [1190, 126],
			[1218, 137], [1260, 134], [1311, 177], [1394, 204], [1536, 171]],
		[[0, 238], [101, 214], [169, 180], [195, 185], [221, 168],
			[247, 173], [276, 197], [314, 208], [387, 246], [479, 255],
			[557, 237], [638, 214], [711, 201], [748, 182], [780, 191],
			[822, 196], [883, 239], [964, 264], [1052, 251], [1124, 217],
			[1179, 207], [1241, 225], [1329, 244], [1424, 216], [1536, 238]],
		[[0, 297], [106, 275], [194, 243], [231, 247], [282, 260],
			[351, 294], [449, 315], [553, 309], [639, 289], [731, 267],
			[785, 249], [813, 254], [867, 277], [974, 308], [1069, 319],
			[1173, 294], [1267, 273], [1363, 287], [1452, 312], [1536, 304]],
		[[0, 347], [89, 329], [181, 303], [224, 311], [298, 339],
			[397, 362], [518, 368], [631, 354], [724, 331], [781, 321],
			[836, 333], [922, 357], [1047, 375], [1159, 359], [1259, 335],
			[1320, 322], [1383, 337], [1465, 358], [1536, 365]]]
	var crest: Array = profiles[layer]
	var mass: Array = crest.duplicate()
	mass.append([1536, 480])
	mass.append([0, 480])
	a.poly(mass, bases[layer])
	# Each face follows a particular crest, then an irregular descending rock rib.
	var faces: Array = [
		[[10, 14, [[510, 99], [491, 116], [478, 144], [435, 174]], 0],
			[14, 17, [[640, 199], [593, 177], [574, 148], [549, 128], [538, 96]], 1],
			[19, 21, [[819, 83], [803, 114], [792, 143], [754, 175]], 0],
			[22, 25, [[932, 208], [893, 177], [881, 146], [861, 125], [850, 82]], 1],
			[27, 30, [[1169, 91], [1146, 126], [1090, 172]], 0]],
		[[3, 5, [[286, 142], [275, 165], [244, 195]], 0],
			[5, 8, [[419, 220], [361, 191], [345, 166], [316, 149]], 1],
			[10, 12, [[578, 161], [549, 189], [542, 210], [506, 228]], 0],
			[14, 17, [[792, 251], [742, 223], [721, 192], [685, 174]], 1],
			[22, 24, [[1170, 163], [1143, 195], [1103, 226]], 0]],
		[[1, 4, [[213, 198], [195, 218], [166, 235], [128, 246]], 0],
			[4, 8, [[353, 275], [304, 255], [278, 229], [248, 214]], 1],
			[10, 13, [[738, 209], [717, 228], [684, 241], [629, 261]], 0],
			[13, 17, [[916, 282], [846, 265], [812, 238], [782, 222]], 1]],
		[[1, 3, [[224, 268], [190, 287], [146, 299]], 0],
			[8, 10, [[767, 276], [721, 294], [683, 304]], 0]],
		[[1, 2, [[165, 325], [126, 340]], 0],
			[7, 9, [[765, 343], [719, 359], [682, 365]], 0]]]
	for face in faces[layer]:
		var polygon: Array = crest.slice(face[0], face[1] + 1)
		polygon.append_array(face[2])
		a.poly(polygon, lights[layer] if face[3] == 0 else shadows[layer])
	if layer == 0:
		a.poly([[449, 78], [458, 68], [481, 65], [499, 72], [524, 70],
			[534, 85], [515, 80], [501, 88], [486, 78], [469, 81], [461, 77]],
			"#ccd0bc")
		a.poly([[812, 73], [825, 38], [839, 42], [855, 78], [843, 67],
			[833, 71], [829, 58], [822, 73]], "#ccd0bc")
	if layer >= 3:
		for index in range(1, crest.size() - 2, 3):
			var p: Array = crest[index]
			var q: Array = crest[index + 1]
			for member in range(7 if layer == 3 else 5):
				var t: float = member / 9.0
				var x: int = roundi(lerpf(p[0], q[0], t))
				var y: int = roundi(lerpf(p[1], q[1], t))
				var height: int = 4 + posmod(member * 7 + index * 3, 8)
				a.poly([[x, y - height], [x + 3, y - 4], [x + 2, y - 4],
					[x + 5, y + 2], [x - 4, y + 2], [x - 2, y - 3]],
					shadows[layer])
	# Broad quiet valley values let distant detail dissolve before the playable route.
	for y in range(210 + layer * 33, 480):
		var haze: float = smoothstep(210 + layer * 33, 460, y) * 0.43
		for x in range(1536):
			var pixel: Color = a.image.get_pixel(x, y)
			if pixel.a > 0:
				a.image.set_pixel(x, y, pixel.lerp(Color(bases[layer]), haze))
	return a.texture()

static func cliff(distant: bool = false) -> ImageTexture:
	var size: int = 768 if distant else 384
	var a = new(size, size)
	a.box(0, 0, size, size, "#38534f" if distant else "#485d51")
	var beds: Array = [
		[18, 12, 160, 32], [218, 53, 145, 44], [67, 103, 189, 38],
		[280, 154, 138, 51], [-23, 202, 165, 35], [157, 248, 180, 48],
		[40, 316, 181, 42], [265, 350, 153, 37]]
	for bed in range(beds.size()):
		var scale_value: int = 2 if distant else 1
		var px: int = beds[bed][0] * scale_value
		var py: int = beds[bed][1] * scale_value
		var w: int = beds[bed][2] * scale_value
		var h: int = beds[bed][3] * scale_value
		# Composed, discontinuous beds wrap as complete shapes at each tile edge.
		for ox in [-size, 0, size]:
			for oy in [-size, 0, size]:
				var x: int = px + ox
				var y: int = py + oy
				a.poly([[x, y + 12], [x + w / 4, y + 3],
					[x + w / 2, y + 5], [x + w - 19, y], [x + w, y + 15],
					[x + w - 23, y + h - 4], [x + w / 3, y + h],
					[x + 16, y + h - 7]], "#3d5751" if distant else "#596b58")
				a.poly([[x + 4, y + 12], [x + w / 4, y + 4],
					[x + w / 2, y + 6], [x + w - 25, y + 3],
					[x + w - 40, y + 13], [x + 48, y + 19],
					[x + 19, y + 17]], "#405a52" if distant else "#65755e")
				a.poly([[x + w - 19, y], [x + w, y + 15],
					[x + w - 23, y + h - 4], [x + w - 51, y + h - 2],
					[x + w - 32, y + 18]], "#354f4b" if distant else "#40574c")
				a.line(x + 4, y + 12, x + w / 4, y + 4,
					"#425c53" if distant else "#758066")
				if not distant:
					a.line(x + 31, y + 23, x + w / 2 - 5, y + 21, "#465c4d")
					a.line(x + 37, y + 24, x + w / 2 - 10, y + 23, "#718064")
					a.line(x + w - 47, y + 8, x + w - 55, y + 16, "#4b6051")
					a.line(x + w - 55, y + 16, x + w - 51, y + 21, "#4b6051")
					if bed in [1, 4]:
						a.box(x + 23, y + 13, 16, 3, "#4d684c")
						a.box(x + 25, y + 12, 7, 1, "#899468")
				if bed % 3 == 0:
					a.line(x + 25, y + h + 2, x + w / 2, y + h - 1,
						"#314c48" if distant else "#354f45", 2)
	return a.texture()

static func tread(variant: int) -> ImageTexture:
	var a = new(64, 6)
	a.box(0, 0, 64, 6, "#87998a")
	a.box(0, 5, 64, 1, "#425c55")
	for i in range(5):
		var x: int = (i * 17 + variant * 11) % 59
		var y: int = 1 + (i * 7 + variant * 3) % 3
		a.box(x, y, 3 + i % 3, 1, "#758d80" if i % 3 else "#a6ae95")
	a.box(2 + variant * 2, 0, 18, 1, "#b3b79c")
	a.box(27, 0, 12 + variant, 1, "#a6ae95")
	a.box(46 + variant, 4, 10, 1, "#a6ae95")
	a.line(23 + variant * 3, 1, 21 + variant * 3, 3, "#607b70")
	a.box(1, 3, 5 + variant, 2, "#537354")
	a.box(2, 3, 3, 1, "#839365")
	return a.texture()


static func terminal_surface(size: Vector2i, origin: Vector2, polygon: PackedVector2Array,
		mouth: Vector2, root: Vector2, direction: float) -> ImageTexture:
	var a = new(size.x, size.y)
	var run: float = absf(root.x - mouth.x)
	for y in range(size.y):
		var spans: PackedInt32Array = _pixel_spans(polygon, origin, y, size.x, false)
		for x in spans:
			var p: Vector2 = origin + Vector2(x, y)
			var inward: float = (p.x - mouth.x) * direction
			var cluster_x: int = floori(p.x / 7.0)
			var cluster_y: int = floori(p.y / 4.0)
			var cluster: int = posmod(cluster_x * 17 + cluster_y * 31, 23)
			var edge: float = 15 + sin(p.y * 0.27) * 5 + sin(p.y * 0.63) * 3
			var color := Color("#66755c")
			if inward > edge:
				color = Color("#87998a") if inward > edge + 17 + sin(p.y * 0.38) * 6 else Color("#78866d")
				if cluster < 7 and posmod(y, 4) == 1 and posmod(x, 7) < 5:
					color = Color("#758d80") if cluster < 4 else Color("#a6ae95")
			if cluster < 3 and posmod(x, 7) < 5 and posmod(y, 4) < 2 and inward > 7 and inward < run - 7:
				color = Color("#587653") if posmod(y, 3) else Color("#829064")
			# Small mineral fragments continue into earth, without a straight material cutoff.
			if cluster > 18 and inward > 8 and inward < edge + 9 and posmod(y, 3) == 1:
				color = Color("#9ca58b") if posmod(x, 5) < 3 else Color("#75856d")
			a.image.set_pixel(x, y, color)
	return a.texture()

static func clearing_surface(size: Vector2i, origin: Vector2, polygon: PackedVector2Array,
		back: PackedVector2Array, front: PackedVector2Array, route: PackedVector2Array,
		endpoint: Vector2, direction: float) -> ImageTexture:
	var a = new(size.x, size.y)
	for x in range(size.x):
		var wx: float = origin.x + x
		var section: int = clampi(floori((wx - route[0].x) * direction / 4.0), 0, route.size() - 2)
		var t: float = clampf((wx - route[section].x) /
			(route[section + 1].x - route[section].x), 0, 1)
		var center: Vector2 = route[section].lerp(route[section + 1], t)
		var rear: float = lerpf(back[section].y, back[section + 1].y, t)
		var near: float = lerpf(front[section].y, front[section + 1].y, t)
		var inward: float = (wx - route[0].x) * direction
		var settled: float = smoothstep(0, 70, inward)
		var wear: float = smoothstep(-35, 24, (wx - endpoint.x) * direction)
		var edge: float = 3 + sin(wx * 0.27) * 2 + sin(wx * 0.63)
		for y in range(size.y):
			var p := origin + Vector2(x, y)
			if not Geometry2D.is_point_in_polygon(p + Vector2(0.5, 0.5), polygon):
				continue
			var cluster: int = posmod(floori(p.x / 7) * 17 + floori(p.y / 4) * 31, 23)
			var code: int = posmod(floori(p.x / 19) * 13 + floori(p.y / 9) * 7, 17)
			var lip: float = near - p.y
			var color := Color("#66755c")
			# The same discrete earth, moss and mineral clusters as the stair turns.
			if settled > 0.3 and (absf(p.y - center.y) > 6 + code * 0.55):
				if cluster < 7 and posmod(y, 4) < 2 and posmod(x, 7) < 5:
					color = Color("#587653") if cluster < 4 else Color("#829064")
				if code < 4 and cluster > 12:
					color = Color("#78866d")
					if posmod(y, 4) == 1 and posmod(x, 7) < 5:
						color = Color("#87998a") if cluster > 18 else Color("#758d80")
			if settled > 0.1 and lip < edge and cluster > 4:
				color = Color("#78866d") if cluster < 16 else Color("#87998a")
			if settled > 0.3 and p.y - rear < edge and cluster < 8:
				color = Color("#587653") if cluster < 5 else Color("#829064")
			if absf(p.y - center.y) < 1.5 and wear < 1:
				if inward < 32 or cluster > 3 + floori(wear * 19):
					color = Color("#b0ad86")
			elif settled > 0.2 and cluster > 18 and posmod(y, 3) == 1 and posmod(x, 5) < 3:
				color = Color("#9ca58b")
			a.image.set_pixel(x, y, color)
	return a.texture()


static func _pixel_spans(polygon: PackedVector2Array, origin: Vector2,
		column: int, limit: int, vertical: bool) -> PackedInt32Array:
	var axis: int = 0 if vertical else 1
	var other: int = 1 - axis
	var sample: Vector2 = origin
	sample[axis] += column
	sample += Vector2.ONE * 0.5
	var at: float = sample[axis]
	var hits: Array[float] = []
	for index in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		if (a[axis] <= at and b[axis] > at) or (b[axis] <= at and a[axis] > at):
			hits.append(lerpf(a[other], b[other], (at - a[axis]) / (b[axis] - a[axis])))
	hits.sort()
	var pixels := PackedInt32Array()
	for index in range(0, hits.size() - 1, 2):
		var first: int = maxi(0, ceili(hits[index] - origin[other] - 0.5) - 1)
		var last: int = mini(limit - 1, floori(hits[index + 1] - origin[other] - 0.5) + 1)
		for pixel in range(first, last + 1):
			# Retain Geometry2D's epsilon/boundary convention around both endpoints.
			if pixel <= first + 1 or pixel >= last - 1:
				var offset := Vector2(column, pixel) if vertical else Vector2(pixel, column)
				var point: Vector2 = origin + offset
				if not Geometry2D.is_point_in_polygon(point + Vector2.ONE * 0.5, polygon):
					continue
			pixels.append(pixel)
	return pixels


static func banner(frame: int) -> ImageTexture:
	var a = new(32, 22)
	for x in range(30):
		var wave: int = roundi(sin(x * 0.22 - frame * TAU / 6.0) * x / 12.0)
		var top: int = 3 + wave + x / 7
		var bottom: int = 18 + wave - x / 5
		var shade: String = "#bc885b" if sin(x * 0.22 - frame * TAU / 6.0) > 0 else "#95684b"
		a.box(x, top, 1, bottom - top, shade)
		a.dot(x, top, "#e0b37b")
		a.dot(x, bottom, "#77543f")
	a.line(1, 4, 1, 17, "#ead0a0")
	return a.texture()


static func sky() -> ImageTexture:
	var a = new(640, 360)
	var top := Color("#668c91")
	var bottom := Color("#c0c5a5")
	for y in range(0, 360, 3):
		a.box(0, y, 640, 3, top.lerp(bottom, float(y) / 360.0).to_html())
	for y in range(-21, 22):
		var w: int = floori(sqrt(21 * 21 - y * y))
		a.box(146 - w, 71 + y, w * 2, 1, "#f0dab1")
	for i in range(7):
		var x: int = 20 + i * 93
		var y: int = 48 + (i * 23) % 55
		a.box(x, y, 61, 2, "#b7beb0")
		a.box(x + 9, y - 2, 36, 2, "#b7beb0")
		a.box(x + 24, y + 2, 51, 1, "#aeb9ab")
	return a.texture()
