class_name GameUtils
extends Node
## Utility functions for Orbital Combat game
## Autoload singleton for common helper functions

const VERSION := "1.0.0"
const BUILD_NUMBER := 61

# === Vector Helpers ===

static func angle_to_vector(angle_rad: float) -> Vector2:
	"""Convert angle in radians to unit vector (X-forward)"""
	return Vector2(cos(angle_rad), sin(angle_rad))


static func vector_to_angle(v: Vector2) -> float:
	"""Get angle of vector in radians (X-forward)"""
	return v.angle()


static func rotate_vector_90(v: Vector2, clockwise: bool = true) -> Vector2:
	"""Rotate vector 90 degrees"""
	return v.rotated(-PI/2 if clockwise else PI/2)


static func project_onto(v: Vector2, direction: Vector2) -> Vector2:
	"""Project v onto direction (scalar component only)"""
	return direction * (v.dot(direction) / direction.length_squared()) if direction.length_squared() > 0.0001 else Vector2.ZERO


static func perpendicular_component(v: Vector2, direction: Vector2) -> Vector2:
	"""Get perpendicular component of v relative to direction"""
	return v - project_onto(v, direction)


# === Math Helpers ===

static func lerp_angle(a: float, b: float, t: float) -> float:
	"""Linear interpolation between angles, taking shortest path"""
	var diff := fmod(b - a + PI, TAU) - PI
	return a + diff * clampf(t, 0.0, 1.0)


static func approach(current: float, target: float, delta: float) -> float:
	"""Move current toward target by delta amount"""
	if target > current + delta:
		return current + delta
	elif target < current - delta:
		return current - delta
	return target


static func angular_approach(current: float, target: float, delta: float) -> float:
	"""Move current angle toward target angle by delta amount"""
	var diff := fmod(target - current + PI, TAU) - PI
	if diff > delta:
		return current + delta
	elif diff < -delta:
		return current - delta
	return target


static func circular_distance(a: float, b: float) -> float:
	"""Get shortest distance between two angles"""
	var diff := fmod(b - a + PI, TAU) - PI
	return absf(diff)


static func sign_nonzero(value: float) -> int:
	"""Return sign of value (1 or -1, never 0)"""
	return 1 if value >= 0 else -1


static func clamp01(value: float) -> float:
	"""Clamp value between 0 and 1"""
	return clampf(value, 0.0, 1.0)


static func inverse_lerp(a: float, b: float, value: float) -> float:
	"""Inverse linear interpolation - get t where value = lerp(a, b, t)"""
	if absf(b - a) < 0.0001:
		return 0.0
	return clampf((value - a) / (b - a), 0.0, 1.0)


# === Distance Helpers ===

static func distance_squared_2d(from: Vector2, to: Vector2) -> float:
	"""Get squared distance (faster than actual distance)"""
	return from.distance_squared_to(to)


static func safe_distance_ratio(distance: float, min_range: float, max_range: float) -> float:
	"""Get ratio of distance within range (0 = at min, 1 = at max, clamped)"""
	if max_range <= min_range:
		return 0.0
	return clamp01((distance - min_range) / (max_range - min_range))


static func falloff_interpolation(distance: float, inner: float, outer: float, curve: float = 1.0) -> float:
	"""Get falloff value for distance (1 at inner, 0 at outer, with curve)"""
	var t := clamp01(1.0 - safe_distance_ratio(distance, inner, outer))
	return pow(t, curve)


# === Angle Helpers ===

static func normalize_angle(angle: float) -> float:
	"""Normalize angle to [-PI, PI]"""
	return fmod(angle + PI, TAU) - PI


static func normalize_angle_0_2pi(angle: float) -> float:
	"""Normalize angle to [0, TAU]"""
	return fmod(angle, TAU)


static func is_angle_between(angle: float, min_angle: float, max_angle: float) -> bool:
	"""Check if angle is between min and max (handles wrap-around)"""
	angle = normalize_angle(angle - min_angle)
	var range_angle := normalize_angle(max_angle - min_angle)
	if range_angle < 0:
		range_angle += TAU
	return angle >= 0 and angle <= range_angle


static func angle_from_to(from_angle: float, to_angle: float) -> float:
	"""Get signed angle from one direction to another (shortest path)"""
	return normalize_angle(to_angle - from_angle)


# === Position Helpers ===

static func point_on_circle(center: Vector2, radius: float, angle: float) -> Vector2:
	"""Get point on circle at angle"""
	return center + Vector2(cos(angle), sin(angle)) * radius


static func point_on_ellipse(center: Vector2, radius_x: float, radius_y: float, angle: float) -> Vector2:
	"""Get point on ellipse at angle"""
	return center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)


static func closest_point_on_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> Vector2:
	"""Get closest point on line segment to given point"""
	var line_vec := line_end - line_start
	var point_vec := point - line_start
	var line_len := line_vec.length()
	var line_dir := line_vec / line_len if line_len > 0.0001 else Vector2.ZERO
	var projection := clampf(point_vec.dot(line_dir), 0.0, line_len)
	return line_start + line_dir * projection


static func distance_to_line_segment(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Get minimum distance from point to line segment"""
	return point.distance_to(closest_point_on_line_segment(point, line_start, line_end))


# === Random Helpers ===

static func random_in_range(min_val: float, max_val: float) -> float:
	"""Get random float in range [min, max]"""
	return randf_range(min_val, max_val)


static func random_in_range_int(min_val: int, max_val: int) -> int:
	"""Get random int in range [min, max]"""
	return randi_range(min_val, max_val)


static func random_bool(probability: float = 0.5) -> bool:
	"""Get random bool with given probability of true"""
	return randf() < probability


static func random_from_array(arr: Array):
	"""Get random element from array"""
	return arr[randi() % arr.size()] if arr.size() > 0 else null


static func random_sign() -> int:
	"""Get random sign (1 or -1)"""
	return 1 if randf() > 0.5 else -1


# === Array Helpers ===

static func clamp_array_index(index: int, array_size: int) -> int:
	"""Clamp index to valid array range"""
	return clampi(index, 0, maxi(array_size - 1, 0))


static func wrap_array_index(index: int, array_size: int) -> int:
	"""Wrap index to valid array range"""
	if array_size <= 0:
		return 0
	return ((index % array_size) + array_size) % array_size


static func remove_if(arr: Array, predicate: Callable) -> Array:
	"""Remove elements matching predicate from array"""
	var result := []
	for item in arr:
		if not predicate.call(item):
			result.append(item)
	return result


# === String Helpers ===

static func pad_number(num: float, width: int, decimals: int = 0) -> String:
	"""Format number with padding"""
	return ("%" + str(width) + "." + str(decimals) + "f") % num


static func pad_int(num: int, width: int) -> String:
	"""Format integer with padding"""
	return ("%0" + str(width) + "d") % num


static func bool_to_yes_no(value: bool) -> String:
	"""Convert bool to YES/NO string"""
	return "YES" if value else "NO"


static func bool_to_on_off(value: bool) -> String:
	"""Convert bool to ON/OFF string"""
	return "ON" if value else "OFF"


static func bool_to_indicator(value: bool, on_char: String = "■", off_char: String = "□") -> String:
	"""Convert bool to indicator characters"""
	return on_char if value else off_char


# === Debug Helpers ===

static func format_vector(v: Vector2, decimals: int = 1) -> String:
	"""Format vector as string"""
	return "(%.{0}f, %.{0}f)".format([decimals, decimals]) % [v.x, v.y]


static func format_degrees(radians: float, decimals: int = 1) -> String:
	"""Format radians as degrees string"""
	return "%.{0}f°".format([decimals]) % rad_to_deg(radians)


static func debug_print_tree(root: Node, indent: int = 0) -> String:
	"""Generate string representation of scene tree"""
	var result := ""
	for i in range(indent):
		result += "  "
	result += root.name + " (" + root.get_class() + ")\n"
	for child in root.get_children():
		result += debug_print_tree(child, indent + 1)
	return result


# === Node Helpers ===

static func find_child_by_type(node: Node, type: String, recursive: bool = true) -> Node:
	"""Find first child of given type"""
	for child in node.get_children():
		if child.get_class() == type or child.name == type:
			return child
		if recursive:
			var found := find_child_by_type(child, type, true)
			if found != null:
				return found
	return null


static func get_all_children(node: Node, include_hidden: bool = false) -> Array:
	"""Get all descendants"""
	var result := []
	var queue := [node]
	while queue.size() > 0:
		var current := queue.pop_front()
		for child in current.get_children():
			if include_hidden or child.visible:
				result.append(child)
				queue.append(child)
	return result


static func safe_queue_free(node: Node) -> void:
	"""Safely queue node for deletion (checks if valid first)"""
	if is_instance_valid(node) and is_instance_id_valid(node.get_instance_id()):
		node.queue_free()


static func safe_call(node: Node, method: StringName, args: Array = []) -> Variant:
	"""Safely call method if it exists"""
	if is_instance_valid(node) and node.has_method(method):
		return node.callv(method, args)
	return null


# === Time Helpers ===

static func format_time_seconds(seconds: float, include_days: bool = true) -> String:
	"""Format seconds as time string (D:HH:MM:SS or HH:MM:SS)"""
	var total_seconds := int(absf(seconds))
	var days := total_seconds / 86400
	var hours := (total_seconds % 86400) / 3600
	var minutes := (total_seconds % 3600) / 60
	var secs := total_seconds % 60
	
	if include_days and days > 0:
		return "%d:%02d:%02d:%02d" % [days, hours, minutes, secs]
	return "%02d:%02d:%02d" % [hours, minutes, secs]


static func parse_time_string(time_str: String) -> float:
	"""Parse time string to seconds (D:HH:MM:SS or HH:MM:SS format)"""
	var parts := time_str.split(":")
	var seconds := 0.0
	
	if parts.size() == 4:  # D:HH:MM:SS
		seconds = (float(parts[0]) * 86400) + (float(parts[1]) * 3600) + (float(parts[2]) * 60) + float(parts[3])
	elif parts.size() == 3:  # HH:MM:SS
		seconds = (float(parts[0]) * 3600) + (float(parts[1]) * 60) + float(parts[2])
	elif parts.size() == 2:  # MM:SS
		seconds = (float(parts[0]) * 60) + float(parts[1])
	
	return seconds


func _ready() -> void:
	print("GameUtils: v%s (Build #%d) initialized" % [VERSION, BUILD_NUMBER])