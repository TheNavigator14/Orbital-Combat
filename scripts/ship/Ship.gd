class_name Ship
extends Node2D
## Player or NPC ship with orbital mechanics
## Uses Kepler propagation when coasting, RK4 integration when thrusting

signal thrust_started()
signal thrust_ended()
signal fuel_depleted()
signal orbit_changed()
signal maneuver_started(node: ManeuverNode)
signal maneuver_completed(node: ManeuverNode)
signal soi_changed(old_parent: CelestialBody, new_parent: CelestialBody)
signal main_engine_toggled(active: bool)
signal throttle_changed(level: int)
signal stability_assist_toggled(enabled: bool)

# === Configuration ===
@export var ship_name: String = "Ship"
@export var max_thrust: float = 100000.0  # Newtons (main engine)
@export var rcs_thrust: float = 5000.0  # Newtons (RCS thrusters, much weaker)
@export var exhaust_velocity: float = 3500.0  # m/s (Isp * g0)
@export var dry_mass: float = 10000.0  # kg
@export var fuel_capacity: float = 20000.0  # kg

# === State ===
var orbit_state: OrbitState = null
var parent_body: CelestialBody = null
var fuel_mass: float = 0.0  # Current fuel in kg

# === Ship Rotation ===
var ship_rotation: float = 0.0  # Radians, 0 = pointing right (+X), world-relative
var angular_velocity: float = 0.0  # Radians per second

@export var rotation_speed: float = 2.0  # Radians per second at full input
@export var stability_assist_strength: float = 5.0  # Angular damping rate (rad/s^2)
var stability_assist_enabled: bool = true

# === Thrust Control ===
var main_engine_active: bool = false  # Toggle for main engine
var throttle_level: int = 0  # 0-4 (0%, 25%, 50%, 75%, 100%)
var is_thrusting: bool = false
var current_thrust_magnitude: float = 0.0  # Actual thrust being applied

# === Input State ===
var input_state: Dictionary = {
	"forward": false,
	"backward": false,
	"strafe_left": false,
	"strafe_right": false,
	"rotate_left": false,
	"rotate_right": false
}

# === Maneuver Queue ===
var planned_maneuvers: Array = []  # Array of ManeuverNode
var current_maneuver: ManeuverNode = null
var is_executing_maneuver: bool = false

# === Computed Properties ===
var total_mass: float:
	get:
		return dry_mass + fuel_mass

var current_acceleration: float:
	get:
		if total_mass <= 0:
			return 0.0
		return current_thrust_magnitude / total_mass

var delta_v_remaining: float:
	get:
		if fuel_mass <= 0:
			return 0.0
		return exhaust_velocity * log((dry_mass + fuel_mass) / dry_mass)

var world_position: Vector2:
	get:
		if orbit_state and parent_body:
			return orbit_state.position + parent_body.world_position
		return Vector2.ZERO

var throttle_percent: float:
	get:
		return throttle_level * 25.0


func _ready() -> void:
	fuel_mass = fuel_capacity  # Start with full tank
	# Initialize rotation to prograde once we have orbit state
	call_deferred("_initialize_rotation")


func _initialize_rotation() -> void:
	if orbit_state and orbit_state.velocity.length_squared() > 0:
		ship_rotation = orbit_state.velocity.angle()


func initialize_orbit(parent: CelestialBody, altitude: float, start_angle: float = 0.0) -> void:
	## Initialize ship in circular orbit around parent body
	parent_body = parent

	var orbital_radius = parent.radius + altitude
	orbit_state = OrbitState.create_circular(orbital_radius, parent.mu, start_angle)

	# Initial state vector update
	orbit_state.update_state_vectors(TimeManager.simulation_time)

	# Set initial rotation to prograde
	if orbit_state.velocity.length_squared() > 0:
		ship_rotation = orbit_state.velocity.angle()

	GameManager.register_player_ship(self)


func initialize_from_state(parent: CelestialBody, pos: Vector2, vel: Vector2) -> void:
	## Initialize ship from position and velocity
	parent_body = parent
	orbit_state = OrbitState.create_from_state_vectors(pos, vel, parent.mu, TimeManager.simulation_time)

	# Set initial rotation to prograde
	if orbit_state.velocity.length_squared() > 0:
		ship_rotation = orbit_state.velocity.angle()

	GameManager.register_player_ship(self)


func _physics_process(delta: float) -> void:
	if orbit_state == null or parent_body == null:
		return

	var sim_delta = TimeManager.get_delta_time(delta)
	if sim_delta <= 0:
		return

	# Update rotation from Q/E input
	_update_rotation(sim_delta)

	# Update thrust from input
	_update_thrust()

	if is_thrusting and current_thrust_magnitude > 0 and fuel_mass > 0:
		# Numerical integration during thrust
		_integrate_thrust(sim_delta)
	else:
		# Kepler propagation when coasting
		orbit_state.update_state_vectors(TimeManager.simulation_time)

	# Check for SOI transitions
	_check_soi_transition()

	# Check for maneuver execution
	_check_maneuver_schedule()


func _update_rotation(delta: float) -> void:
	## Update ship rotation based on Q/E input and stability assist
	var rotation_input: float = 0.0
	if input_state.rotate_left:
		rotation_input -= 1.0
	if input_state.rotate_right:
		rotation_input += 1.0

	if rotation_input != 0.0:
		# Direct rotation from input
		angular_velocity = rotation_input * rotation_speed
	elif stability_assist_enabled:
		# Stability assist: damp angular velocity when not commanding rotation
		angular_velocity = move_toward(angular_velocity, 0.0, stability_assist_strength * delta)
	# Without stability assist, angular_velocity persists (realistic)

	# Apply rotation
	ship_rotation += angular_velocity * delta

	# Normalize to [0, TAU)
	ship_rotation = fmod(ship_rotation + TAU, TAU)


func _update_thrust() -> void:
	## Calculate thrust based on main engine state and RCS input
	var thrust_vector := Vector2.ZERO
	var thrust_power: float = 0.0

	if main_engine_active:
		# Main engine mode: W/S control throttle, thrust is always forward
		if throttle_level > 0:
			var forward_dir = Vector2.RIGHT.rotated(ship_rotation)
			thrust_vector = forward_dir
			thrust_power = max_thrust * (throttle_level / 4.0)
		# A/D still work for RCS strafing even with main engine on
		var strafe_thrust := Vector2.ZERO
		if input_state.strafe_right:
			strafe_thrust.y += 1.0
		if input_state.strafe_left:
			strafe_thrust.y -= 1.0
		if strafe_thrust.length_squared() > 0.0:
			# Add RCS strafe to main engine thrust
			var strafe_world = strafe_thrust.rotated(ship_rotation) * rcs_thrust
			if thrust_power > 0:
				# Combine main engine forward with RCS strafe
				var main_thrust_vec = thrust_vector * thrust_power
				var combined = main_thrust_vec + strafe_world
				thrust_vector = combined.normalized()
				thrust_power = combined.length()
			else:
				thrust_vector = strafe_world.normalized()
				thrust_power = rcs_thrust
	else:
		# RCS mode: WASD for strafing
		var local_thrust := Vector2.ZERO

		if input_state.forward:
			local_thrust.x += 1.0
		if input_state.backward:
			local_thrust.x -= 1.0
		if input_state.strafe_right:
			local_thrust.y += 1.0
		if input_state.strafe_left:
			local_thrust.y -= 1.0

		if local_thrust.length_squared() > 0.0:
			local_thrust = local_thrust.normalized()
			thrust_vector = local_thrust.rotated(ship_rotation)
			thrust_power = rcs_thrust

	# Apply thrust
	if thrust_power > 0 and fuel_mass > 0:
		current_thrust_magnitude = thrust_power
		if not is_thrusting:
			is_thrusting = true
			# Limit warp during thrust
			TimeManager.limit_warp(TimeManager.WarpLevel.X100)
			thrust_started.emit()
	else:
		if is_thrusting:
			is_thrusting = false
			current_thrust_magnitude = 0.0
			TimeManager.remove_warp_limit()
			thrust_ended.emit()

	# Store thrust direction for integration
	if thrust_power > 0:
		_current_thrust_direction = thrust_vector


var _current_thrust_direction: Vector2 = Vector2.ZERO


func _integrate_thrust(delta: float) -> void:
	## RK4 integration for thrust phase
	var thrust_dir = _current_thrust_direction
	if thrust_dir.length_squared() < 0.1:
		return

	# Calculate acceleration
	var accel_magnitude = current_acceleration
	var thrust_accel = thrust_dir.normalized() * accel_magnitude

	# Subdivide for stability at high time warp
	var max_step = 1.0  # Maximum 1 second per integration step
	var remaining = delta
	var substeps = 0
	var max_substeps = 1000

	while remaining > 0 and substeps < max_substeps:
		var step = minf(remaining, max_step)

		# RK4 step
		var result = OrbitalMechanics.rk4_step(
			orbit_state.position,
			orbit_state.velocity,
			parent_body.mu,
			step,
			thrust_accel
		)

		# Update orbit state
		orbit_state.position = result.position
		orbit_state.velocity = result.velocity

		# Consume fuel
		var mass_flow_rate = current_thrust_magnitude / exhaust_velocity
		fuel_mass = maxf(0.0, fuel_mass - mass_flow_rate * step)

		if fuel_mass <= 0:
			_on_fuel_depleted()
			break

		remaining -= step
		substeps += 1

	# Recalculate orbital elements from new state
	orbit_state.set_from_state_vectors(orbit_state.position, orbit_state.velocity, TimeManager.simulation_time)
	orbit_state.last_update_time = TimeManager.simulation_time

	orbit_changed.emit()


# === Engine Control ===

func toggle_main_engine() -> void:
	## Toggle main engine on/off
	main_engine_active = not main_engine_active

	# Clear W/S input state to prevent carryover between modes
	input_state.forward = false
	input_state.backward = false

	if main_engine_active and throttle_level == 0:
		throttle_level = 1  # Start at 25% when turning on
		throttle_changed.emit(throttle_level)
	main_engine_toggled.emit(main_engine_active)
	print("Main engine: %s (Throttle: %d%%)" % ["ON" if main_engine_active else "OFF", throttle_level * 25])


func increase_throttle() -> void:
	## Increase throttle by 25%
	if main_engine_active and throttle_level < 4:
		throttle_level += 1
		throttle_changed.emit(throttle_level)
		print("Throttle: %d%%" % [throttle_level * 25])


func decrease_throttle() -> void:
	## Decrease throttle by 25%
	if main_engine_active and throttle_level > 0:
		throttle_level -= 1
		throttle_changed.emit(throttle_level)
		print("Throttle: %d%%" % [throttle_level * 25])
		if throttle_level == 0:
			main_engine_active = false
			main_engine_toggled.emit(false)


func toggle_stability_assist() -> void:
	## Toggle stability assist system
	stability_assist_enabled = not stability_assist_enabled
	stability_assist_toggled.emit(stability_assist_enabled)
	print("SAS: %s" % ["ON" if stability_assist_enabled else "OFF"])


func _on_fuel_depleted() -> void:
	is_thrusting = false
	current_thrust_magnitude = 0.0
	main_engine_active = false
	TimeManager.remove_warp_limit()
	fuel_depleted.emit()


# === SOI Transition ===

func _check_soi_transition() -> void:
	## Check if ship has crossed an SOI boundary and handle transition
	var current_world_pos = world_position

	# Case 1: Check if leaving current parent's SOI (exiting to parent's parent)
	if parent_body is Planet:
		var planet = parent_body as Planet
		var distance_from_parent = orbit_state.position.length()

		if distance_from_parent >= planet.sphere_of_influence:
			# Exiting to parent's parent (e.g., Earth SOI -> Sun)
			var new_parent = planet.parent_body
			if new_parent != null:
				_transition_to_body(new_parent)
				return

	# Case 2: Check if entering a child body's SOI
	var bodies = GameManager.get_all_celestial_bodies()
	for body in bodies:
		if body == parent_body:
			continue
		if not body is Planet:
			continue

		var planet = body as Planet

		# Only check planets that orbit our current parent
		if planet.parent_body != parent_body:
			continue

		if planet.is_point_in_soi(current_world_pos):
			_transition_to_body(planet)
			return


func _transition_to_body(new_parent: CelestialBody) -> void:
	## Transform orbit state from current parent to new parent reference frame
	var old_parent = parent_body
	var current_time = TimeManager.simulation_time

	# Get current state vectors in world frame
	orbit_state.update_state_vectors(current_time)
	var world_pos = orbit_state.position + old_parent.world_position
	var world_vel = orbit_state.velocity

	# If old parent is orbiting something (is a planet), add its orbital velocity
	if old_parent is Planet:
		var planet = old_parent as Planet
		world_vel += planet.get_orbital_velocity()

	# Calculate position and velocity relative to new parent
	var rel_pos = world_pos - new_parent.world_position
	var rel_vel = world_vel

	# Subtract new parent's orbital velocity if it's a planet
	if new_parent is Planet:
		var planet = new_parent as Planet
		rel_vel -= planet.get_orbital_velocity()

	# Create new orbit state in new reference frame
	orbit_state = OrbitState.create_from_state_vectors(rel_pos, rel_vel, new_parent.mu, current_time)
	parent_body = new_parent

	# Emit signals for UI updates
	orbit_changed.emit()
	soi_changed.emit(old_parent, new_parent)

	print("SOI Transition: %s -> %s" % [old_parent.body_name, new_parent.body_name])
	print("  New orbit: a=%.0f km, e=%.4f, %s" % [
		orbit_state.semi_major_axis / 1000.0,
		orbit_state.eccentricity,
		"hyperbolic" if orbit_state.is_hyperbolic else "elliptical"
	])


func get_heliocentric_velocity() -> Vector2:
	## Get velocity in heliocentric (Sun-centered) frame
	var vel = orbit_state.velocity
	var current = parent_body

	while current is Planet:
		var planet = current as Planet
		vel += planet.get_orbital_velocity()
		current = planet.parent_body

	return vel


func get_heliocentric_position() -> Vector2:
	## Get position in heliocentric (Sun-centered) frame
	return world_position


# === Maneuver Planning ===

func plan_maneuver(execution_time: float, delta_v: Vector2) -> ManeuverNode:
	## Create a new maneuver node
	var node = ManeuverNode.new()
	node.execution_time = execution_time
	node.delta_v = delta_v
	node.calculate_for_ship(self)

	planned_maneuvers.append(node)
	planned_maneuvers.sort_custom(func(a, b): return a.execution_time < b.execution_time)

	# Schedule auto-warp slowdown before maneuver
	_schedule_maneuver_events(node)

	return node


func remove_maneuver(node: ManeuverNode) -> void:
	## Remove a planned maneuver
	var idx = planned_maneuvers.find(node)
	if idx >= 0:
		planned_maneuvers.remove_at(idx)
		TimeManager.cancel_event("maneuver_warning_%d" % node.get_instance_id())
		TimeManager.cancel_event("maneuver_start_%d" % node.get_instance_id())


func _schedule_maneuver_events(node: ManeuverNode) -> void:
	## Schedule time events for a maneuver
	var warning_time = node.execution_time - 60.0  # 60s warning

	if warning_time > TimeManager.simulation_time:
		TimeManager.schedule_event(
			warning_time,
			"maneuver_warning_%d" % node.get_instance_id(),
			func(): TimeManager.set_warp_level(TimeManager.WarpLevel.X10),
			false
		)

	# Auto-pause at maneuver time for manual execution
	TimeManager.schedule_event(
		node.execution_time,
		"maneuver_start_%d" % node.get_instance_id(),
		func(): _on_maneuver_time(node),
		true  # Auto-pause
	)


func _on_maneuver_time(node: ManeuverNode) -> void:
	## Called when it's time to execute a maneuver
	current_maneuver = node
	print("MANEUVER TIME - Align ship and thrust to execute")
	# Player must manually align and thrust


func _check_maneuver_schedule() -> void:
	## Check if it's time to execute a maneuver
	pass


func complete_maneuver() -> void:
	## Called when maneuver is complete
	if current_maneuver:
		var completed = current_maneuver
		planned_maneuvers.erase(current_maneuver)
		current_maneuver = null
		is_executing_maneuver = false
		maneuver_completed.emit(completed)


# === Hohmann Transfer Helper ===

func plan_hohmann_to_altitude(target_altitude: float) -> Array:
	## Plan a Hohmann transfer to a new circular orbit altitude
	var current_radius = orbit_state.position.length()
	var target_radius = parent_body.radius + target_altitude

	var transfer = OrbitalMechanics.hohmann_transfer(current_radius, target_radius, parent_body.mu)

	# First burn at current position
	var burn1_time = TimeManager.simulation_time + orbit_state.time_to_periapsis(TimeManager.simulation_time)
	if burn1_time < TimeManager.simulation_time + 60:
		burn1_time = TimeManager.simulation_time + 60  # At least 60s from now

	var node1 = plan_maneuver(burn1_time, orbit_state.get_prograde() * transfer.dv1)

	# Second burn at apoapsis of transfer orbit
	var node2 = plan_maneuver(burn1_time + transfer.transfer_time, orbit_state.get_prograde() * transfer.dv2)

	return [node1, node2]


# === Input Handling ===

func _unhandled_input(event: InputEvent) -> void:
	# Main engine toggle
	if event.is_action_pressed("toggle_main_engine"):
		toggle_main_engine()
		return

	# Stability assist toggle
	if event.is_action_pressed("toggle_stability_assist"):
		toggle_stability_assist()
		return

	# W/S behavior depends on main engine state
	if main_engine_active:
		# Main engine on: W/S control throttle
		if event.is_action_pressed("thrust_prograde"):
			increase_throttle()
			return
		if event.is_action_pressed("thrust_retrograde"):
			decrease_throttle()
			return
	else:
		# Main engine off: W/S are RCS forward/backward
		if event.is_action_pressed("thrust_prograde"):
			input_state.forward = true
		elif event.is_action_released("thrust_prograde"):
			input_state.forward = false

		if event.is_action_pressed("thrust_retrograde"):
			input_state.backward = true
		elif event.is_action_released("thrust_retrograde"):
			input_state.backward = false

	# A/D always strafe (RCS)
	if event.is_action_pressed("thrust_radial_in"):
		input_state.strafe_left = true
	elif event.is_action_released("thrust_radial_in"):
		input_state.strafe_left = false

	if event.is_action_pressed("thrust_radial_out"):
		input_state.strafe_right = true
	elif event.is_action_released("thrust_radial_out"):
		input_state.strafe_right = false

	# Q/E always rotate
	if event.is_action_pressed("rotate_left"):
		input_state.rotate_left = true
	elif event.is_action_released("rotate_left"):
		input_state.rotate_left = false

	if event.is_action_pressed("rotate_right"):
		input_state.rotate_right = true
	elif event.is_action_released("rotate_right"):
		input_state.rotate_right = false


# === Visualization ===

func get_visual_rotation() -> float:
	## Get rotation for visual display
	return ship_rotation


func _draw() -> void:
	# Simple triangle ship icon - rotated based on ship_rotation
	var size_val = 10.0
	var draw_rotation = ship_rotation

	# Base points (ship pointing right when rotation = 0)
	var base_points = PackedVector2Array([
		Vector2(size_val, 0),                      # Nose (right)
		Vector2(-size_val * 0.6, -size_val * 0.6), # Top-left
		Vector2(-size_val * 0.3, 0),               # Notch
		Vector2(-size_val * 0.6, size_val * 0.6)   # Bottom-left
	])

	# Rotate all points
	var points = PackedVector2Array()
	for point in base_points:
		points.append(point.rotated(draw_rotation))

	draw_colored_polygon(points, Color.GREEN)

	# Thrust indicator
	if is_thrusting and current_thrust_magnitude > 0:
		var thrust_length = size_val * 1.5 * (current_thrust_magnitude / max_thrust)
		var thrust_dir = _current_thrust_direction
		if thrust_dir.length_squared() > 0.1:
			# Exhaust is opposite to thrust direction
			var exhaust_dir = -thrust_dir * thrust_length
			var exhaust_color = Color.ORANGE if main_engine_active else Color.CYAN
			draw_line(Vector2.ZERO, exhaust_dir, exhaust_color, 3.0 if main_engine_active else 1.5)


func get_info_string() -> String:
	if orbit_state == null:
		return ship_name

	return "%s\nAlt: %s\nVel: %s\nFuel: %.0f kg\nDelta-v: %s" % [
		ship_name,
		OrbitalConstantsClass.format_distance(orbit_state.current_altitude - parent_body.radius),
		OrbitalConstantsClass.format_velocity(orbit_state.current_speed),
		fuel_mass,
		OrbitalConstantsClass.format_velocity(delta_v_remaining)
	]
