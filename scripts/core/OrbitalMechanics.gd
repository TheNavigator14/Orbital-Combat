class_name OrbitalMechanics
extends RefCounted
## Core orbital mechanics calculations
## Handles Kepler equation solving, coordinate conversions, and transfer calculations

# === Kepler Equation Solver ===

static func solve_kepler(mean_anomaly: float, eccentricity: float, tolerance: float = 1e-10, max_iterations: int = 50) -> float:
	## Solve Kepler's equation M = E - e*sin(E) for eccentric anomaly E
	## Uses Newton-Raphson iteration
	## For hyperbolic orbits (e > 1), solves M = e*sinh(H) - H for hyperbolic anomaly H

	var M = fmod(mean_anomaly, TAU)
	if M < 0:
		M += TAU

	if eccentricity < 1.0:
		# Elliptical orbit - solve for eccentric anomaly E
		var E = M if eccentricity < 0.8 else PI  # Initial guess

		for i in range(max_iterations):
			var f = E - eccentricity * sin(E) - M
			var f_prime = 1.0 - eccentricity * cos(E)
			var delta = f / f_prime
			E -= delta

			if abs(delta) < tolerance:
				return E

		push_warning("Kepler solver did not converge for e=%.4f, M=%.4f" % [eccentricity, mean_anomaly])
		return E

	elif eccentricity > 1.0:
		# Hyperbolic orbit - solve for hyperbolic anomaly H
		var H = M  # Initial guess

		for i in range(max_iterations):
			var f = eccentricity * sinh(H) - H - M
			var f_prime = eccentricity * cosh(H) - 1.0
			var delta = f / f_prime
			H -= delta

			if abs(delta) < tolerance:
				return H

		push_warning("Hyperbolic Kepler solver did not converge")
		return H

	else:
		# Parabolic orbit (e = 1) - use Barker's equation
		# For simplicity, treat as slightly elliptical
		return M


static func eccentric_to_true_anomaly(E: float, eccentricity: float) -> float:
	## Convert eccentric anomaly to true anomaly
	if eccentricity < 1.0:
		# Elliptical
		var beta = eccentricity / (1.0 + sqrt(1.0 - eccentricity * eccentricity))
		return E + 2.0 * atan2(beta * sin(E), 1.0 - beta * cos(E))
	else:
		# Hyperbolic
		return 2.0 * atan(sqrt((eccentricity + 1.0) / (eccentricity - 1.0)) * tanh(E / 2.0))


static func true_to_eccentric_anomaly(true_anomaly: float, eccentricity: float) -> float:
	## Convert true anomaly to eccentric anomaly
	var nu = true_anomaly
	if eccentricity < 1.0:
		# Elliptical
		return atan2(sqrt(1.0 - eccentricity * eccentricity) * sin(nu), eccentricity + cos(nu))
	else:
		# Hyperbolic
		var tanh_H_2 = sqrt((eccentricity - 1.0) / (eccentricity + 1.0)) * tan(nu / 2.0)
		return 2.0 * atanh(tanh_H_2)


# === Orbital Element Conversions ===

static func elements_to_state(semi_major_axis: float, eccentricity: float,
		arg_periapsis: float, mean_anomaly: float, mu: float) -> Dictionary:
	## Convert orbital elements to state vectors (position and velocity)
	## Returns: { "position": Vector2, "velocity": Vector2 }

	# Solve Kepler's equation for eccentric anomaly
	var E = solve_kepler(mean_anomaly, eccentricity)

	# Get true anomaly
	var nu = eccentric_to_true_anomaly(E, eccentricity)

	# Calculate distance from focus
	var r: float
	if eccentricity < 1.0:
		r = semi_major_axis * (1.0 - eccentricity * cos(E))
	else:
		r = semi_major_axis * (eccentricity * cosh(E) - 1.0)

	# Position in orbital plane (perifocal frame)
	var pos_orbital = Vector2(r * cos(nu), r * sin(nu))

	# Velocity in orbital plane
	var p = semi_major_axis * (1.0 - eccentricity * eccentricity)  # Semi-latus rectum
	if eccentricity >= 1.0:
		p = semi_major_axis * (eccentricity * eccentricity - 1.0)

	var h = sqrt(mu * abs(p))  # Specific angular momentum
	var vel_orbital = Vector2(
		-mu / h * sin(nu),
		mu / h * (eccentricity + cos(nu))
	)

	# Rotate by argument of periapsis to get inertial frame
	var cos_w = cos(arg_periapsis)
	var sin_w = sin(arg_periapsis)

	var position = Vector2(
		pos_orbital.x * cos_w - pos_orbital.y * sin_w,
		pos_orbital.x * sin_w + pos_orbital.y * cos_w
	)

	var velocity = Vector2(
		vel_orbital.x * cos_w - vel_orbital.y * sin_w,
		vel_orbital.x * sin_w + vel_orbital.y * cos_w
	)

	return { "position": position, "velocity": velocity }


static func state_to_elements(position: Vector2, velocity: Vector2, mu: float) -> Dictionary:
	## Convert state vectors to orbital elements
	## Returns dictionary with: semi_major_axis, eccentricity, arg_periapsis, true_anomaly, mean_anomaly

	var r = position.length()
	var v = velocity.length()

	# Specific orbital energy
	var energy = v * v / 2.0 - mu / r

	# Semi-major axis
	var a: float
	if abs(energy) > 1e-10:
		a = -mu / (2.0 * energy)
	else:
		a = INF  # Parabolic

	# Specific angular momentum (scalar in 2D, cross product gives z-component)
	var h = position.x * velocity.y - position.y * velocity.x

	# Eccentricity vector
	var e_vec = Vector2(
		(v * v - mu / r) * position.x / mu - (position.dot(velocity)) * velocity.x / mu,
		(v * v - mu / r) * position.y / mu - (position.dot(velocity)) * velocity.y / mu
	)
	var e = e_vec.length()

	# Argument of periapsis (angle from +x axis to periapsis)
	var omega: float
	if e > 1e-10:
		omega = atan2(e_vec.y, e_vec.x)
	else:
		omega = 0.0  # Circular orbit, undefined periapsis

	# True anomaly (angle from periapsis to current position)
	var nu = atan2(position.y, position.x) - omega
	nu = fmod(nu + TAU, TAU)  # Normalize to [0, 2*PI]

	# Eccentric anomaly and mean anomaly
	var E = true_to_eccentric_anomaly(nu, e)
	var M: float
	if e < 1.0:
		M = E - e * sin(E)
	else:
		M = e * sinh(E) - E

	return {
		"semi_major_axis": a,
		"eccentricity": e,
		"arg_periapsis": omega,
		"true_anomaly": nu,
		"eccentric_anomaly": E,
		"mean_anomaly": M,
		"specific_angular_momentum": h,
		"specific_energy": energy
	}


# === Orbital Parameters ===

static func get_orbital_period(semi_major_axis: float, mu: float) -> float:
	## Calculate orbital period: T = 2*PI*sqrt(a^3/mu)
	if semi_major_axis <= 0:
		return INF  # Hyperbolic/parabolic has no period
	return TAU * sqrt(pow(semi_major_axis, 3) / mu)


static func get_mean_motion(semi_major_axis: float, mu: float) -> float:
	## Calculate mean motion: n = sqrt(mu/a^3)
	if semi_major_axis <= 0:
		return 0.0
	return sqrt(mu / pow(semi_major_axis, 3))


static func vis_viva(radius: float, semi_major_axis: float, mu: float) -> float:
	## Calculate orbital velocity at given radius using vis-viva equation
	## v^2 = mu * (2/r - 1/a)
	if semi_major_axis == INF:
		# Parabolic - escape velocity
		return sqrt(2.0 * mu / radius)
	return sqrt(mu * (2.0 / radius - 1.0 / semi_major_axis))


static func get_apoapsis(semi_major_axis: float, eccentricity: float) -> float:
	## Calculate apoapsis distance: r_a = a * (1 + e)
	if eccentricity >= 1.0:
		return INF  # Hyperbolic has no apoapsis
	return semi_major_axis * (1.0 + eccentricity)


static func get_periapsis(semi_major_axis: float, eccentricity: float) -> float:
	## Calculate periapsis distance: r_p = a * (1 - e)
	## For hyperbolic orbits: r_p = a * (e - 1) but a is negative
	if eccentricity >= 1.0:
		return abs(semi_major_axis) * (eccentricity - 1.0)
	return semi_major_axis * (1.0 - eccentricity)


static func get_semi_latus_rectum(semi_major_axis: float, eccentricity: float) -> float:
	## Calculate semi-latus rectum: p = a * (1 - e^2)
	if eccentricity < 1.0:
		return semi_major_axis * (1.0 - eccentricity * eccentricity)
	else:
		return abs(semi_major_axis) * (eccentricity * eccentricity - 1.0)


static func get_radius_at_true_anomaly(semi_major_axis: float, eccentricity: float, true_anomaly: float) -> float:
	## Calculate orbital radius at a given true anomaly
	## r = p / (1 + e*cos(nu))
	var p = get_semi_latus_rectum(semi_major_axis, eccentricity)
	return p / (1.0 + eccentricity * cos(true_anomaly))


# === Transfer Calculations ===

static func hohmann_transfer(r1: float, r2: float, mu: float) -> Dictionary:
	## Calculate Hohmann transfer between two circular orbits
	## Returns: { dv1, dv2, transfer_time, total_dv }

	# Transfer orbit semi-major axis
	var a_transfer = (r1 + r2) / 2.0

	# Circular velocities
	var v_circ_1 = sqrt(mu / r1)
	var v_circ_2 = sqrt(mu / r2)

	# Transfer orbit velocities at periapsis and apoapsis
	var v_transfer_1 = sqrt(mu * (2.0 / r1 - 1.0 / a_transfer))
	var v_transfer_2 = sqrt(mu * (2.0 / r2 - 1.0 / a_transfer))

	# Delta-v for each burn
	var dv1 = v_transfer_1 - v_circ_1  # Positive = prograde
	var dv2 = v_circ_2 - v_transfer_2  # Positive = prograde

	# Transfer time (half period of transfer orbit)
	var transfer_time = PI * sqrt(pow(a_transfer, 3) / mu)

	return {
		"dv1": dv1,
		"dv2": dv2,
		"total_dv": abs(dv1) + abs(dv2),
		"transfer_time": transfer_time,
		"transfer_semi_major_axis": a_transfer
	}


static func calculate_escape_velocity(radius: float, mu: float) -> float:
	## Calculate escape velocity at given radius: v_esc = sqrt(2*mu/r)
	return sqrt(2.0 * mu / radius)


static func calculate_circular_velocity(radius: float, mu: float) -> float:
	## Calculate circular orbital velocity at given radius: v_circ = sqrt(mu/r)
	return sqrt(mu / radius)


# === Propagation ===

static func propagate_mean_anomaly(mean_anomaly_0: float, mean_motion: float, delta_time: float) -> float:
	## Propagate mean anomaly forward in time
	## M(t) = M_0 + n * dt
	var M = mean_anomaly_0 + mean_motion * delta_time
	return fmod(M, TAU)


# === Orbital Frame Vectors ===

static func get_prograde_direction(velocity: Vector2) -> Vector2:
	## Get unit vector in prograde (velocity) direction
	if velocity.length_squared() < 1e-10:
		return Vector2.RIGHT
	return velocity.normalized()


static func get_radial_direction(position: Vector2) -> Vector2:
	## Get unit vector in radial-out direction (away from parent body)
	if position.length_squared() < 1e-10:
		return Vector2.UP
	return position.normalized()


static func get_orbital_frame(position: Vector2, velocity: Vector2) -> Dictionary:
	## Get orbital reference frame vectors
	## Returns: { prograde, retrograde, radial_out, radial_in }
	var prograde = get_prograde_direction(velocity)
	var radial_out = get_radial_direction(position)

	return {
		"prograde": prograde,
		"retrograde": -prograde,
		"radial_out": radial_out,
		"radial_in": -radial_out
	}


# === Numerical Integration ===

static func rk4_step(position: Vector2, velocity: Vector2, mu: float, dt: float,
		thrust_accel: Vector2 = Vector2.ZERO) -> Dictionary:
	## Single RK4 integration step for orbital motion with optional thrust
	## Returns: { position, velocity }

	# Gravitational acceleration function
	var gravity_accel = func(pos: Vector2) -> Vector2:
		var r = pos.length()
		if r < 1.0:
			return Vector2.ZERO
		return -mu / (r * r * r) * pos

	# k1
	var k1_v = velocity
	var k1_a = gravity_accel.call(position) + thrust_accel

	# k2
	var k2_v = velocity + k1_a * (dt / 2.0)
	var k2_a = gravity_accel.call(position + k1_v * (dt / 2.0)) + thrust_accel

	# k3
	var k3_v = velocity + k2_a * (dt / 2.0)
	var k3_a = gravity_accel.call(position + k2_v * (dt / 2.0)) + thrust_accel

	# k4
	var k4_v = velocity + k3_a * dt
	var k4_a = gravity_accel.call(position + k3_v * dt) + thrust_accel

	# Combine
	var new_position = position + (dt / 6.0) * (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v)
	var new_velocity = velocity + (dt / 6.0) * (k1_a + 2.0 * k2_a + 2.0 * k3_a + k4_a)

	return { "position": new_position, "velocity": new_velocity }
