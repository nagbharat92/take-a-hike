extends Node2D
const Library = preload("res://scripts/asset_library.gd")

enum State { HIKE, COMPLETE }
var state: State = State.HIKE
var paused: bool = false
var overview: bool = false
var completed_count: int = 0
var _last_hint: String = ""

@onready var trail = $Trail
@onready var player = $Player
@onready var camera = $Camera2D
@onready var landscape = $Landscape
@onready var backdrop = $Backdrop/Atmosphere
var title: Label
var subtitle: Label
var hint: Label
var panel: PanelContainer
var summary: Label
var action: Button
var map_button: Button
var pause_button: Button
var credits: RichTextLabel
var credits_button: Button
var bottom: HBoxContainer
var _new_hike_pending: bool = false


func _ready() -> void:
	_build_ui()
	camera.zoom = Vector2.ONE * 2.2
	get_viewport().size_changed.connect(_layout_ui)
	_begin_hike()
	camera.snap_to_target()


func _build_ui() -> void:
	var ui: CanvasLayer = $HUD
	var card := PanelContainer.new()
	card.position = Vector2(28, 24)
	card.custom_minimum_size = Vector2(292, 0)
	card.add_theme_stylebox_override("panel", Library.panel())
	ui.add_child(card)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	card.add_child(top)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("#e2dfc5"))
	title.add_theme_color_override("font_shadow_color", Color("#1e3d36"))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	top.add_child(title)
	subtitle = Label.new()
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("#a8bdb4"))
	subtitle.add_theme_color_override("font_shadow_color", Color("#142d32"))
	subtitle.add_theme_constant_override("shadow_offset_y", 1)
	top.add_child(subtitle)
	bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	ui.add_child(bottom)
	map_button = _button("Overview  O", toggle_view, bottom)
	map_button.toggle_mode = true
	_button("Replay  T", replay_hike, bottom)
	_button("New hike  R", request_new_hike, bottom)
	pause_button = _button("Pause  Esc", toggle_pause, bottom)
	pause_button.toggle_mode = true
	_button("−", func(): camera.manual_zoom(-1), bottom)
	_button("+", func(): camera.manual_zoom(1), bottom)
	for i in range(3):
		var icon := AtlasTexture.new()
		icon.atlas = load("res://assets/vendor/kenney/Spritesheet/UIpackSheet_transparent.png")
		icon.region = Rect2(396 if i == 1 else 414, 432, 16, 16)
		bottom.get_child(i).icon = icon
	var primary: Button = bottom.get_child(2)
	var primary_style: StyleBoxTexture = Library.panel()
	primary_style.modulate_color = Color("#849580")
	primary.add_theme_stylebox_override("normal", primary_style)
	hint = Label.new()
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("#e2dfc5"))
	ui.add_child(hint)
	panel = PanelContainer.new()
	panel.position = Vector2(28, 136)
	panel.custom_minimum_size = Vector2(292, 0)
	panel.add_theme_stylebox_override("panel", Library.panel())
	ui.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	summary = Label.new()
	summary.add_theme_font_size_override("font_size", 15)
	summary.add_theme_color_override("font_color", Color("#d0d4bd"))
	column.add_child(summary)
	action = _button("Replay this trail  T", replay_hike, column)
	credits_button = _button("Credits  C", toggle_credits, column)
	credits = RichTextLabel.new()
	credits.bbcode_enabled = true
	credits.custom_minimum_size = Vector2(380, 240)
	credits.add_theme_font_size_override("normal_font_size", 15)
	credits.add_theme_color_override("default_color", Color("#d0d4bd"))
	credits.text = "[b]Art and tools[/b]\n\n" \
		+ "[url=https://rvros.itch.io/animated-pixel-hero]Animated Pixel Adventurer[/url] · rvros\n\n" \
		+ "[url=https://anokolisa.itch.io/sidescroller-pixelart-sprites-asset-pack-forest-16x16]High Forest[/url] · Anokolisa\n\n" \
		+ "[url=https://kenney.nl/assets/pixel-ui-pack]Pixel UI Pack[/url] · Kenney / Lynn Evers · CC0\n\n" \
		+ "[url=https://github.com/alex9978/scatter2d]Scatter2D[/url] · Alessandro Rasulo / HungryProton · MIT\n\n" \
		+ "[url=https://godotengine.org/license/]Godot Engine and third-party licenses[/url] · MIT\n\n" \
		+ "Artwork adapted for this game. Original asset licenses still apply."
	credits.meta_clicked.connect(func(url: Variant): OS.shell_open(str(url)))
	column.add_child(credits)
	credits.hide()
	_layout_ui()


func _layout_ui() -> void:
	var size: Vector2 = get_viewport_rect().size
	bottom.position = Vector2(28, size.y - 68)
	hint.position = Vector2(28, size.y - 104)


func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	for item in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBoxTexture = Library.panel(item == "pressed")
		if item == "hover":
			style.modulate_color = Color("#849b80")
		elif item == "focus":
			style.modulate_color = Color("#c9bc85")
			style.draw_center = false
		elif item == "disabled":
			style.modulate_color = Color("#36483f")
		button.add_theme_stylebox_override(item, style)
	button.add_theme_color_override("font_color", Color("#dce0c7"))
	button.add_theme_color_override("font_disabled_color", Color("#788b7c"))
	button.add_theme_color_override("icon_normal_color", Color("#afbc9b"))
	button.add_theme_color_override("icon_hover_color", Color("#d4d5ae"))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func toggle_pause() -> void:
	if state != State.HIKE or overview:
		return
	paused = not paused
	_sync_controls()


func toggle_credits() -> void:
	credits.visible = not credits.visible
	credits_button.text = "Close credits  C" if credits.visible else "Credits  C"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.manual_zoom(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode if event.physical_keycode else event.keycode
	match code:
		KEY_C:
			if panel.visible:
				toggle_credits()
		KEY_R:
			request_new_hike()
		KEY_T:
			replay_hike()
		KEY_O, KEY_TAB:
			toggle_view()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			camera.manual_zoom(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			camera.manual_zoom(-1)
		KEY_ESCAPE:
			if credits.visible:
				toggle_credits()
			elif overview:
				set_overview(false)
			elif state == State.HIKE:
				toggle_pause()
		_:
			return
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if state == State.HIKE and not paused and not overview and player.at_summit():
		complete_hike()
	var text: String
	match state:
		State.COMPLETE:
			text = "T  Walk this trail again     ·     R  A new hike"
		State.HIKE:
			if overview:
				text = "O / Esc  Return to trail     ·     Scroll or + / −  Zoom"
			elif paused:
				text = "Paused     ·     Esc  Resume"
			elif _stairs_exit():
				text = "A / D or ← / →  Leave the steps and follow the path"
			elif player.depth_walking or _near_stairs():
				text = "W / ↑  Climb into depth     ·     S / ↓  Descend"
			else:
				text = "A / D or ← / →  Follow the path     ·     Reverse at each turn"
	if text != _last_hint:
		hint.text = text
		_last_hint = text


func _near_stairs() -> bool:
	var index: int = player._segment
	return index < trail.segment_kinds.size() - 1 \
		and trail.segment_kinds[index + 1] == "stairs" \
		and player.position.distance_to(trail.points[index + 1]) < 45


func _stairs_exit() -> bool:
	if not player.depth_walking:
		return false
	var index: int = player._segment
	var length: float = trail.points[index].distance_to(trail.points[index + 1])
	return (player._distance >= length - 0.01 and index < trail.segment_kinds.size() - 1 \
		and trail.segment_kinds[index + 1] == "walk") \
		or (player._distance <= 0.01 and index > 0 and trail.segment_kinds[index - 1] == "walk")


func _begin_hike() -> void:
	state = State.HIKE
	player.modulate.a = 1
	trail.visible = false
	paused = false
	camera.set_physics_process(true)
	_refresh()
	_sync_controls()


func complete_hike() -> void:
	if state == State.COMPLETE:
		return
	state = State.COMPLETE
	completed_count += 1
	player.moving = false
	player.set_physics_process(false)
	summary.text = "Summit reached\n\nThe valley is quiet below."
	action.text = "Replay this trail  T"
	action.disabled = false
	panel.visible = true
	_sync_controls()


func _short_specs() -> String:
	return "%.2f km one way\n%.0f m elevation gain" % [
		trail.walking_distance / 20000.0, trail.uphill_travel / 20.0]


func _sync_controls() -> void:
	if credits.visible:
		toggle_credits()
	player.set_physics_process(state == State.HIKE and not paused and not overview)
	player.moving = false
	player.visible = not overview
	panel.visible = overview or paused or state == State.COMPLETE
	map_button.text = "Trail view  O" if overview else "Overview  O"
	map_button.set_pressed_no_signal(overview)
	map_button.icon.region.position.x = 396 if overview else 414
	map_button.disabled = false
	pause_button.disabled = overview or state == State.COMPLETE
	pause_button.text = "Resume  Esc" if paused else "Pause  Esc"
	pause_button.set_pressed_no_signal(paused)
	if state == State.HIKE:
		summary.text = "Trail overview" if overview else "Take a breath"
		action.text = "Return to trail" if overview else "Resume walking"
		action.disabled = false
	for connection in action.pressed.get_connections():
		action.pressed.disconnect(connection.callable)
	action.pressed.connect(resume_hike if state == State.HIKE else replay_hike)


func resume_hike() -> void:
	paused = false
	set_overview(false)


func set_overview(enabled: bool) -> void:
	overview = enabled
	camera.set_overview(enabled)
	_sync_controls()


func toggle_view() -> void:
	if state != State.HIKE and state != State.COMPLETE:
		return
	set_overview(not overview)


func request_new_hike() -> void:
	# Multiple presses delivered in one frame must not queue several blocking builds.
	if _new_hike_pending:
		return
	_new_hike_pending = true
	_flush_new_hike.call_deferred()


func _flush_new_hike() -> void:
	_new_hike_pending = false
	new_hike()


func new_hike() -> void:
	var next_seed: int = randi()
	if next_seed == trail.hike_seed:
		next_seed = (next_seed + 1) % 4294967296
	# Adjacent hikes have distinct anchors; Replay still derives from this ID alone.
	if next_seed % 4 == trail.hike_seed % 4:
		next_seed = (next_seed + 1) % 4294967296
	trail.generate(next_seed)
	var keep_map: bool = overview
	_begin_hike()
	set_overview(keep_map)


func replay_hike() -> void:
	var keep_map: bool = overview
	_begin_hike()
	set_overview(keep_map)


func _refresh() -> void:
	var bounds := Rect2(trail.points[0], Vector2.ZERO)
	for point in trail.points:
		bounds = bounds.expand(point)
	camera.world_bounds = bounds.grow(420)
	camera.overview_bounds = bounds.grow(120)
	player.reset()
	camera.reframe()
	landscape.rebuild()
	backdrop.regenerate(trail.hike_seed)
	title.text = trail.personality_text()
	subtitle.text = _short_specs()
