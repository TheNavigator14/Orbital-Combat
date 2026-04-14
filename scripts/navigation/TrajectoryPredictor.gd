class_name TrajectoryPredictor
extends RefCounted
## Predicts future trajectory including SOI transitions
## Used for visualizing planned maneuvers across multiple reference frames

# === Trajectory Segment Data ===

class TrajectorySegment:
	## Represents a portion of the trajectory within a single SOI
	var parent_body: CelestialBody = null
	var orbit_state: OrbitState = null
	var start_time: float = 0.0
	var end_time: float = 0.0
	var points: PackedVector2Array = PackedVector2Array()  # World coordinates
	var is_hyperbolic: bool = false
	var ends_at_soi_exit: bool = false
	var ends_at_soi_entry: bool = false
	var next_parent: CelestialBody = null

	func get_duration() -> float:
		return end_time - start_time


# === Main Prediction Function ===

static func predict_trajectory(
		ship: Node,
		duration: float,
		sample_count: int = 200,
		include_maneuvers: bool = true
	) -> Array[TrajectorySegment]:
	## Predict ship's trajectory for the given duration
	## Returns array of segments, each in a different reference frame
	##
	## This handles SOI transitions automatically, creating new segments
	## when the ship crosses from one gravitational influence to another

	var segments: Array[TrajectorySegment] = []

	if ship == null or ship.orbit_state == null or ship.parent_body == null:
		return segments

	var current_time = TimeManager.simulation_time
	var end_time = current_time + duration

	# Start with current state
	var sim_orbit = ship.orbit_state.duplicate() as OrbitState
	var sim_parent = ship.parent_body
	var sim_time = current_time

	# Get maneuvers if we should include them
	var maneuvers: Array = []
	if include_maneuvers and ship.has_method("get") == false:
		# Access planned_maneuvers directly
		maneuvers = ship.planned_maneuvers.duplicate()

	# Start first segment
	var current_segment = _start_new_segment(sim_orbit, sim_parent, sim_time)
	current_segment.is_hyperbolic = sim_orbit.is_hyperbolic

	# Step through time
	var dt = duration / float(sample_count)
	var t = current_time

	while t < end_time:
		# Check for maneuver execution
		for maneuver in maneuvers:
			if maneuver.execution_time > sim_time and maneuver.execution_time <= t:
				# Apply maneuver
				var state = sim_orbit.get_state_at_time(maneuver.execution_time)
				var new_velocity = state.velocity + maneuver.delta_v
				sim_orbit = OrbitState.create_from_state_vectors(
					state.position, new_velocity, sim_parent.mu, maneuver.execution_time
				)

		# Get state at this time
		var state = sim_orbit.get_state_at_time(t)
		var world_pos = state.position + sim_parent.world_position

		current_segment.points.append(world_pos)

		# Check for SOI transition
		var transition = _check_soi_transition(world_pos, state.velocity, sim_parent, sim_orbit)

		if transition.has_transition:
			# End current segment
			current_segment.end_time = t
			current_segment.ends_at_soi_exit = transition.is_exit
			current_segment.ends_at_soi_entry = not transition.is_exit
			current_segment.next_parent = transition.new_parent
			segments.append(current_segment)

			# Transform to new reference frame
			sim_orbit = transition.new_orbit
			sim_parent = transition.new_parent

			# Start new segment
			current_segment = _start_new_segment(sim_orbit, sim_parent, t)
			current_segment.is_hyperbolic = sim_orbit.is_hyperbolic

		sim_time = t
		t += dt

	# Finalize last segment
	current_segment.end_time = end_time
	segments.append(current_segment)

	return segments


static func _start_new_segment(orbit: OrbitState, parent: CelestialBody, time: float) -> TrajectorySegment:
	## Create a new trajectory segment
	var segment = TrajectorySegment.new()
	segment.parent_body = parent
	segment.orbit_state = orbit
	segment.start_time = time
	return segment


static func _check_soi_transition(world_pos: Vector2, velocity: Vector2,
		current_parent: CelestialBody, current_orbit: OrbitState) -> Dictionary:
	## Check if position has crossed into a different SOI
	## Returns: { has_transition, new_parent, new_orbit, is_exit }

	var result = {
		"has_transition": false,
		"new_parent": null,
		"new_orbit": null,
		"is_exit": false
	}

	# Check exit from current parent (if it's a planet)
	if current_parent is Planet:
		var planet = current_parent as Planet
		var distance = current_orbit.position.length()

		if distance >= planet.sphere_of_influence:
			# Exiting to parent's parent
			var new_parent = planet.parent_body
			if new_parent != null:
				result.has_transition = true
				result.new_parent = new_parent
				result.is_exit = true

				# Transform orbit to new frame
				var world_vel = velocity + planet.get_orbital_velocity()
				var rel_pos = world_pos - new_parent.world_position
				var rel_vel = world_vel
				if new_parent is Planet:
					rel_vel -= (new_parent as Planet).get_orbital_velocity()

				result.new_orbit = OrbitState.create_from_state_vectors(
					rel_pos, rel_vel, new_parent.mu, TimeManager.simulation_time
				)
				return result

	# Check entry into child bodies
	var bodies = GameManager.get_all_celestial_bodies()
	for body in bodies:
		if body == current_parent:
			continue
		if not body is Planet:
			continue

		var planet = body as Planet
		if planet.parent_body != current_parent:
			continue

		if planet.is_point_in_soi(world_pos):
			result.has_transition = true
			result.new_parent = planet
			result.is_exit = false

			# Transform orbit to new frame
			var world_vel = velocity
			if current_parent is Planet:
				world_vel += (current_parent as Planet).get_orbital_velocity()

			var rel_pos = world_pos - planet.world_position
			var rel_vel = world_vel - planet.get_orbital_velocity()

			result.new_orbit = OrbitState.create_from_state_vectors(
				rel_pos, rel_vel, planet.mu, TimeManager.simulation_time
			)
			return result

	return result


# === Utility Functions ===

static func get_segment_color(segment: TrajectorySegment) -> Color:
	## Get the appropriate color for rendering a trajectory segment
	if segment.is_hyperbolic:
		return Color(1.0, 0.6, 0.0, 0.8)  # Orange for hyperbolic (escape/capture)
	return Color(0.9, 0.9, 0.0, 0.7)  # Yellow for elliptical


static func predict_single_orbit(ship: Node) -> PackedVector2Array:
	## Quick prediction of just the current orbit (no SOI transitions)
	## Useful for displaying the ship's current orbital path

	if ship == null or ship.orbit_state == null:
		return PackedVector2Array()

	return ship.orbit_state.sample_orbit_points(100)


static func predict_until_soi_exit(ship: Node, max_duration: float = 86400.0 * 365.0) -> TrajectorySegment:
	## Predict trajectory until the ship exits the current SOI
	## Useful for escape trajectories

	var segment = TrajectorySegment.new()

	if ship == null or ship.orbit_state == null or ship.parent_body == null:
		return segment

	if not ship.parent_body is Planet:
		# Already in heliocentric orbit, no SOI to exit
		return segment

	var planet = ship.parent_body as Planet
	var orbit = ship.orbit_state as OrbitState

	if not orbit.is_hyperbolic:
		# Elliptical orbit won't exit SOI
		return segment

	segment.parent_body = planet
	segment.orbit_state = orbit
	segment.start_time = TimeManager.simulation_time
	segment.is_hyperbolic = true

	# Sample the hyperbolic trajectory until SOI boundary
	var current_time = TimeManager.simulation_time
	var dt = 3600.0  # 1 hour steps
	var t = current_time

	while t < current_time + max_duration:
		var state = orbit.get_state_at_time(t)
		var distance = state.position.length()

		segment.points.append(state.position + planet.world_position)

		if distance >= planet.sphere_of_influence:
			segment.end_time = t
			segment.ends_at_soi_exit = true
			segment.next_parent = planet.parent_body
			break

		t += dt

	return segment
