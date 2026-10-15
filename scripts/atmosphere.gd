extends Node2D

const Art = preload("res://scripts/pixel_art.gd")
const Scenery = preload("res://scripts/mountain_scenery.gd")
var scenery_seed: int = -1
var shoulder_offset: float = 0
var time: float = 0
var veil: ColorRect
var shader_material: ShaderMaterial
var mountains: Array[Texture2D] = []
var sky_texture: Texture2D
var mountain_canvas: Node2D
var range_draws: int = 0
var _range_rects: Array[Rect2] = []
var _range_size := Vector2.ZERO
@onready var camera = $"../../Camera2D"


func _ready() -> void:
	sky_texture = Art.sky()
	mountain_canvas = Node2D.new()
	mountain_canvas.show_behind_parent = true
	mountain_canvas.draw.connect(_draw_ranges)
	add_child(mountain_canvas)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float clock = 0.0;
void fragment() {
	vec2 uv = UV;
	float bands = sin(uv.y * 21.0 + sin(uv.x * 5.0 + clock * 0.035) * 1.4);
	float haze = smoothstep(-0.65, 1.0, bands) * 0.035;
	float shaft = pow(max(0.0, sin(uv.x * 13.0 + uv.y * 4.0 + 0.7)), 12.0);
	float vignette = smoothstep(0.22, 0.80, distance(uv, vec2(0.5)));
	COLOR = vec4(vec3(0.66, 0.76, 0.59),
		haze + shaft * 0.035 - vignette * 0.01);
}
"""
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	# A separate layer places the restrained mist over the world, below the HUD.
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	veil = ColorRect.new()
	veil.size = Vector2(1280, 720)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.material = shader_material
	layer.add_child(veil)


func regenerate(hike_id: int) -> void:
	if scenery_seed == hike_id:
		return
	scenery_seed = hike_id
	shoulder_offset = Scenery.recipe(hike_id).shoulder * 2
	mountains = Scenery.layers(hike_id)
	mountain_canvas.queue_redraw()


func _process(delta: float) -> void:
	time += delta
	veil.size = get_viewport_rect().size
	shader_material.set_shader_parameter("clock", time)
	var rects: Array[Rect2] = []
	for layer in range(5):
		rects.append(_mountain_rect(layer))
	if rects != _range_rects or _range_size != get_viewport_rect().size:
		_range_rects = rects
		_range_size = get_viewport_rect().size
		mountain_canvas.queue_redraw()
	queue_redraw()


func _mountain_rect(layer: int) -> Rect2:
	var parallax: float = 0.018 + layer * 0.018
	var offset: float = clampf(740 + camera.position.x * parallax, 0, 1792)
	var elevation: float = clampf(-camera.position.y * (0.004 + layer * 0.003), -12, 46)
	return Rect2(-roundf(offset), -12 + roundf(elevation + (shoulder_offset if layer > 0 else 0)), 3072, 960)


func _draw_ranges() -> void:
	range_draws += 1
	var size: Vector2 = get_viewport_rect().size
	mountain_canvas.draw_set_transform(Vector2.ZERO, 0, size / Vector2(1280, 720))
	if sky_texture:
		mountain_canvas.draw_texture_rect(sky_texture, Rect2(0, 0, 1280, 720), false)
	for layer in range(5):
		# A single overscanned panorama never wraps at negative X or exposes a tile seam.
		if layer < mountains.size():
			mountain_canvas.draw_texture_rect(mountains[layer], _mountain_rect(layer), false)


func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(1280, 720))
	for index in range(18):
		var x: float = fposmod(index * 83.7 + sin(time * 0.17 + index) * 28 - time * 3, 1300)
		var y: float = fposmod(index * 127.3 + time * (2 + index % 3), 740)
		draw_rect(Rect2(Vector2(x, y).snapped(Vector2(2, 2)), Vector2(2, 2)),
			Color(0.96, 0.85, 0.60, 0.35))
	# Two distant birds follow a slow, looping arc; no borrowed animation frames.
	for index in range(2):
		var p := Vector2(fposmod(time * 8 + 230 + index * 38, 1500) - 100,
			190 + sin(time * 0.18 + index) * 18)
		var wing: float = sin(time * 2.0 + index) * 3
		draw_polyline(PackedVector2Array([
			p + Vector2(-5, -wing), p, p + Vector2(5, -wing)]), Color("#4b685b"), 1)
