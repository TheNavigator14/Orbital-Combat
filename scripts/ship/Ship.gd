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

# === Configuration ===
@export var ship_name: String = "Ship"
@export var max_thrust: float = 100000.0  # Newtons
@export var exhaust_velocity: float = 3500.0  # m/s (Isp * g0)
@export var dry_mass: float = 10000.0  # kg
@export var fuel_capacity: float = 20000.0  # kg

# === State ===
var orbit_state: OrbitState = null
var parent_body: CelestialBody = null
var fuel_mass: float = 0.0  # Current fuel in kg

# === Thrust Control ===
enum ThrustDirection { NONE, PROGRADE, RETROGRADE, RADIAL_IN, RADIAL_OUT, MANUAL }
var current_thrust_direction: ThrustDirection = ThrustDirection.NONE
var manual_thrust_vector: Vector2 = Vector2.ZERO
var throttle: float = 0.0  # 0.0 to 1.0
var is_thrusting: bool = false

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
		return (max_thrust * throttle) / total_mass

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


func _ready() -> void:
	fuel_mass = fuel_capacity  # Start with full tank


func initialize_orbit(parent: CelestialBody, altitude: float, start_angle: float = 0.0) -> void:
	## Initialize ship in circular orbit around parent body
	parent_body = parent

	var orbital_radius = parent.radius + altitude
	orbit_state = OrbitState.create_circular(orbital_radius, parent.mu, start_angle)

	# Initial state vector update
	orbit_state.update_state_vectors(TimeManager.simulation_time)

	GameManager.register_player_ship(self)


func initialize_from_state(parent: CelestialBody, pos: Vector2, vel: Vector2) -> void:
	## Initialize ship from position and velocity
	parent_body = parent
	orbit_state = OrbitState.create_from_state_vectors(pos, vel, parent.mu, TimeManager.simulation_time)

	GameManager.register_player_ship(self)


func _physics_process(delta: float) -> void:
	if orbit_state == null or parent_body == null:
		return

	var sim_delta = TimeManager.get_delta_time(delta)
	if sim_delta <= 0:
		return

	if is_thrusting and throttle > 0 and fuel_mass > 0:
		# Numerical integration during thrust
		_integrate_thrust(sim_delta)
	else:
		# Kepler propagation when coasting
		orbit_state.update_state_vectors(TimeManager.simulation_time)

	# Check for SOI transitions
	_check_soi_transition()

	# Check for maneuver execution
	_check_maneuver_schedule()


func _integrate_thrust(delta: float) -> void:
	## RK4 integration for thrust phase
	## This is only called when actively thrusting

	# Get thrust direction in world coordinates
	var thrust_dir = _get_thrust_direction_vector()
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
		var mass_flow_rate = (max_thrust * throttle) / exhaust_velocity
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


func _get_thrust_direction_vector() -> Vector2:
	## Get thrust direction as a unit vector in world coordinates
	match current_thrust_direction:
		ThrustDirection.NONE:
			return Vector2.ZERO
		ThrustDirection.PROGRADE:
			return orbit_state.get_prograde()
		ThrustDirection.RETROGRADE:
			return orbit_state.get_retrograde()
		ThrustDirection.RADIAL_OUT:
			return orbit_state.get_radial_out()
		ThrustDirection.RADIAL_IN:
			return orbit_state.get_radial_in()
		ThrustDirection.MANUAL:
			return manual_thrust_vector.normalized()
		_:
			return Vector2.ZERO


# === Thrust Control ===

func start_thrust(direction: ThrustDirection, throttle_level: float = 1.0) -> void:
	## Begin thrusting in specified direction
	if fuel_mass <= 0:
		return

	current_thrust_direction = direction
	throttle = clampf(throttle_level, 0.0, 1.0)
	is_thrusting = true

	# Limit time warp during thrust
	TimeManager.limit_warp(TimeManager.WarpLevel.X100)

	thrust_started.emit()


func stop_thrust() -> void:
	## Stop thrusting
	current_thrust_direction = ThrustDirection.NONE
	throttle = 0.0
	is_thrusting = false

	# Remove warp limit
	TimeManager.remove_warp_limit()

	thrust_ended.emit()


func set_manual_thrust(direction: Vector2, throttle_level: float = 1.0) -> void:
	## Set manual thrust direction
	manual_thrust_vector = direction
	start_thrust(ThrustDirection.MANUAL, throttle_level)


func _on_fuel_depleted() -> void:
	stop_thrust()
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
	# (e.g., from Sun's SOI into Mars' SOI)
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

	# Walk up the hierarchy adding orbital velocities
	while current is Planet:
		var planet = current as Planet
		vel += planet.get_orbital_velocity()
		current = planet.parent_body

	return vel


func get_heliocentric_position() -> Vector2:
	## Get position in heliocentric (Sun-centered) frame
	return world_position  # world_position is already heliocentric since Sun is at origin


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
	var start_time = node.execution_time - node.burn_duration / 2.0  # Start burn early to center it

	if warning_time > TimeManager.simulation_time:
		TimeManager.schedule_event(
			warning_time,
			"maneuver_warning_%d" % node.get_instance_id(),
			func(): TimeManager.set_warp_level(TimeManager.WarpLevel.X10),
			false
		)

	if start_time > TimeManager.simulation_time:
		TimeManager.schedule_event(
			start_time,
			"maneuver_start_%d" % node.get_instance_id(),
			func(): _begin_maneuver_execution(node),
			true  # Auto-pause at maneuver
		)


func _check_maneuver_schedule() -> void:
	## Check if it's time to execute a maneuver
	# This is handled by scheduled events now
	pass


func _begin_maneuver_execution(node: ManeuverNode) -> void:
	## Begin executing a maneuver
	current_maneuver = node
	is_executing_maneuver = true

	# Calculate thrust direction from delta-v
	var frame = orbit_state.get_orbital_frame()
	var prograde_component = node.delta_v.dot(frame.prograde)
	var radial_component = node.delta_v.dot(frame.radial_out)

	# For now, use manual thrust in delta-v direction
	# (A proper autopilot would orient the ship first)
	set_manual_thrust(node.delta_v, 1.0)

	maneuver_started.emit(node)


func complete_maneuver() -> void:
	## Called when maneuver is complete
	stop_thrust()

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
	if event.is_action_pressed("thrust_prograde"):
		start_thrust(ThrustDirection.PROGRADE)
	elif event.is_action_released("thrust_prograde"):
		if current_thrust_direction == ThrustDirection.PROGRADE:
			stop_thrust()

	elif event.is_action_pressed("thrust_retrograde"):
		start_thrust(ThrustDirection.RETROGRADE)
	elif event.is_action_released("thrust_retrograde"):
		if current_thrust_direction == ThrustDirection.RETROGRADE:
			stop_thrust()

	elif event.is_action_pressed("thrust_radial_out"):
		start_thrust(ThrustDirection.RADIAL_OUT)
	elif event.is_action_released("thrust_radial_out"):
		if current_thrust_direction == ThrustDirection.RADIAL_OUT:
			stop_thrust()

	elif event.is_action_pressed("thrust_radial_in"):
		start_thrust(ThrustDirection.RADIAL_IN)
	elif event.is_action_released("thrust_radial_in"):
		if current_thrust_direction == ThrustDirection.RADIAL_IN:
			stop_thrust()


# === Visualization ===

func _draw() -> void:
	# Simple triangle ship icon
	var size = 10.0
	var points = PackedVector2Array([
		Vector2(0, -size),      # Nose
		Vector2(-size * 0.6, size * 0.6),  # Left
		Vector2(0, size * 0.3),  # Notch
		Vector2(size * 0.6, size * 0.6)   # Right
	])

	draw_colored_polygon(points, Color.GREEN)

	# Thrust indicator
	if is_thrusting and throttle > 0:
		var thrust_length = size * 1.5 * throttle
		var thrust_dir = _get_thrust_direction_vector()
		if thrust_dir.length_squared() > 0.1:
			# Rotate thrust indicator
			var local_thrust = -thrust_dir  # Opposite direction for exhaust
			draw_line(Vector2.ZERO, local_thrust * thrust_length, Color.ORANGE, 3.0)


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
