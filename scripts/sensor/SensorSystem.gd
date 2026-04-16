# scripts/sensor/SensorSystem.gd
class_name SensorSystem
extends Node2D
## Space sensor detection system for tracking orbital objects
## Supports passive thermal detection and active radar tracking

# Sensor modes
enum SensorMode { THERMAL, RADAR }
var _current_mode: int = SensorMode.THERMAL
var _thermal_range_m: float = 2000000.0  # 2000 km thermal range
var _radar_range_m: float = 5000000.0    # 5000 km radar range
var _radar_active: bool = false

# Sensor state
var _detected_contacts: Array = []
var _sensor_range_m: float = 1000000.0  # Default 1000 km
var _owner_ship: Ship = null

# Lock state
var _locked_target: Node2D = null
var _lock_acquisition_time: float = 0.0
var _lock_time_required: float = 2.0  # seconds to acquire lock

# Countermeasures state
var _countermeasures_active: bool = false
var _chaff_deployed: bool = false
var _chaff_count: int = 10
var _decoy_count: int = 5

# Registered missiles that will receive countermeasure effects
var _registered_missiles: Array = []

signal contact_detected(contact: Dictionary)
signal contact_locked(target: Node2D)
signal lock_lost(target: Node2D)
signal sensor_mode_changed(mode: int)
signal chaff_deployed(count: int)
signal decoy_deployed(count: int)
signal countermeasures_depleted(type: String)

func _ready() -> void:
	# Get owning ship reference
	_owner_ship = get_parent() as Ship
	_update_sensor_range()

func _process(delta: float) -> void:
	# Update lock acquisition
	if _locked_target and _radar_active:
		_lock_acquisition_time += delta
		if _lock_acquisition_time >= _lock_time_required:
			_lock_target_fully()
	elif _locked_target and not _radar_active:
		# Lost lock when radar turned off
		_unlock_target()

func set_sensor_mode(mode: int) -> void:
	"""Set thermal (passive) or radar (active) mode."""
	if mode != _current_mode:
		_current_mode = mode
		_update_sensor_range()
		# Radar deactivates on mode change (radar is toggled separately)
		sensor_mode_changed.emit(_current_mode)

func toggle_radar(active: bool) -> void:
	"""Toggle radar active mode (reveals position to targets)."""
	if _radar_active != active:
		_radar_active = active
		# Clear lock when radar deactivated
		if not active and _locked_target:
			_unlock_target()

func _update_sensor_range() -> void:
	"""Update detection range based on current mode."""
	match _current_mode:
		SensorMode.THERMAL:
			_sensor_range_m = _thermal_range_m
		SensorMode.RADAR:
			_sensor_range_m = _radar_range_m

func _lock_target_fully() -> void:
	"""Complete lock acquisition."""
	if _locked_target:
		contact_locked.emit(_locked_target)

func _unlock_target() -> void:
	"""Release current lock."""
	var lost_target = _locked_target
	_locked_target = null
	_lock_acquisition_time = 0.0
	if lost_target:
		lock_lost.emit(lost_target)

func scan() -> Array:
	_detected_contacts.clear()
	
	# Get all orbital objects in scene
	var objects = get_tree().get_nodes_in_group("orbital_object")
	
	for obj in objects:
		# Skip self
		if obj == _owner_ship:
			continue
		
		# Calculate distance
		var distance_m: float
		if obj is Node2D:
			distance_m = _owner_ship.global_position.distance_to(obj.global_position)
		else:
			continue
		
		# Check if within detection range
		if distance_m <= _sensor_range_m:
			# Check line-of-sight occlusion (planet horizon blocking)
			if not _has_line_of_sight(obj):
				continue
			
			var signature = _calculate_detection_signature(obj, distance_m)
			
			# Only add if above noise floor
			if signature > 0.01:
				_detected_contacts.append({
					"object": obj,
					"distance_m": distance_m,
					"signature": signature,
					"position": obj.global_position if obj is Node2D else Vector2.ZERO
				})
	
	return _detected_contacts


func _has_line_of_sight(target: Node2D) -> bool:
	## Check if target is occluded by any celestial body
	## Uses ray intersection to detect horizon blocking
	
	if not _owner_ship:
		return true
	
	var ship_pos: Vector2 = _owner_ship.global_position
	var target_pos: Vector2 = target.global_position
	
	# Get all celestial bodies (planets, moons, sun)
	var bodies = get_tree().get_nodes_in_group("celestial_body")
	
	for body in bodies:
		if not body is Node2D:
			continue
		
		# Skip if body is too close to either endpoint
		var body_pos: Vector2 = body.global_position
		var body_radius: float = 100000.0  # Default 100km radius
		
		if body.has("radius"):
			body_radius = body.radius
		elif body.has("sphere_of_influence"):
			body_radius = max(body_radius, body.sphere_of_influence * 0.1)
		
		# Distance from body center to ship
		var dist_to_ship: float = body_pos.distance_to(ship_pos)
		if dist_to_ship < body_radius:
			continue  # We're inside the body, shouldn't happen
		
		# Distance from body center to target
		var dist_to_target: float = body_pos.distance_to(target_pos)
		if dist_to_target < body_radius:
			continue  # Target is inside body
		
		# Calculate closest approach of line to body center
		var line_dir: Vector2 = (target_pos - ship_pos).normalized()
		var to_body: Vector2 = body_pos - ship_pos
		var projection: float = to_body.dot(line_dir)
		
		# Only check if body is between ship and target
		var total_dist: float = ship_pos.distance_to(target_pos)
		if projection < 0 or projection > total_dist:
			continue
		
		# Closest point on line to body center
		var closest_point: Vector2 = ship_pos + line_dir * projection
		var closest_dist: float = closest_point.distance_to(body_pos)
		
		# Occluded if closest approach is within body radius
		if closest_dist < body_radius:
			return false  # Blocked by horizon
	
	return true  # Clear line of sight

func _calculate_detection_signature(obj, distance_m: float) -> float:
	## Calculate detection probability based on distance
	## Uses inverse square falloff with noise floor
	
	var base_signature: float = 1.0
	
	# Apply object-specific modifiers
	if obj.has_method("get_sensor_signature"):
		base_signature = obj.get_sensor_signature()
	
	# Range attenuation (inverse square law)
	var range_ratio: float = _sensor_range_m / max(distance_m, 1.0)
	var attenuation: float = range_ratio * range_ratio
	
	return base_signature * attenuation

func set_range_m(range_m: float) -> void:
	_sensor_range_m = max(0.0, range_m)

func get_contacts() -> Array:
	return _detected_contacts.duplicate()

func get_contact_count() -> int:
	return _detected_contacts.size()

func get_current_mode() -> int:
	return _current_mode

func is_radar_active() -> bool:
	return _radar_active

func get_locked_target() -> Node2D:
	return _locked_target

func is_locked() -> bool:
	return _locked_target != null

func acquire_lock(target: Node2D) -> void:
	"""Start acquiring a lock on a target."""
	if _radar_active:
		_locked_target = target
		_lock_acquisition_time = 0.0

func release_lock() -> void:
	"""Release current lock."""
	_unlock_target()

# Countermeasures methods
func deploy_chaff() -> bool:
	"""Deploy chaff to confuse enemy radar. Returns success."""
	if _chaff_count > 0:
		_chaff_count -= 1
		_chaff_deployed = true
		_countermeasures_active = true
		chaff_deployed.emit(_chaff_count)
		return true
	else:
		countermeasures_depleted.emit("chaff")
		return false

func deploy_decoy() -> bool:
	"""Deploy thermal decoy to distract heat-seeking weapons. Returns success."""
	if _decoy_count > 0:
		_decoy_count -= 1
		_countermeasures_active = true
		decoy_deployed.emit(_decoy_count)
		return true
	else:
		countermeasures_depleted.emit("decoy")
		return false

func get_chaff_count() -> int:
	return _chaff_count

func get_decoy_count() -> int:
	return _decoy_count

func get_countermeasure_type() -> String:
	"""Get the name of the available countermeasure type."""
	if _chaff_count > 0:
		return "chaff"
	elif _decoy_count > 0:
		return "decoy"
	return "none"

func is_countermeasure_available() -> bool:
	"""Check if any countermeasures are available."""
	return _chaff_count > 0 or _decoy_count > 0

func recharge_countermeasures(chaff: int = 0, decoys: int = 0) -> void:
	"""Replenish countermeasure supplies (e.g., during rearm)."""
	_chaff_count += chaff
	_decoy_count += decoys

# Missile registration for countermeasure effects
func register_missile(missile: Node) -> void:
	"""Register a missile to receive countermeasure effects."""
	if not _registered_missiles.has(missile):
		_registered_missiles.append(missile)

func unregister_missile(missile: Node) -> void:
	"""Remove missile from countermeasure tracking."""
	_registered_missiles.erase(missile)

func get_active_countermeasures() -> Dictionary:
	"""Get current active countermeasure state for UI."""
	return {
		"chaff_active": _chaff_deployed,
		"chaff_remaining": _chaff_count,
		"decoy_active": _countermeasures_active and not _chaff_deployed,
		"decoy_remaining": _decoy_count,
		"any_active": _countermeasures_active
	}