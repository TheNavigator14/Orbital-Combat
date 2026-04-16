class_name ScaleConverter
extends RefCounted
## Converts between world coordinates (meters) and screen coordinates (pixels)
## Supports hybrid linear/logarithmic scaling for orbital visualization

enum ScaleMode { LINEAR, LOGARITHMIC, HYBRID }

# === Configuration ===
var scale_mode: ScaleMode = ScaleMode.LINEAR
var focus_position: Vector2 = Vector2.ZERO  # World position of view center (meters)
var zoom_level: float = 1.0  # Higher = more zoomed in
var screen_center: Vector2 = Vector2.ZERO  # Screen center in pixels

# === Scale Parameters ===
const LINEAR_THRESHOLD: float = 1.0e9  # 1 million km - switch to log beyond this
const LOG_BASE: float = 10.0
const LOG_SCALE_FACTOR: float = 80.0  # Pixels per log10 unit at zoom 1.0
const LINEAR_SCALE: float = 1.0e-6  # Pixels per meter at zoom 1.0 (1 pixel = 1km)

const MIN_ZOOM: float = 0.0001
const MAX_ZOOM: float = 10000.0


func set_screen_size(size: Vector2) -> void:
	screen_center = size / 2.0


func set_focus(world_pos: Vector2) -> void:
	focus_position = world_pos


func set_zoom(level: float) -> void:
	zoom_level = clampf(level, MIN_ZOOM, MAX_ZOOM)


func zoom_in(factor: float = 1.2) -> void:
	set_zoom(zoom_level * factor)


func zoom_out(factor: float = 1.2) -> void:
	set_zoom(zoom_level / factor)


func world_to_screen(world_pos: Vector2) -> Vector2:
	## Convert world position (meters) to screen position (pixels)
	var relative = world_pos - focus_position

	var screen_offset: Vector2
	match scale_mode:
		ScaleMode.LINEAR:
			screen_offset = _linear_transform(relative)
		ScaleMode.LOGARITHMIC:
			screen_offset = _logarithmic_transform(relative)
		ScaleMode.HYBRID:
			screen_offset = _hybrid_transform(relative)

	return screen_center + screen_offset


func screen_to_world(screen_pos: Vector2) -> Vector2:
	## Convert screen position to world position (approximate for log scale)
	var screen_offset = screen_pos - screen_center

	var relative: Vector2
	match scale_mode:
		ScaleMode.LINEAR:
			relative = _inverse_linear(screen_offset)
		ScaleMode.LOGARITHMIC:
			relative = _inverse_logarithmic(screen_offset)
		ScaleMode.HYBRID:
			relative = _inverse_hybrid(screen_offset)

	return focus_position + relative


func distance_to_screen(world_distance: float) -> float:
	## Convert a world distance to screen pixels
	match scale_mode:
		ScaleMode.LINEAR:
			return world_distance * LINEAR_SCALE * zoom_level
		ScaleMode.LOGARITHMIC:
			if world_distance <= 1.0:
				return 0.0
			return log(world_distance) / log(LOG_BASE) * LOG_SCALE_FACTOR * zoom_level
		ScaleMode.HYBRID:
			if world_distance < LINEAR_THRESHOLD:
				return world_distance * LINEAR_SCALE * zoom_level
			else:
				var base_offset = LINEAR_THRESHOLD * LINEAR_SCALE * zoom_level
				var log_distance = log(world_distance / LINEAR_THRESHOLD) / log(LOG_BASE)
				return base_offset + log_distance * LOG_SCALE_FACTOR * zoom_level

	return 0.0


# === Transform Functions ===

func _linear_transform(relative: Vector2) -> Vector2:
	return relative * LINEAR_SCALE * zoom_level


func _logarithmic_transform(relative: Vector2) -> Vector2:
	var distance = relative.length()
	if distance < 1.0:
		return Vector2.ZERO

	var log_distance = log(distance) / log(LOG_BASE)
	var screen_distance = log_distance * LOG_SCALE_FACTOR * zoom_level
	return relative.normalized() * screen_distance


func _hybrid_transform(relative: Vector2) -> Vector2:
	## Linear close-up, logarithmic at distance
	var distance = relative.length()

	if distance < LINEAR_THRESHOLD:
		return _linear_transform(relative)
	else:
		# Continuous transition: linear up to threshold, then log
		var direction = relative.normalized()

		# Linear portion up to threshold
		var linear_portion = LINEAR_THRESHOLD * LINEAR_SCALE * zoom_level

		# Logarithmic portion beyond threshold
		var log_distance = log(distance / LINEAR_THRESHOLD) / log(LOG_BASE)
		var log_portion = log_distance * LOG_SCALE_FACTOR * zoom_level

		return direction * (linear_portion + log_portion)


# === Inverse Transforms ===

func _inverse_linear(screen_offset: Vector2) -> Vector2:
	return screen_offset / (LINEAR_SCALE * zoom_level)


func _inverse_logarithmic(screen_offset: Vector2) -> Vector2:
	var screen_distance = screen_offset.length()
	if screen_distance < 0.1:
		return Vector2.ZERO

	var log_distance = screen_distance / (LOG_SCALE_FACTOR * zoom_level)
	var world_distance = pow(LOG_BASE, log_distance)
	return screen_offset.normalized() * world_distance


func _inverse_hybrid(screen_offset: Vector2) -> Vector2:
	var screen_distance = screen_offset.length()
	var linear_max = LINEAR_THRESHOLD * LINEAR_SCALE * zoom_level

	if screen_distance < linear_max:
		return _inverse_linear(screen_offset)
	else:
		var direction = screen_offset.normalized()

		# Subtract linear portion
		var log_screen = screen_distance - linear_max

		# Convert log portion back
		var log_distance = log_screen / (LOG_SCALE_FACTOR * zoom_level)
		var world_distance = LINEAR_THRESHOLD * pow(LOG_BASE, log_distance)

		return direction * world_distance


# === Utility ===

func get_visible_world_radius() -> float:
	## Get approximate world radius visible on screen
	var screen_radius = minf(screen_center.x, screen_center.y)
	return _inverse_hybrid(Vector2(screen_radius, 0)).x