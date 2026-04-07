class_name OrbitState
extends Resource
## Stores orbital elements and provides state vector calculations
## This is the core data structure for any orbiting object

signal orbit_changed()

# === Keplerian Orbital Elements ===
@export var semi_major_axis: float = 0.0  # a (meters) - negative for hyperbolic
@export var eccentricity: float = 0.0  # e (dimensionless) - 0=circular, 0-1=ellipse, 1=parabola, >1=hyperbola
@export var argument_of_periapsis: float = 0.0  # omega (radians) - angle from reference to periapsis
@export var mean_anomaly_at_epoch: float = 0.0  # M0 (radians) - mean anomaly at epoch time
@export var epoch_time: float = 0.0  # t0 (seconds) - reference time for mean anomaly

# === Parent Body Reference ===
# The gravitational parameter (mu = G*M) of the parent body
@export var parent_mu: float = 0.0

# === Cached State Vectors (updated by propagation) ===
var position: Vector2 = Vector2.ZERO  # Current position relative to parent (meters)
var velocity: Vector2 = Vector2.ZERO  # Current velocity relative to parent (m/s)
var last_update_time: float = -1.0  # Time of last state vector update

# === Derived Properties ===

var apoapsis: float:
	get:
		if eccentricity >= 1.0:
			return INF
		return semi_major_axis * (1.0 + eccentricity)

var periapsis: float:
	get:
		return OrbitalMechanics.get_periapsis(semi_major_axis, eccentricity)

var orbital_period: float:
	get:
		if semi_major_axis <= 0 or eccentricity >= 1.0:
			return INF
		return OrbitalMechanics.get_orbital_period(semi_major_axis, parent_mu)

var mean_motion: float:
	get:
		if semi_major_axis <= 0:
			return 0.0
		return OrbitalMechanics.get_mean_motion(semi_major_axis, parent_mu)

var current_altitude: float:
	get:
		return position.length()

var current_speed: float:
	get:
		return velocity.length()

var specific_orbital_energy: float:
	get:
		return velocity.length_squared() / 2.0 - parent_mu / position.length()

var is_hyperbolic: bool:
	get:
		return eccentricity >= 1.0

var is_circular: bool:
	get:
		return eccentricity < 0.01


# === Initialization ===

static func create_circular(radius: float, mu: float, start_angle: float = 0.0) -> OrbitState:
	## Create a circular orbit at given radius
	var orbit = OrbitState.new()
	orbit.semi_major_axis = radius
	orbit.eccentricity = 0.0
	orbit.argument_of_periapsis = 0.0
	orbit.mean_anomaly_at_epoch = start_angle
	orbit.epoch_time = 0.0
	orbit.parent_mu = mu
	return orbit


static func create_from_state_vectors(pos: Vector2, vel: Vector2, mu: float, current_time: float = 0.0) -> OrbitState:
	## Create orbit state from position and velocity vectors
	var orbit = OrbitState.new()
	orbit.parent_mu = mu
	orbit.set_from_state_vectors(pos, vel, current_time)
	return orbit


func set_from_state_vectors(pos: Vector2, vel: Vector2, current_time: float) -> void:
	## Set orbital elements from state vectors
	var elements = OrbitalMechanics.state_to_elements(pos, vel, parent_mu)

	semi_major_axis = elements.semi_major_axis
	eccentricity = elements.eccentricity
	argument_of_periapsis = elements.arg_periapsis
	mean_anomaly_at_epoch = elements.mean_anomaly
	epoch_time = current_time

	# Also cache the state vectors
	position = pos
	velocity = vel
	last_update_time = current_time

	orbit_changed.emit()


# === Propagation ===

func update_state_vectors(current_time: float) -> void:
	## Propagate orbit to current time and update position/velocity
	## Uses Kepler propagation (analytical, no numerical integration)

	if last_update_time == current_time:
		return  # Already up to date

	# Calculate mean anomaly at current time
	var dt = current_time - epoch_time
	var n = mean_motion
	var M = mean_anomaly_at_epoch + n * dt

	# Get state vectors from orbital elements
	var state = OrbitalMechanics.elements_to_state(
		semi_major_axis, eccentricity, argument_of_periapsis, M, parent_mu
	)

	position = state.position
	velocity = state.velocity
	last_update_time = current_time


func get_state_at_time(future_time: float) -> Dictionary:
	## Get position and velocity at a future time without modifying current state
	var dt = future_time - epoch_time
	var n = mean_motion
	var M = mean_anomaly_at_epoch + n * dt

	return OrbitalMechanics.elements_to_state(
		semi_major_axis, eccentricity, argument_of_periapsis, M, parent_mu
	)


func get_mean_anomaly_at_time(time: float) -> float:
	## Get mean anomaly at specified time
	var dt = time - epoch_time
	return mean_anomaly_at_epoch + mean_motion * dt


func get_true_anomaly_at_time(time: float) -> float:
	## Get true anomaly at specified time
	var M = get_mean_anomaly_at_time(time)
	var E = OrbitalMechanics.solve_kepler(M, eccentricity)
	return OrbitalMechanics.eccentric_to_true_anomaly(E, eccentricity)


func get_radius_at_time(time: float) -> float:
	## Get orbital radius at specified time
	var nu = get_true_anomaly_at_time(time)
	return OrbitalMechanics.get_radius_at_true_anomaly(semi_major_axis, eccentricity, nu)


# === Maneuvers ===

func apply_impulse(delta_v: Vector2, current_time: float) -> void:
	## Apply instantaneous velocity change and recalculate orbital elements
	## This is used for maneuver execution

	# First ensure state vectors are current
	update_state_vectors(current_time)

	# Apply impulse to velocity
	var new_velocity = velocity + delta_v

	# Recalculate orbital elements from new state
	set_from_state_vectors(position, new_velocity, current_time)


func get_velocity_at_periapsis() -> float:
	## Calculate velocity at periapsis
	return OrbitalMechanics.vis_viva(periapsis, semi_major_axis, parent_mu)


func get_velocity_at_apoapsis() -> float:
	## Calculate velocity at apoapsis
	if eccentricity >= 1.0:
		return 0.0  # No apoapsis for hyperbolic
	return OrbitalMechanics.vis_viva(apoapsis, semi_major_axis, parent_mu)


# === Time Calculations ===

func time_to_periapsis(current_time: float) -> float:
	## Calculate time until next periapsis passage
	var M = get_mean_anomaly_at_time(current_time)
	M = fmod(M + TAU, TAU)  # Normalize to [0, 2*PI]

	if eccentricity >= 1.0:
		# Hyperbolic - may have already passed periapsis
		if M > 0:
			return INF  # Already passed
		return -M / mean_motion

	# Elliptical - find time to M = 0 (periapsis)
	var remaining_M = TAU - M if M > 0 else -M
	return remaining_M / mean_motion


func time_to_apoapsis(current_time: float) -> float:
	## Calculate time until next apoapsis passage
	if eccentricity >= 1.0:
		return INF  # No apoapsis for hyperbolic

	var M = get_mean_anomaly_at_time(current_time)
	M = fmod(M + TAU, TAU)

	# Apoapsis is at M = PI
	var delta_M: float
	if M < PI:
		delta_M = PI - M
	else:
		delta_M = TAU - M + PI

	return delta_M / mean_motion


# === Orbital Frame ===

func get_orbital_frame() -> Dictionary:
	## Get current orbital reference frame vectors
	return OrbitalMechanics.get_orbital_frame(position, velocity)


func get_prograde() -> Vector2:
	## Get current prograde direction
	return OrbitalMechanics.get_prograde_direction(velocity)


func get_retrograde() -> Vector2:
	## Get current retrograde direction
	return -get_prograde()


func get_radial_out() -> Vector2:
	## Get current radial-out direction (away from parent)
	return OrbitalMechanics.get_radial_direction(position)


func get_radial_in() -> Vector2:
	## Get current radial-in direction (toward parent)
	return -get_radial_out()


# === Trajectory Sampling ===

func sample_orbit_points(num_points: int = 100, start_anomaly: float = 0.0, end_anomaly: float = TAU) -> PackedVector2Array:
	## Generate points along the orbit path for visualization
	## Returns positions in parent-relative coordinates

	var points = PackedVector2Array()

	if eccentricity >= 1.0:
		# Hyperbolic - limit the range
		end_anomaly = min(end_anomaly, PI * 0.9)
		start_anomaly = max(start_anomaly, -PI * 0.9)

	var step = (end_anomaly - start_anomaly) / float(num_points - 1)

	for i in range(num_points):
		var nu = start_anomaly + step * i
		var r = OrbitalMechanics.get_radius_at_true_anomaly(semi_major_axis, eccentricity, nu)

		# Position in orbital plane
		var angle = nu + argument_of_periapsis
		var point = Vector2(r * cos(angle), r * sin(angle))
		points.append(point)

	return points


# === Debug ===

func get_debug_string() -> String:
	return "a=%.2f km, e=%.4f, omega=%.2f deg, period=%.2f days" % [
		semi_major_axis / 1000.0,
		eccentricity,
		rad_to_deg(argument_of_periapsis),
		orbital_period / 86400.0
	]
