class_name OrbitalCamera
extends Camera2D
## Camera for orbital view with zoom and pan controls
## Integrates with ScaleConverter for proper world-to-screen mapping

signal zoom_changed(level: float)
signal focus_changed(target: Node)

# === Configuration ===
@export var zoom_speed: float = 0.1
@export var pan_speed: float = 1.0
@export var smooth_zoom: bool = true
@export var smooth_pan: bool = true
@export var smoothing_speed: float = 5.0

# === State ===
var scale_converter: ScaleConverter
var focus_target: Node = null
var is_panning: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO

# === Target values for smoothing ===
var target_zoom: float = 1.0
var target_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	scale_converter = ScaleConverter.new()
	scale_converter.set_screen_size(get_viewport_rect().size)

	# Connect to GameManager for focus changes
	if GameManager:
		GameManager.focus_body_changed.connect(_on_focus_changed)


func _process(delta: float) -> void:
	# Update scale converter screen size
	scale_converter.set_screen_size(get_viewport_rect().size)

	# Follow focus target
	if focus_target:
		if focus_target.has_method("get") and "world_position" in focus_target:
			target_offset = Vector2.ZERO
			scale_converter.set_focus(focus_target.world_position)
		elif "position" in focus_target:
			target_offset = Vector2.ZERO
			scale_converter.set_focus(focus_target.position)

	# Smooth zoom
	if smooth_zoom:
		scale_converter.zoom_level = lerpf(scale_converter.zoom_level, target_zoom, smoothing_speed * delta)
	else:
		scale_converter.zoom_level = target_zoom

	# Update camera zoom (Godot's zoom is inverse of our zoom_level)
	var godot_zoom = scale_converter.zoom_level * 0.01  # Adjust scale
	zoom = Vector2(godot_zoom, godot_zoom)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				start_pan(event.position)
			else:
				end_pan()

	# Mouse motion for panning
	if event is InputEventMouseMotion and is_panning:
		update_pan(event.position)

	# Keyboard zoom
	if event.is_action_pressed("zoom_in"):
		zoom_in()
	elif event.is_action_pressed("zoom_out"):
		zoom_out()


func zoom_in(factor: float = 1.0 + zoom_speed) -> void:
	target_zoom = clampf(target_zoom * factor, ScaleConverter.MIN_ZOOM, ScaleConverter.MAX_ZOOM)
	zoom_changed.emit(target_zoom)


func zoom_out(factor: float = 1.0 + zoom_speed) -> void:
	target_zoom = clampf(target_zoom / factor, ScaleConverter.MIN_ZOOM, ScaleConverter.MAX_ZOOM)
	zoom_changed.emit(target_zoom)


func set_zoom_level(level: float) -> void:
	target_zoom = clampf(level, ScaleConverter.MIN_ZOOM, ScaleConverter.MAX_ZOOM)
	if not smooth_zoom:
		scale_converter.zoom_level = target_zoom
	zoom_changed.emit(target_zoom)


func start_pan(mouse_pos: Vector2) -> void:
	is_panning = true
	pan_start_mouse = mouse_pos
	pan_start_offset = target_offset


func update_pan(mouse_pos: Vector2) -> void:
	if not is_panning:
		return

	var delta = mouse_pos - pan_start_mouse
	# Convert screen delta to world delta
	var world_delta = scale_converter.screen_to_world(pan_start_mouse) - scale_converter.screen_to_world(mouse_pos)
	scale_converter.focus_position += world_delta
	pan_start_mouse = mouse_pos


func end_pan() -> void:
	is_panning = false


func set_focus(target: Node) -> void:
	focus_target = target
	focus_changed.emit(target)


func clear_focus() -> void:
	focus_target = null
	focus_changed.emit(null)


func _on_focus_changed(body: Node) -> void:
	set_focus(body)


func world_to_screen(world_pos: Vector2) -> Vector2:
	## Convenience function to convert world to screen coordinates
	return scale_converter.world_to_screen(world_pos)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	## Convenience function to convert screen to world coordinates
	return scale_converter.screen_to_world(screen_pos)


func get_focus_position() -> Vector2:
	## Get current focus position in world coordinates
	return scale_converter.focus_position