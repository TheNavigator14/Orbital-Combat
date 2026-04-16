class_name Missile
extends Node2D
## Physicalized missile with orbital mechanics and guidance
## Supports multiple missile types and launch profiles

signal missile_launched(missile: Missile)
signal missile_exploded(missile: Missile, hit_target: bool)
signal target_acquired(target: Node2D)
signal fuel_depleted()
signal flight_profile_changed(profile: String)

# === Missile Types ===
enum MissileType {
	SHORT_RANGE = 0,   # Quick intercept, limited delta-v
	LONG_RANGE = 1,     # Extended range, higher delta-v
	BALLISTIC = 2,      # No thrust, purely orbital trajectory
	SHIP_TO_SHIP = 3,   # Anti-ship weapon
	ANTI_MISSILE = 4    # PD interceptor
}

# === Launch Profiles ===
enum LaunchProfile {
	IMMEDIATE_BURN = 0,   # Boost immediately toward target
	COAST_TO_APOAPSIS = 1, # Coast to high point, then burn
	TANGENTIAL_BURN = 2,   # Burn perpendicular to reduce detection
}

# === Missile State ===
enum FlightState {
	STANDBY = 0,      # Loaded, waiting for launch
	BOOST = 1,         # Initial boost phase
	COAST = 2,         # Ballistic coast
	TERMINAL = 3,      # Terminal guidance active
	EXPLODED = 4,      # Impact or self-destruct
}

# === Configuration ===
@export var missile_type: MissileType = MissileType.SHORT_RANGE
@export var max_thrust: float = 50000.0  # Newtons
@export var exhaust_velocity: float = 3000.0  # m/s (lower Isp for missiles)
@export var fuel_capacity: float = 100.0  # kg
@export var warhead_yield: float = 1.0  # Relative damage

# Type-specific configurations
@export var detection_radius: float = 100.0  # meters - how close to target before explosion
@export var terminal_guidance_range: float = 50000.0  # meters - range to activate terminal guidance

# === State ===
var fuel_mass: float = 0.0  # Current fuel in kg
var flight_state: FlightState = FlightState.STANDBY
var launch_profile: LaunchProfile = LaunchProfile.IMMEDIATE_BURN

# === Orbital Mechanics ===
var position: Vector2 = Vector2.ZERO  # World position
var velocity: Vector2 = Vector2.ZERO   # Velocity vector
var orbit_state: OrbitState = null  # For orbital propagation reference
var parent_body: CelestialBody = null  # Current gravitational parent

# === Guidance ===
var target: Node2D = null  # Target to track
var launch_position: Vector2 = Vector2.ZERO
var launch_velocity: Vector2 = Vector2.ZERO
var initial_delta_v: float = 0.0  # Boost delta-v

# === Tracking ===
var flight_time: float = 0.0  # Time since launch
var max_flight_time: float = 300.0  # Self-destruct after this time

# === Health & Damage ===
var health: float = 100.0  # Health points
var max_health: float = 100.0
var is_destroyed: bool = false

# === Countermeasure Tracking ===
var _countermeasures_active: bool = false
var _chaff_confusion_factor: float = 0.0  # 0-1, reduces tracking accuracy
var _decoy_offset: Vector2 = Vector2.ZERO  # Offset from actual target position
var _countermeasure_duration: float = 3.0  # Countermeasures last 3 seconds
var _countermeasure_timer: float = 0.0  # Time remaining for current effect

func take_pdc_hit(damage: float) -> bool:
	## Handle being hit by PDC rounds
	## Returns true if missile is destroyed
	if is_destroyed:
		return false
	
	health -= damage
	print("Missile hit by PDC: damage=", damage, ", remaining health=", health)
	
	if health <= 0:
		is_destroyed = true
		_explode(false)  # Don't count as successful hit
		return true
	
	return false


# === Countermeasure Response ===

func apply_chaff(confusion: float) -> void:
	"""Apply radar confusion from chaff. Target tracking is degraded."""
	_countermeasures_active = true
	_chaff_confusion_factor = clamp(_chaff_confusion_factor + confusion, 0.0, 0.9)
	# Apply random offset to tracking based on confusion level
	var offset_magnitude = 5000.0 * _chaff_confusion_factor  # Up to 5km offset
	_decoy_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * offset_magnitude
	print("Missile confused by chaff: confusion=", _chaff_confusion_factor)


func apply_decoy() -> void:
	"""Apply thermal decoy distraction. Missile targets decoy position instead."""
	_countermeasures_active = true
	_chaff_confusion_factor = clamp(_chaff_confusion_factor + 0.3, 0.0, 0.9)
	# Large offset when decoy deployed
	_decoy_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 15000.0
	print("Missile distracted by decoy: offset=", _decoy_offset)


func is_confused() -> bool:
	"""Returns true if tracking is currently degraded by countermeasures."""
	return _countermeasures_active


func get_tracking_offset() -> Vector2:
	"""Get the position offset caused by countermeasures."""
	return _decoy_offset

func _update_countermeasures(delta: float) -> void:
	"""Update countermeasure effect timer."""
	if not _countermeasures_active:
		return
	
	_countermeasure_timer -= delta
	if _countermeasure_timer <= 0:
		# Clear countermeasure effects
		_countermeasures_active = false
		_chaff_confusion_factor = 0.0
		_decoy_offset = Vector2.ZERO
		print("Missile countermeasure effect expired")


func get_health_percent() -> float:
	## Get health as percentage
	return clamp(health / max_health, 0.0, 1.0)


# === Computed Properties ===
var total_mass: float:
	get:
		# Assume small warhead mass
		return 50.0 + fuel_mass  # 50kg dry mass (warhead + structure)

var current_delta_v: float:
	get:
		if fuel_mass <= 0:
			return 0.0
		return exhaust_velocity * log((50.0 + fuel_mass) / 50.0)

var fuel_percent: float:
	get:
		if fuel_capacity <= 0:
			return 0.0
		return clamp(fuel_mass / fuel_capacity, 0.0, 1.0)

# === Type Configuration ===

func _ready() -> void:
	# Initialize based on missile type
	_configure_for_type()
	fuel_mass = fuel_capacity


func _configure_for_type() -> void:
	## Set default parameters based on missile type
	match missile_type:
		MissileType.SHORT_RANGE:
			max_thrust = 40000.0
			exhaust_velocity = 2800.0
			fuel_capacity = 80.0
			warhead_yield = 0.8
			detection_radius = 150.0
			terminal_guidance_range = 30000.0
			max_flight_time = 120.0
			
		MissileType.LONG_RANGE:
			max_thrust = 30000.0
			exhaust_velocity = 3200.0
			fuel_capacity = 150.0
			warhead_yield = 1.2
			detection_radius = 100.0
			terminal_guidance_range = 100000.0
			max_flight_time = 600.0
			
		MissileType.BALLISTIC:
			max_thrust = 0.0
			exhaust_velocity = 0.0
			fuel_capacity = 0.0
			warhead_yield = 1.5
			detection_radius = 200.0
			terminal_guidance_range = 0.0
			max_flight_time = 3600.0
			
		MissileType.SHIP_TO_SHIP:
			max_thrust = 50000.0
			exhaust_velocity = 3000.0
			fuel_capacity = 120.0
			warhead_yield = 2.0
			detection_radius = 80.0
			terminal_guidance_range = 50000.0
			max_flight_time = 180.0
			
		MissileType.ANTI_MISSILE:
			max_thrust = 60000.0
			exhaust_velocity = 3500.0
			fuel_capacity = 50.0
			warhead_yield = 0.5
			detection_radius = 50.0
			terminal_guidance_range = 20000.0
			max_flight_time = 60.0


# === Launch Methods ===

func launch(target_node: Node2D, profile: LaunchProfile = LaunchProfile.IMMEDIATE_BURN,
		launch_pos: Vector2 = Vector2.ZERO, launch_vel: Vector2 = Vector2.ZERO) -> bool:
	## Launch the missile at a target with given profile
	if flight_state != FlightState.STANDBY:
		push_warning("Missile: Already launched")
		return false
	
	if target_node == null:
		push_warning("Missile: No target specified")
		return false
	
	target = target_node
	launch_profile = profile
	launch_position = launch_pos if launch_pos != Vector2.ZERO else position
	launch_velocity = launch_vel if launch_vel != Vector2.ZERO else velocity
	
	# Set initial state
	position = launch_position
	velocity = launch_velocity
	
	# Apply launch profile delta-v
	match profile:
		LaunchProfile.IMMEDIATE_BURN:
			_apply_immediate_burn_profile()
		LaunchProfile.COAST_TO_APOAPSIS:
			_apply_coast_profile()
		LaunchProfile.TANGENTIAL_BURN:
			_apply_tangential_profile()
	
	flight_state = FlightState.BOOST
	flight_time = 0.0
	
	missile_launched.emit(self)
	print("Missile launched: ", get_missile_type_name(), " at ", target.name if target else "unknown")
	
	return true


func _apply_immediate_burn_profile() -> void:
	## Apply immediate thrust toward target
	if missile_type == MissileType.BALLISTIC:
		flight_state = FlightState.COAST
		flight_profile_changed.emit("ballistic")
		return
	
	var target_pos = _get_target_position()
	if target_pos == Vector2.ZERO:
		return
	
	# Calculate intercept vector (prograde toward target's predicted position)
	var to_target = (target_pos - position).normalized()
	
	# Calculate boost delta-v (use available fuel efficiently)
	var burn_delta_v = min(current_delta_v, 500.0)  # Max 500 m/s initial burn
	
	if burn_delta_v > 0 and fuel_mass > 0:
		velocity += to_target * burn_delta_v
		_consume_fuel_for_delta_v(burn_delta_v)
	
	flight_state = FlightState.BOOST
	flight_profile_changed.emit("immediate_burn")


func _apply_coast_profile() -> void:
	## Coast in orbit, burn at apoapsis for maximum range
	if missile_type == MissileType.BALLISTIC:
		flight_state = FlightState.COAST
		flight_profile_changed.emit("ballistic")
		return
	
	# No initial burn - coast on ballistic trajectory
	flight_state = FlightState.COAST
	flight_profile_changed.emit("coast_to_apoapsis")


func _apply_tangential_profile() -> void:
	## Burn perpendicular to reduce thermal signature
	if missile_type == MissileType.BALLISTIC:
		flight_state = FlightState.COAST
		flight_profile_changed.emit("ballistic")
		return
	
	var target_pos = _get_target_position()
	if target_pos == Vector2.ZERO:
		_apply_immediate_burn_profile()
		return
	
	# Burn perpendicular (radial out)
	var radial_out = position.normalized()
	if velocity.length_squared() > 1.0:
		radial_out = velocity.orthogonal().normalized()
	
	var burn_delta_v = min(current_delta_v * 0.5, 200.0)  # Smaller burn
	
	if burn_delta_v > 0 and fuel_mass > 0:
		velocity += radial_out * burn_delta_v
		_consume_fuel_for_delta_v(burn_delta_v)
	
	flight_state = FlightState.BOOST
	flight_profile_changed.emit("tangential_burn")


# === Physics Update ===

func _physics_process(delta: float) -> void:
	if flight_state == FlightState.STANDBY or flight_state == FlightState.EXPLODED:
		return
	
	flight_time += delta
	
	# Check for self-destruct timeout
	if flight_time > max_flight_time:
		_explode(false)
		return
	
	# Update based on flight state
	match flight_state:
		FlightState.BOOST:
			_update_boost_phase(delta)
		FlightState.COAST:
			_update_coast_phase(delta)
		FlightState.TERMINAL:
			_update_terminal_phase(delta)
	
	# Check for target proximity
	if target != null:
		var distance_to_target = position.distance_to(_get_target_position())
		if distance_to_target < detection_radius:
			_explode(true)
			return
		
		# Activate terminal guidance when in range
		if flight_state == FlightState.COAST and distance_to_target < terminal_guidance_range:
			if fuel_mass > 0:
				flight_state = FlightState.TERMINAL
				print("Missile: Terminal guidance activated at ", distance_to_target)
	
	# Propagate position
	_propagate_orbit(delta)


func _update_boost_phase(delta: float) -> void:
	## Boost phase - continue thrust if fuel remains
	if missile_type == MissileType.BALLISTIC:
		flight_state = FlightState.COAST
		return
	
	if fuel_mass <= 0:
		flight_state = FlightState.COAST
		return
	
	# Continue thrust toward target (but less aggressive)
	_apply_thrust_toward_target(delta, 0.3)


func _update_coast_phase(delta: float) -> void:
	## Coast phase - ballistic flight with optional mid-course corrections
	if target == null or fuel_mass <= 0:
		return
	
	# Periodic mid-course correction
	var distance_to_target = position.distance_to(_get_target_position())
	if distance_to_target > terminal_guidance_range:
		# Occasional correction burns
		if fmod(flight_time, 10.0) < delta:  # Every ~10 seconds
			_apply_small_correction()


func _update_terminal_phase(delta: float) -> void:
	## Terminal guidance - aggressive pursuit
	if fuel_mass <= 0:
		flight_state = FlightState.COAST
		return
	
	_apply_thrust_toward_target(delta, 1.0)


# === Thrust Application ===

func _apply_thrust_toward_target(delta: float, intensity: float) -> void:
	## Apply thrust toward target position
	var target_pos = _get_target_position()
	if target_pos == Vector2.ZERO:
		return
	
	var to_target = (target_pos - position)
	var distance = to_target.length()
	if distance < 1.0:
		return
	
	to_target = to_target.normalized()
	
	# Calculate required thrust
	var thrust_magnitude = max_thrust * intensity
	
	# Calculate fuel consumption
	var fuel_flow = thrust_magnitude / (exhaust_velocity + 0.001)
	var fuel_used = min(fuel_flow * delta, fuel_mass)
	
	if fuel_used > 0:
		fuel_mass -= fuel_used
		# Apply acceleration
		var acceleration = to_target * (thrust_magnitude / total_mass)
		velocity += acceleration * delta
		
		# Check for fuel depletion
		if fuel_mass <= 0:
			fuel_mass = 0
			flight_state = FlightState.COAST
			fuel_depleted.emit()


func _apply_small_correction() -> void:
	## Apply small mid-course correction burn
	var target_pos = _get_target_position()
	if target_pos == Vector2.ZERO or fuel_mass <= 0:
		return
	
	var to_target = (target_pos - position).normalized()
	
	# Small correction burn
	var correction_delta_v = min(current_delta_v * 0.1, 50.0)  # 10% of remaining or 50 m/s
	if correction_delta_v > 1.0 and fuel_mass > 0:
		velocity += to_target * correction_delta_v
		_consume_fuel_for_delta_v(correction_delta_v)


func _consume_fuel_for_delta_v(dv: float) -> void:
	## Consume fuel mass to produce delta-v
	# Tsiolkovsky: dv = v_e * ln(m0/mf)
	# Solving for mf: mf = m0 / exp(dv / v_e)
	var m0 = 50.0 + fuel_mass
	var mf = m0 / exp(dv / exhaust_velocity)
	var fuel_consumed = m0 - mf
	fuel_mass = max(0, fuel_mass - fuel_consumed)


# === Orbital Propagation ===

func _propagate_orbit(delta: float) -> void:
	## Propagate missile position using RK4 integration
	if parent_body == null:
		# Default to solar gravity
		_propagate_solar_system(delta)
		return
	
	# Get gravitational parameter
	var mu = parent_body.mu if parent_body.has_method("get") and parent_body.get("mu") else OrbitalConstants.SUN_MU
	
	# RK4 integration step
	var state = OrbitalMechanics.rk4_step(position, velocity, mu, delta)
	position = state.position
	velocity = state.velocity


func _propagate_solar_system(delta: float) -> void:
	## Fallback propagation for solar system gravity
	var mu = OrbitalConstants.SUN_MU
	
	# Simple gravitational acceleration
	var r = position.length()
	if r < 1.0:
		return
	
	var gravity = -mu / (r * r * r) * position
	velocity += gravity * delta
	position += velocity * delta


# === Target Tracking ===

func _get_target_position() -> Vector2:
	## Get target's current world position
	if target == null:
		return Vector2.ZERO
	
	if target is Ship:
		return target.world_position
	elif target.has("position"):
		return target.position
	else:
		return Vector2.ZERO


func update_target_position(new_target: Node2D) -> void:
	## Update the target being tracked
	target = new_target
	if target != null:
		target_acquired.emit(target)


# === Explosion ===

func _explode(hit_target: bool) -> void:
	## Detonate the missile
	flight_state = FlightState.EXPLODED
	
	# Apply damage to target if we have one
	if target != null and is_instance_valid(target):
		var damage_amount = warhead_yield * 50.0  # Base damage scaled by yield
		if target.has_method("take_damage"):
			target.take_damage(damage_amount)
			print("Missile ", get_missile_type_name(), " dealt ", damage_amount, " damage to target")
	
	missile_exploded.emit(self, hit_target)
	print("Missile exploded: ", get_missile_type_name(), " (hit=", hit_target, ")")
	
	# Remove from scene after a short delay
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self):
		queue_free()


# === Utility Methods ===

func get_missile_type_name() -> String:
	## Get human-readable missile type name
	match missile_type:
		MissileType.SHORT_RANGE:
			return "Short-Range"
		MissileType.LONG_RANGE:
			return "Long-Range"
		MissileType.BALLISTIC:
			return "Ballistic"
		MissileType.SHIP_TO_SHIP:
			return "Ship-to-Ship"
		MissileType.ANTI_MISSILE:
			return "Anti-Missile"
		_:
			return "Unknown"


func get_state_name() -> String:
	## Get human-readable flight state
	match flight_state:
		FlightState.STANDBY:
			return "Standby"
		FlightState.BOOST:
			return "Boost"
		FlightState.COAST:
			return "Coasting"
		FlightState.TERMINAL:
			return "Terminal"
		FlightState.EXPLODED:
			return "Exploded"
		_:
			return "Unknown"


func get_flight_data() -> Dictionary:
	## Get current flight data for UI display
	return {
		"type": get_missile_type_name(),
		"state": get_state_name(),
		"flight_time": flight_time,
		"fuel_percent": fuel_percent * 100.0,
		"delta_v_remaining": current_delta_v,
		"distance_to_target": position.distance_to(_get_target_position()) if target else INF,
		"warhead_yield": warhead_yield
	}


# === Heat Signature (for detection) ===

func get_thermal_signature() -> float:
	## Get thermal signature when boosting (1.0) vs coasting (0.2)
	if flight_state == FlightState.BOOST or flight_state == FlightState.TERMINAL:
		return 1.0
	return 0.2


func get_detection_radius() -> float:
	## Get detection radius for radar/thermal
	if flight_state == FlightState.BOOST or flight_state == FlightState.TERMINAL:
		return 2000.0  # Easily detectable when thrusting
	return 500.0  # Small when coasting