class_name SensorContact
extends RefCounted
## Represents a detected contact in the sensor system
## Tracks contact state, position, velocity, and identification

# Contact identification
var contact_id: int = -1
var object_reference: Node2D = null

# Kinematic data
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var distance_m: float = 0.0
var bearing: float = 0.0  # radians
var closure_rate: float = 0.0  # m/s (negative = approaching)

# Sensor data
var thermal_signature: float = 0.0
var radar_signature: float = 0.0
var is_hostile: bool = false
var is_locked: bool = false

# Identification state
enum IdentificationLevel { UNKNOWN, DETECTED, INVESTIGATING, IDENTIFIED }
var identification_level: int = IdentificationLevel.UNKNOWN
var ship_class: int = 0  # SensorManager.ShipClass
var class_confidence: float = 0.0
var estimated_threat_level: float = 0.0

# Contact tracking
var time_first_detected: float = -1.0
var time_last_detected: float = 0.0
var detection_count: int = 0
var track_quality: float = 0.0  # 0-1, improves with continuous tracking

# History for analysis
var position_history: Array = []  # [{time, position}]
const MAX_HISTORY_SIZE: int = 60  # Keep last 60 samples

# Prediction data
var predicted_position: Vector2 = Vector2.ZERO
var predicted_intercept_time: float = INF
var maneuver_detected: bool = false
var maneuver_count: int = 0

func _init(obj: Node2D = null, dist: float = 0.0) -> void:
	if obj:
		object_reference = obj
		position = obj.global_position if obj is Node2D else Vector2.ZERO
		distance_m = dist

func update_from_scan(obj: Node2D, dist: float, signature: float, pos: Vector2, current_time: float) -> void:
	"""Update contact data from a sensor scan."""
	object_reference = obj
	position = pos
	distance_m = dist
	
	# Update detection timing
	if time_first_detected < 0:
		time_first_detected = current_time
	time_last_detected = current_time
	detection_count += 1
	
	# Update signatures
	thermal_signature = signature if signature >= 0 else thermal_signature
	radar_signature = signature if signature >= 0 else radar_signature
	
	# Calculate bearing
	if object_reference and object_reference is Node2D:
		bearing = (object_reference.global_position - pos).angle()
	
	# Update position history
	_add_to_history(current_time)
	
	# Update track quality
	_update_track_quality()

func update_position(pos: Vector2, vel: Vector2, dist: float, current_time: float) -> void:
	"""Update position and calculate kinematic data."""
	var prev_pos: Vector2 = position
	position = pos
	velocity = vel
	distance_m = dist
	
	# Calculate closure rate from position delta
	if position_history.size() >= 2:
		var prev_sample: Dictionary = position_history[position_history.size() - 2]
		var prev_time: float = prev_sample.get("time", 0.0)
		if current_time > prev_time:
			var dt: float = current_time - prev_time
			if dt > 0:
				var range_delta: float = prev_sample.get("distance", 0.0) - dist
				closure_rate = range_delta / dt
	
	# Update history
	_add_to_history(current_time)
	
	# Detect maneuvers (significant velocity changes)
	_detect_maneuver(prev_pos)
	
	# Update track quality
	_update_track_quality()

func _add_to_history(current_time: float) -> void:
	"""Add current state to position history."""
	position_history.append({
		"time": current_time,
		"position": position,
		"distance": distance_m,
		"velocity": velocity
	})
	
	# Trim history if too long
	while position_history.size() > MAX_HISTORY_SIZE:
		position_history.pop_front()

func _detect_maneuver(prev_pos: Vector2) -> void:
	"""Detect if a maneuver has occurred based on velocity changes."""
	if position_history.size() < 3:
		return
	
	# Get recent velocity samples
	var recent_velocities: Array = []
	for i in range(max(0, position_history.size() - 5), position_history.size()):
		var v: Vector2 = position_history[i].get("velocity", Vector2.ZERO)
		recent_velocities.append(v)
	
	if recent_velocities.size() < 3:
		return
	
	# Calculate velocity variance
	var avg_vel: Vector2 = Vector2.ZERO
	for v in recent_velocities:
		avg_vel += v
	avg_vel /= recent_velocities.size()
	
	var variance: float = 0.0
	for v in recent_velocities:
		variance += (v - avg_vel).length_squared()
	variance /= recent_velocities.size()
	
	# Maneuver detected if significant velocity variance
	if variance > 100.0:  # Threshold for detectable maneuver
		maneuver_detected = true
		maneuver_count += 1

func _update_track_quality() -> void:
	"""Update track quality based on detection continuity."""
	# Quality improves with more detections and less time gap
	var base_quality: float = min(float(detection_count) / 10.0, 1.0)
	
	# Penalize for age (if not recently detected)
	var time_since_last: float = Time.get_ticks_msec() / 1000.0 - time_last_detected
	var recency_factor: float = max(0.0, 1.0 - time_since_last / 60.0)  # Decay over 60 seconds
	
	track_quality = base_quality * recency_factor

func set_identified(ship_class_type: int, confidence: float) -> void:
	"""Mark contact as identified with ship class and confidence."""
	identification_level = IdentificationLevel.IDENTIFIED
	ship_class = ship_class_type
	class_confidence = confidence

func set_investigating() -> void:
	"""Mark contact as under investigation."""
	if identification_level < IdentificationLevel.INVESTIGATING:
		identification_level = IdentificationLevel.INVESTIGATING

func get_age() -> float:
	"""Get age of contact in seconds since first detection."""
	if time_first_detected < 0:
		return 0.0
	return time_last_detected - time_first_detected

func get_distance_string() -> String:
	"""Get formatted distance string."""
	return OrbitalConstants.format_distance(distance_m)

func get_bearing_string() -> float:
	"""Get bearing in degrees (0-360)."""
	var degrees: float = rad_to_deg(bearing)
	if degrees < 0:
		degrees += 360.0
	return degrees

func get_closure_string() -> String:
	"""Get formatted closure rate string."""
	if closure_rate > 0:
		return "+%.0f m/s" % closure_rate
	elif closure_rate < 0:
		return "%.0f m/s" % closure_rate
	return "0 m/s"

func get_track_summary() -> String:
	"""Get a summary string for display."""
	var summary: String = ""
	summary += "DIST: %s\n" % get_distance_string()
	summary += "BRG: %.1fdeg\n" % get_bearing_string()
	summary += "CLOSURE: %s\n" % get_closure_string()
	summary += "TRACK: %.0f%%\n" % (track_quality * 100.0)
	if maneuver_detected:
		summary += "MANVR: %d\n" % maneuver_count
	return summary