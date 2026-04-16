class_name EnemyAIShip
extends Ship
## AI-controlled enemy ship with patrol and intercept behaviors
## Uses sensor detection to find targets and orbital mechanics for pursuit

signal ai_state_changed(from_state: int, to_state: int)
signal target_acquired(target: Node2D)
signal target_lost()
signal patrol_started()
signal intercept_started()
signal engagement_started()
signal evading()

# === AI States ===
enum AIState {
	IDLE = 0,
	PATROL = 1,
	TRANSIT = 2,
	TRACKING = 3,
	INTERCEPTING = 4,
	ENGAGED = 5,
	EVALUATING = 6,
	EVADING = 7,
	RETURNING = 8,
}

# === Configuration ===
@export var reaction_time: float = 2.0
@export var patrol_radius: float = 500000.0
@export var intercept_distance: float = 100000.0
@export var engagement_range: float = 50000.0
@export var disengage_threshold: float = 200000.0
@export var evade_health_threshold: float = 0.3

@export var detection_reaction_time: float = 3.0
@export var lock_on_time: float = 5.0
@export var firing_range: float = 30000.0

@export var min_patrol_altitude: float = 200000.0
@export var max_patrol_altitude: float = 800000.0

@export var aggressive: bool = false
@export var patient: bool = true
@export var evasive: bool = true

@export var patrol_pattern: int = 0
@export var patrol_center: Vector2 = Vector2.ZERO

# === State ===
var ai_state: AIState = AIState.IDLE
var previous_state: AIState = AIState.IDLE
var state_timer: float = 0.0
var reaction_timer: float = 0.0
var lock_on_timer: float = 0.0
var has_lock: bool = false

var detected_targets: Array = []
var primary_target: Node2D = null

var patrol_center_body: CelestialBody = null
var patrol_orbit: OrbitState = null
var patrol_waypoints: Array = []
var current_waypoint_index: int = 0

var is_in_combat: bool = false
var missiles_launched: Array = []
var pdc_enabled: bool = true
var last_combat_time: float = 0.0

var evasion_pattern: int = 0
var evasion_timer: float = 0.0
var evasion_duration: float = 10.0

var awareness_level: float = 0.0
var threat_assessment_timer: float = 0.0

# === Threat Tracking ===
var incoming_missiles: Array = []
var missile_threat_timer: float = 0.0
var last_evasion_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	ship_name = "Enemy Ship"
	setup_ai_sensors()
	set_ai_state(AIState.PATROL)
	print("EnemyAIShip: Initialized - ", ship_name)


func setup_ai_sensors() -> void:
	current_heat_output = 0.3


func set_ai_state(new_state: int) -> void:
	if new_state == ai_state:
		return
	
	previous_state = ai_state
	ai_state = new_state
	state_timer = 0.0
	
	match new_state:
		AIState.PATROL:
			_start_patrol()
		AIState.TRANSIT:
			_start_transit()
		AIState.TRACKING:
			_start_tracking()
		AIState.INTERCEPTING:
			_start_intercept()
		AIState.ENGAGED:
			_start_engagement()
		AIState.EVALUATING:
			_start_evaluation()
		AIState.EVADING:
			_start_evasion()
		AIState.RETURNING:
			_start_return()
	
	ai_state_changed.emit(previous_state, new_state)
	print("EnemyAIShip %s: State %s -> %s" % [ship_name, _get_state_name(previous_state), _get_state_name(new_state)])


func _get_state_name(state: int) -> String:
	match state:
		AIState.IDLE: return "IDLE"
		AIState.PATROL: return "PATROL"
		AIState.TRANSIT: return "TRANSIT"
		AIState.TRACKING: return "TRACKING"
		AIState.INTERCEPTING: return "INTERCEPTING"
		AIState.ENGAGED: return "ENGAGED"
		AIState.EVALUATING: return "EVALUATING"
		AIState.EVADING: return "EVADING"
		AIState.RETURNING: return "RETURNING"
	return "UNKNOWN"


func _start_patrol() -> void:
	patrol_center_body = parent_body
	patrol_center = parent_body.world_position if parent_body else Vector2.ZERO
	
	if parent_body != null:
		var random_altitude = randf_range(min_patrol_altitude, max_patrol_altitude)
		_create_patrol_orbit(parent_body.radius + random_altitude)
	
	patrol_started.emit()
	is_in_combat = false
	_set_weapons_enabled(false)


func _start_transit() -> void:
	if primary_target != null:
		_calculate_intercept_trajectory()


func _start_tracking() -> void:
	reaction_timer = 0.0
	target_acquired.emit(primary_target)


func _start_intercept() -> void:
	intercept_started.emit()
	_set_weapons_enabled(true)
	is_in_combat = true


func _start_engagement() -> void:
	engagement_started.emit()
	has_lock = false
	lock_on_timer = 0.0
	_set_weapons_enabled(true)
	is_in_combat = true


func _start_evaluation() -> void:
	primary_target = null
	has_lock = false
	_set_weapons_enabled(false)


func _start_evasion() -> void:
	evasion_timer = 0.0
	evading.emit()
	_set_weapons_enabled(true)
	is_in_combat = true


func _start_return() -> void:
	primary_target = null
	has_lock = false
	_set_weapons_enabled(false)


func _set_weapons_enabled(enabled: bool) -> void:
	if pdc:
		pdc.set_auto_fire(enabled)
		pdc.set_powered(enabled)


func _process_patrol(delta: float) -> void:
	if primary_target != null:
		set_ai_state(AIState.TRACKING)
		return
	
	match patrol_pattern:
		0:
			_maintain_circular_patrol(delta)
		1:
			_maintain_figure8_patrol(delta)
		2:
			_maintain_varying_patrol(delta)


func _maintain_circular_patrol(delta: float) -> void:
	if patrol_center_body == null:
		patrol_center_body = parent_body
	
	var orbit_radius = patrol_radius
	var orbit_angle = state_timer * 0.001
	
	var target_pos = patrol_center_body.world_position + Vector2(
		cos(orbit_angle) * orbit_radius,
		sin(orbit_angle) * orbit_radius
	)
	
	if orbit_state == null or orbit_state.semi_major_axis < orbit_radius * 0.9:
		_create_patrol_orbit(orbit_radius)
		return
	
	var distance_error = orbit_state.position.length() - orbit_radius
	var thrust_direction = _get_prograde_direction()
	
	if abs(distance_error) > 50000:
		if distance_error > 0:
			thrust_direction = _get_prograde_direction()
		else:
			thrust_direction = -_get_prograde_direction()
	
	_apply_orbital_thrust(thrust_direction, 0.3)


func _maintain_figure8_patrol(delta: float) -> void:
	if patrol_waypoints.size() < 2:
		_generate_figure8_waypoints()
	
	if current_waypoint_index >= patrol_waypoints.size():
		current_waypoint_index = 0
	
	var target_pos = patrol_waypoints[current_waypoint_index]
	var distance = world_position.distance_to(target_pos)
	
	if distance < 50000:
		current_waypoint_index += 1
		if current_waypoint_index >= patrol_waypoints.size():
			current_waypoint_index = 0
	
	if distance > 10000:
		var to_target = (target_pos - world_position).normalized()
		var prograde_dir = _get_prograde_direction()
		var thrust_dir = _blend_thrust_direction(to_target, prograde_dir, 0.7)
		_apply_orbital_thrust(thrust_dir, 0.4)


func _maintain_varying_patrol(delta: float) -> void:
	var base_radius = patrol_radius
	var altitude_variation = sin(state_timer * 0.0002) * 100000.0
	var current_target_radius = base_radius + altitude_variation
	
	var orbit_radius = current_target_radius
	var orbit_angle = state_timer * 0.001
	
	if patrol_center_body == null:
		patrol_center_body = parent_body
	
	_maintain_circular_patrol(delta)


func _generate_figure8_waypoints() -> void:
	patrol_waypoints.clear()
	
	var num_points = 8
	for i in range(num_points):
		var t = float(i) / float(num_points) * TAU
		var x = 2.0 * cos(t) / (1.0 + sin(t) * sin(t))
		var y = 2.0 * sin(t) * cos(t) / (1.0 + sin(t) * sin(t))
		
		var waypoint = Vector2(x, y) * (patrol_radius / 2.0)
		if parent_body:
			waypoint += parent_body.world_position
		
		patrol_waypoints.append(waypoint)


func _process_transit(delta: float) -> void:
	if primary_target == null:
		set_ai_state(AIState.PATROL)
		return
	
	_calculate_intercept_trajectory()
	
	var distance = world_position.distance_to(primary_target.world_position if primary_target else Vector2.ZERO)
	if distance < intercept_distance * 0.5:
		set_ai_state(AIState.TRACKING)


func _process_tracking(delta: float) -> void:
	if primary_target == null or not is_instance_valid(primary_target):
		set_ai_state(AIState.PATROL)
		return
	
	reaction_timer += delta
	
	var distance = world_position.distance_to(primary_target.world_position if primary_target else Vector2.ZERO)
	
	if reaction_timer >= detection_reaction_time:
		if distance < engagement_range:
			set_ai_state(AIState.ENGAGED)
		elif distance < intercept_distance:
			set_ai_state(AIState.INTERCEPTING)


func _process_intercept(delta: float) -> void:
	if primary_target == null or not is_instance_valid(primary_target):
		set_ai_state(AIState.EVALUATING)
		return
	
	var distance = world_position.distance_to(primary_target.world_position if primary_target else Vector2.ZERO)
	
	_calculate_intercept_trajectory()
	
	if distance < engagement_range:
		set_ai_state(AIState.ENGAGED)
		return
	
	if distance > intercept_distance * 2:
		set_ai_state(AIState.EVALUATING)


func _process_engaged(delta: float) -> void:
	if primary_target == null or not is_instance_valid(primary_target):
		set_ai_state(AIState.EVALUATING)
		return
	
	var distance = world_position.distance_to(primary_target.world_position if primary_target else Vector2.ZERO)
	
	if distance > firing_range * 1.5:
		_calculate_intercept_trajectory()
		_apply_orbital_thrust(_get_prograde_direction(), 0.8)
	elif distance < firing_range * 0.3:
		_apply_orbital_thrust(_get_radial_direction() * -1, 0.5)
	else:
		_maintain_weapons_range(distance)
	
	_engage_target(distance)
	
	if distance > disengage_threshold * 1.5:
		set_ai_state(AIState.EVALUATING)
	
	if evasive and health < max_health * evade_health_threshold:
		set_ai_state(AIState.EVADING)


func _maintain_weapons_range(distance: float) -> void:
	pass


func _engage_target(distance: float) -> void:
	if not has_lock:
		lock_on_timer += 0.016
		if lock_on_timer >= lock_on_time:
			has_lock = true
			print("EnemyAIShip %s: Weapons locked on target" % ship_name)
		return
	
	if distance < firing_range and distance > engagement_range * 0.5:
		_fire_at_will()


func _fire_at_will() -> void:
	if has_combat_systems() and missile_launcher != null:
		var launcher = get_missile_launcher()
		if launcher.get_missiles_in_rack() > 0:
			launcher.fire(primary_target, Missile.LaunchProfile.IMMEDIATE_BURN)
			print("EnemyAIShip %s: Missile launched at target" % ship_name)


func _process_evaluating(delta: float) -> void:
	_update_detected_targets()
	
	if primary_target != null and is_instance_valid(primary_target):
		set_ai_state(AIState.TRACKING)
	else:
		set_ai_state(AIState.PATROL)


func _process_evading(delta: float) -> void:
	evasion_timer += delta
	
	match evasion_pattern % 3:
		0:
			_radial_evasion()
		1:
			_prograde_evasion()
		2:
			_unpredictable_evasion()
	
	if evasion_timer >= evasion_duration:
		evasion_timer = 0.0
		evasion_pattern += 1
		
		if health >= max_health * 0.5:
			set_ai_state(AIState.EVALUATING)
		else:
			set_ai_state(AIState.RETURNING)


func _radial_evasion() -> void:
	_apply_orbital_thrust(_get_radial_direction(), 0.9)
	throttle = 0.9
	
	if randf() < 0.1:
		evasion_pattern += 1


func _prograde_evasion() -> void:
	var burst = sin(state_timer * 3.0) * 0.5 + 0.5
	_apply_orbital_thrust(_get_prograde_direction(), burst)
	throttle = burst


func _unpredictable_evasion() -> void:
	var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var random_thrust = randf_range(0.3, 0.8)
	_apply_orbital_thrust(random_dir, random_thrust)
	throttle = random_thrust
	
	if state_timer > 2.0:
		evasion_pattern += 1


func _process_return(delta: float) -> void:
	var base_pos = Vector2.ZERO
	
	if patrol_center_body != null:
		base_pos = patrol_center_body.world_position
	
	var distance = world_position.distance_to(base_pos)
	
	if distance < 100000:
		set_ai_state(AIState.IDLE)
		return
	
	_calculate_transfer_to_position(base_pos)
	_apply_orbital_thrust(_get_prograde_direction(), 0.7)


func _calculate_intercept_trajectory() -> void:
	if primary_target == null or not is_instance_valid(primary_target):
		return
	
	var target_pos = primary_target.world_position if "world_position" in primary_target else primary_target.position
	var target_vel = Vector2.ZERO
	
	if "velocity" in primary_target:
		target_vel = primary_target.get("velocity")
	
	var intercept_point = _predict_intercept_point(
		world_position, velocity, target_pos, target_vel, 3600.0
	)
	
	if intercept_point == Vector2.INF:
		intercept_point = target_pos
	
	_calculate_transfer_to_position(intercept_point)


func _predict_intercept_point(launcher_pos: Vector2, launcher_vel: Vector2,
		target_pos: Vector2, target_vel: Vector2, max_time: float) -> Vector2:
	var intercept_time = _calculate_intercept_time(
		launcher_pos, launcher_vel, target_pos, target_vel
	)
	
	if intercept_time == INF or intercept_time > max_time:
		return Vector2.INF
	
	return target_pos + target_vel * intercept_time


func _calculate_intercept_time(launcher_pos: Vector2, launcher_vel: Vector2,
		target_pos: Vector2, target_vel: Vector2) -> float:
	var rel_pos = target_pos - launcher_pos
	var rel_vel = target_vel - launcher_vel
	
	var a = rel_vel.dot(rel_vel)
	var b = 2.0 * rel_pos.dot(rel_vel)
	var c = rel_pos.dot(rel_pos)
	
	if abs(a) < 1e-10:
		if abs(b) > 1e-10:
			return -c / b
		return INF
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return INF
	
	var t1 = (-b + sqrt(discriminant)) / (2.0 * a)
	var t2 = (-b - sqrt(discriminant)) / (2.0 * a)
	
	if t1 >= 0 and t2 >= 0:
		return min(t1, t2)
	elif t1 >= 0:
		return t1
	elif t2 >= 0:
		return t2
	else:
		return INF


func _calculate_transfer_to_position(target_pos: Vector2) -> void:
	var distance = world_position.distance_to(target_pos)
	
	if distance < 50000:
		return
	
	var to_target = (target_pos - world_position).normalized()
	var prograde = _get_prograde_direction()
	
	var burn_direction = _blend_thrust_direction(to_target, prograde, 0.6)
	
	_apply_orbital_thrust(burn_direction, 0.8)


func _create_patrol_orbit(altitude: float) -> void:
	if parent_body == null:
		return
	
	var radius = altitude
	var mu = parent_body.mu if parent_body.has("mu") else OrbitalConstants.SUN_MU
	var velocity_magnitude = sqrt(mu / radius)
	
	var current_pos = world_position - parent_body.world_position
	var current_vel = velocity
	
	var radial = current_pos.normalized()
	var current_prograde = Vector2(-radial.y, radial.x)
	
	var target_vel = current_prograde * velocity_magnitude
	var vel_diff = target_vel - current_vel
	
	if vel_diff.length() > 1.0:
		_apply_orbital_thrust(vel_diff.normalized(), min(1.0, vel_diff.length() / 100.0))


func _get_prograde_direction() -> Vector2:
	if orbit_state != null and orbit_state.position.length() > 0:
		var radial = orbit_state.position.normalized()
		return Vector2(-radial.y, radial.x)
	return velocity.normalized() if velocity.length_squared() > 0 else Vector2.RIGHT


func _get_radial_direction() -> Vector2:
	if orbit_state != null and orbit_state.position.length() > 0:
		return orbit_state.position.normalized()
	return world_position.normalized() if world_position.length_squared() > 0 else Vector2.UP


func _blend_thrust_direction(dir1: Vector2, dir2: Vector2, blend: float) -> Vector2:
	var blended = dir1 * blend + dir2 * (1.0 - blend)
	return blended.normalized()


func _apply_orbital_thrust(direction: Vector2, power: float) -> void:
	throttle = power
	
	var ship_prograde = _get_prograde_direction()
	var dot_prograde = direction.dot(ship_prograde)
	var dot_radial = direction.dot(_get_radial_direction())
	
	var thrust_dir: ThrustDirection
	if dot_prograde > 0.7:
		thrust_dir = ThrustDirection.PROGRADE
	elif dot_prograde < -0.7:
		thrust_dir = ThrustDirection.RETROGRADE
	elif dot_radial > 0.7:
		thrust_dir = ThrustDirection.RADIAL_OUT
	elif dot_radial < -0.7:
		thrust_dir = ThrustDirection.RADIAL_IN
	else:
		thrust_dir = ThrustDirection.MANUAL
		manual_thrust_vector = direction
	
	current_thrust_direction = thrust_dir
	is_thrusting = true


func _update_threat_assessment() -> void:
	_update_detected_targets()
	
	var best_target = null
	var best_priority = -INF
	
	for target in detected_targets:
		var priority = _calculate_target_priority(target)
		if priority > best_priority:
			best_priority = priority
			best_target = target
	
	if best_target != null:
		awareness_level = min(1.0, awareness_level + 0.1)
	else:
		awareness_level = max(0.0, awareness_level - 0.05)
	
	if best_target != primary_target:
		if primary_target != null:
			target_lost.emit()
		primary_target = best_target
		if best_target != null:
			target_acquired.emit(best_target)


func _update_detected_targets() -> void:
	detected_targets.clear()
	
	var player_ship = _get_player_ship()
	if player_ship != null:
		var distance = world_position.distance_to(player_ship.world_position)
		if distance < intercept_distance * 2:
			detected_targets.append(player_ship)
	
	var sensor_manager = get_node("/root/SensorManager") if has_node("/root/SensorManager") else null
	if sensor_manager != null and sensor_manager.has_method("get_contacts"):
		var contacts = sensor_manager.get_contacts()
		for contact in contacts:
			if contact != null and is_instance_valid(contact):
				var cpos = contact.get("position") if "position" in contact else (contact.get("world_position") if "world_position" in contact else Vector2.ZERO)
				var distance = world_position.distance_to(cpos)
				if distance < intercept_distance * 2:
					detected_targets.append(contact)


func _calculate_target_priority(target: Node2D) -> float:
	var priority = 0.0
	
	var tpos = target.get("world_position") if "world_position" in target else target.position
	var distance = world_position.distance_to(tpos)
	priority += max(0, 1000.0 - distance / 1000.0)
	
	if target.has("has_combat_systems"):
		if target.has_combat_systems():
			priority += 500.0
	
	if aggressive:
		priority *= 1.5
	
	return priority


func _get_player_ship() -> Ship:
	var main = get_node("/root/Main") if has_node("/root/Main") else null
	if main and main.has("player_ship"):
		return main.get("player_ship")
	
	var ships = get_tree().get_nodes_in_group("player")
	if ships.size() > 0:
		return ships[0]
	
	return null


func set_patrol_area(body: CelestialBody, radius: float) -> void:
	patrol_center_body = body
	patrol_center = body.world_position if body else Vector2.ZERO
	patrol_radius = radius


func set_aggressive_mode(enabled: bool) -> void:
	aggressive = enabled


func force_engage(target: Node2D) -> void:
	primary_target = target
	set_ai_state(AIState.TRACKING)


func disengage() -> void:
	primary_target = null
	set_ai_state(AIState.RETURNING)


func get_ai_state() -> int:
	return ai_state


func get_ai_state_name() -> String:
	return _get_state_name(ai_state)


func get_primary_target() -> Node2D:
	return primary_target


func is_combat_active() -> bool:
	return is_in_combat


func get_ai_data() -> Dictionary:
	return {
		"state": ai_state,
		"state_name": get_ai_state_name(),
		"primary_target": primary_target.ship_name if primary_target != null else "None",
		"targets_detected": detected_targets.size(),
		"awareness_level": awareness_level,
		"has_lock": has_lock,
		"is_combat": is_in_combat,
		"patrol_center": patrol_center,
		"patrol_radius": patrol_radius
	}


func _process(delta: float) -> void:
	super._process(delta)
	
	state_timer += delta
	
	# Check for missile threats (higher priority than other AI decisions)
	_check_missile_threats(delta)
	
	match ai_state:
		AIState.IDLE:
			if parent_body != null:
				set_ai_state(AIState.PATROL)
		AIState.PATROL:
			_process_patrol(delta)
		AIState.TRANSIT:
			_process_transit(delta)
		AIState.TRACKING:
			_process_tracking(delta)
		AIState.INTERCEPTING:
			_process_intercept(delta)
		AIState.ENGAGED:
			_process_engaged(delta)
		AIState.EVALUATING:
			_process_evaluating(delta)
		AIState.EVADING:
			# Check if this is a missile evasion or tactical evasion
			if incoming_missiles.size() > 0:
				_process_missile_evasion(delta)
			else:
				_process_evading(delta)
		AIState.RETURNING:
			_process_return(delta)
	
	threat_assessment_timer += delta
	if threat_assessment_timer > 1.0:
		threat_assessment_timer = 0.0
		_update_threat_assessment()
	
	_update_ai_heat_signature(delta)


func _update_ai_heat_signature(delta: float) -> void:
	var target_heat: float = base_heat_signature
	
	match ai_state:
		AIState.PATROL, AIState.TRANSIT:
			target_heat = 0.2
		AIState.INTERCEPTING:
			target_heat = 0.6
		AIState.ENGAGED:
			target_heat = 0.9
		AIState.EVADING:
			target_heat = 0.5
	
	if target_heat > current_heat_output:
		current_heat_output = min(target_heat, current_heat_output + 0.8 * delta)
	else:
		current_heat_output = max(target_heat, current_heat_output - 0.5 * delta)


# === Missile Threat Detection & Response ===

func _check_missile_threats(delta: float) -> void:
	"""Detect incoming missiles and trigger evasion."""
	missile_threat_timer += delta
	if missile_threat_timer < 0.5:  # Check every 0.5 seconds
		return
	missile_threat_timer = 0.0
	
	# Find all missiles in the scene
	var all_missiles: Array = []
	var missiles = get_tree().get_nodes_in_group("missile")
	if missiles.size() > 0:
		all_missiles = missiles
	else:
		# Fallback: search by class name
		for node in get_tree().get_all_instances():
			if node is Missile or (node.get("class_name") == "Missile"):
				all_missiles.append(node)
	
	incoming_missiles.clear()
	
	for missile in all_missiles:
		# Skip our own missiles
		if missile == self or missile.get("fired_by") == self:
			continue
		
		# Calculate distance to missile
		var missile_pos = missile.get("world_position") if "world_position" in missile else missile.position
		var missile_vel = missile.get("velocity") if "velocity" in missile else Vector2.ZERO
		
		var distance_to_missile = world_position.distance_to(missile_pos)
		
		# Consider it a threat if within detection range and approaching
		if distance_to_missile < 50000.0:  # 50km detection range
			# Check if missile is approaching (relative velocity toward us)
			var relative_vel = missile_vel - (orbit_state.velocity if orbit_state else Vector2.ZERO)
			var closing_speed = -relative_vel.dot((missile_pos - world_position).normalized())
			
			if closing_speed > 0 or distance_to_missile < 20000.0:
				incoming_missiles.append({
					"missile": missile,
					"position": missile_pos,
					"distance": distance_to_missile,
					"closing": closing_speed > 0
				})
	
	# Trigger evasion if missiles are detected and we're not already evading
	if incoming_missiles.size() > 0 and ai_state != AIState.EVADING:
		# Prioritize missile evasion over other states
		if ai_state == AIState.ENGAGED or ai_state == AIState.INTERCEPTING:
			# Can interrupt engagement to evade
			set_ai_state(AIState.EVADING)
		elif evasion_timer > 5.0:
			# Can also trigger from patrol/tracking
			_trigger_missile_evasion()


func _trigger_missile_evasion() -> void:
	"""Execute emergency evasion maneuver."""
	if incoming_missiles.size() == 0:
		return
	
	# Find best escape direction (perpendicular to missile approach)
	var escape_dir = Vector2.ZERO
	var closest_missile = null
	var closest_distance = INF
	
	for threat in incoming_missiles:
		if threat.distance < closest_distance:
			closest_distance = threat.distance
			closest_missile = threat
	
	if closest_missile:
		# Direction from missile to us
		var missile_to_us = (world_position - closest_missile.position).normalized()
		
		# Perpendicular directions (both options, pick one randomly)
		var perp_dir = Vector2(-missile_to_us.y, missile_to_us.x)
		if randf() > 0.5:
			perp_dir = -perp_dir
		
		escape_dir = perp_dir.normalized()
		last_evasion_direction = escape_dir
	
	# Set up evasion state
	evasion_pattern = randi() % 4
	evasion_duration = 8.0 + randf() * 4.0  # 8-12 seconds
	evasion_timer = 0.0
	
	set_ai_state(AIState.EVADING)
	evading.emit()


func _process_missile_evasion(delta: float) -> void:
	"""Process evasion state when under missile attack."""
	evasion_timer += delta
	
	# Apply evasion thrust in the escape direction
	var evade_thrust_dir = Ship.ThrustDirection.RADIAL_OUT
	if last_evasion_direction.length_squared() > 0.1:
		# Determine if we should thrust prograde or retrograde based on escape direction
		var prograde = orbit_state.get_prograde() if orbit_state else Vector2.RIGHT
		var dot_product = last_evasion_direction.dot(prograde.normalized())
		
		if dot_product > 0.3:
			evade_thrust_dir = Ship.ThrustDirection.PROGRADE
		elif dot_product < -0.3:
			evade_thrust_dir = Ship.ThrustDirection.RETROGRADE
	
	# Start thrust for evasion
	if not is_thrusting:
		start_thrust(evade_thrust_dir, 0.8)
	
	# Also try to activate PDC if we have them
	if pdc_enabled and has_method("get_pdc_count"):
		var pdc_count = get("pdc_count")
		if pdc_count > 0 and closest_missile_in_range():
			_fire_pdc_at_nearest_missile()
	
	# Check if we can return to previous state after evasion
	if evasion_timer >= evasion_duration:
		# Check if missiles are still a threat
		if incoming_missiles.size() == 0:
			set_ai_state(previous_state if previous_state != AIState.EVADING else AIState.PATROL)


func closest_missile_in_range() -> bool:
	"""Check if there's a missile within PDC range."""
	for threat in incoming_missiles:
		if threat.distance < 5000.0:  # PDC range ~5km
			return true
	return false


func _fire_pdc_at_nearest_missile() -> void:
	"""Fire PDCs at the nearest incoming missile."""
	if incoming_missiles.size() == 0 or not has_method("fire_pdc"):
		return
	
	var closest: Dictionary = incoming_missiles[0]
	for threat in incoming_missiles:
		if threat.distance < closest.distance:
			closest = threat
	
	# Fire PDCs in the direction of the missile
	var aim_direction = (closest.position - world_position).normalized()
	
	# Trigger PDC fire through the ship
	if has_method("request_pdc_fire"):
		request_pdc_fire(aim_direction)