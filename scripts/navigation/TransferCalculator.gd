class_name TransferCalculator
extends RefCounted
## Calculates interplanetary transfer windows and delta-v requirements
## Used by the navigation system to plan transfers between celestial bodies

# === Flyby Opportunity Data ===

class FlybyOpportunity:
	var planet: Planet = null              # Planet to flyby
	var planet_name: String = ""
	var encounter_time: float = 0.0        # When ship passes closest
	var closest_approach: float = 0.0      # Distance at closest approach (m)
	var dv_benefit: float = 0.0            # Estimated delta-v savings (m/s)
	var turn_angle: float = 0.0            # Trajectory bend angle (radians)
	var is_viable: bool = false            # Within SOI and safe altitude

	func get_info_string() -> String:
		if not is_viable:
			return "%s flyby - Not viable" % planet_name
		return "%s flyby at %s\nΔV benefit: ~%.0f m/s" % [
			planet_name,
			OrbitalConstantsClass.format_timestamp(encounter_time),
			dv_benefit
		]


# === Patched Conic Transfer Data ===

class PatchedConicTransfer:
	## Full interplanetary transfer calculation including escape and capture burns
	## Used when ship is in planetary orbit (not heliocentric)

	# Phase 1: Escape from origin planet
	var escape_dv: float = 0.0              # Delta-v to escape origin planet
	var escape_v_infinity: float = 0.0      # Hyperbolic excess velocity at departure
	var escape_c3: float = 0.0              # Characteristic energy (v_inf²)

	# Phase 2: Heliocentric transfer
	var transfer_time: float = 0.0          # Coast time between planets
	var helio_departure_v: float = 0.0      # Heliocentric velocity after escape
	var helio_arrival_v: float = 0.0        # Heliocentric velocity at arrival

	# Phase 3: Capture at destination
	var capture_dv: float = 0.0             # Delta-v to capture into destination orbit
	var capture_v_infinity: float = 0.0     # Hyperbolic excess velocity at arrival

	# Configuration
	var origin_parking_altitude: float = 0.0  # Ship's orbit altitude at origin (m)
	var target_orbit_altitude: float = 0.0    # Desired orbit altitude at target (m)
	var is_outward: bool = true               # True if going to outer planet

	# References
	var origin_planet: Planet = null
	var target_planet: Planet = null

	# Totals
	var total_dv: float:
		get:
			return escape_dv + capture_dv

	func get_phase_summary() -> String:
		return "ESCAPE: %.0f m/s (v∞=%.1f km/s)\nCOAST: %s\nCAPTURE: %.0f m/s (v∞=%.1f km/s)" % [
			escape_dv,
			escape_v_infinity / 1000.0,
			OrbitalConstantsClass.format_time(transfer_time),
			capture_dv,
			capture_v_infinity / 1000.0
		]


# === Transfer Window Data ===

class TransferWindow:
	var departure_time: float = 0.0      # Simulation time to depart
	var arrival_time: float = 0.0        # Simulation time of arrival
	var transfer_time: float = 0.0       # Duration of transfer
	var departure_dv: float = 0.0        # Delta-v for departure burn (m/s)
	var arrival_dv: float = 0.0          # Delta-v for arrival burn (m/s)
	var total_dv: float = 0.0            # Total delta-v required (m/s)
	var phase_angle: float = 0.0         # Phase angle at departure
	var origin_name: String = ""
	var target_name: String = ""
	var flyby_opportunities: Array[FlybyOpportunity] = []  # Detected flybys

	# Patched conic data (when ship is in planetary orbit)
	var is_patched_conic: bool = false   # True if this uses escape/capture burns
	var patched_conic: PatchedConicTransfer = null
	var escape_dv: float = 0.0           # Phase 1: escape burn
	var capture_dv: float = 0.0          # Phase 3: capture burn

	func get_info_string() -> String:
		var info = "%s → %s\nDepart: %s\nArrive: %s\nΔV: %.1f m/s" % [
			origin_name, target_name,
			OrbitalConstantsClass.format_timestamp(departure_time),
			OrbitalConstantsClass.format_timestamp(arrival_time),
			total_dv
		]
		# Add flyby info if available
		for flyby in flyby_opportunities:
			if flyby.is_viable:
				info += "\n✦ %s assist: -%.0f m/s" % [flyby.planet_name, flyby.dv_benefit]
		return info

	func has_viable_flybys() -> bool:
		for flyby in flyby_opportunities:
			if flyby.is_viable:
				return true
		return false

	func get_best_flyby() -> FlybyOpportunity:
		var best: FlybyOpportunity = null
		for flyby in flyby_opportunities:
			if flyby.is_viable:
				if best == null or flyby.dv_benefit > best.dv_benefit:
					best = flyby
		return best


# === Main Calculation Functions ===

static func calculate_transfer_windows(origin: Planet, target: Planet,
		count: int = 5, start_time: float = -1.0) -> Array[TransferWindow]:
	## Calculate upcoming transfer windows from origin to target
	## Returns array of TransferWindow objects sorted by departure time

	if origin == null or target == null:
		push_error("TransferCalculator: origin or target is null")
		return []

	if origin.parent_body == null or target.parent_body == null:
		push_error("TransferCalculator: bodies must orbit the same parent")
		return []

	# Use current simulation time if not specified
	if start_time < 0:
		start_time = TimeManager.simulation_time

	var windows: Array[TransferWindow] = []
	var sun_mu = origin.parent_body.mu

	# Get orbital radii (using semi-major axis for simplicity)
	var r_origin = origin.orbital_radius
	var r_target = target.orbital_radius

	# Get orbital periods
	var period_origin = origin.get_orbital_period()
	var period_target = target.get_orbital_period()

	# Calculate synodic period (time between windows)
	var synodic = OrbitalMechanics.synodic_period(period_origin, period_target)

	# Calculate required phase angle for Hohmann transfer
	var required_phase = OrbitalMechanics.hohmann_phase_angle(r_origin, r_target, sun_mu)

	# Adjust for inner vs outer planet transfer
	var transferring_outward = r_target > r_origin
	if not transferring_outward:
		# For inward transfer, target needs to be behind, not ahead
		required_phase = TAU - required_phase

	# Get current phase angle
	var current_phase = OrbitalMechanics.calculate_phase_angle(
		origin.world_position - origin.parent_body.world_position,
		target.world_position - target.parent_body.world_position
	)

	# Mean motions
	var n_origin = OrbitalMechanics.get_mean_motion(r_origin, sun_mu)
	var n_target = OrbitalMechanics.get_mean_motion(r_target, sun_mu)
	var angular_rate_diff = n_target - n_origin  # Relative angular velocity

	# Find time to reach required phase angle
	var phase_diff = required_phase - current_phase
	if angular_rate_diff < 0:
		# Target is slower (outer planet), phase_diff should be positive
		while phase_diff < 0:
			phase_diff += TAU
	else:
		# Target is faster (inner planet)
		while phase_diff > 0:
			phase_diff -= TAU
		phase_diff = -phase_diff

	var time_to_first = phase_diff / abs(angular_rate_diff)

	# Ensure first window is in the future
	if time_to_first < 60.0:  # At least 60 seconds from now
		time_to_first += synodic

	# Calculate transfer parameters (same for all windows in Hohmann)
	var transfer = OrbitalMechanics.hohmann_transfer(r_origin, r_target, sun_mu)

	# Generate windows
	for i in range(count):
		var window = TransferWindow.new()
		window.departure_time = start_time + time_to_first + i * synodic
		window.transfer_time = transfer.transfer_time
		window.arrival_time = window.departure_time + transfer.transfer_time
		window.departure_dv = abs(transfer.dv1)
		window.arrival_dv = abs(transfer.dv2)
		window.total_dv = transfer.total_dv
		window.phase_angle = required_phase
		window.origin_name = origin.body_name
		window.target_name = target.body_name

		# Detect potential flyby opportunities along the transfer
		detect_flybys_for_window(window, origin, target)

		windows.append(window)

	return windows


static func calculate_transfer_from_ship(ship: Node, target: Planet,
		count: int = 5) -> Array[TransferWindow]:
	## Calculate transfer windows from ship's current orbit to target planet
	## Assumes ship is in heliocentric orbit (orbiting the Sun)

	if ship == null or target == null:
		return []

	# Get ship's orbital state
	var ship_orbit = ship.orbit_state as OrbitState
	if ship_orbit == null:
		push_error("Ship has no orbit_state")
		return []

	var ship_parent = ship.parent_body as CelestialBody
	if ship_parent == null:
		push_error("Ship has no parent_body")
		return []

	# For now, simplified: use ship's current orbital radius
	# In reality, should calculate from ship's orbit parameters
	var ship_radius = ship_orbit.position.length() + ship_parent.world_position.length()

	# If ship is orbiting a planet (not the Sun), this gets more complex
	# For now, assume heliocentric
	var sun = GameManager.get_sun()
	if sun == null:
		return []

	var sun_mu = sun.mu
	var r_target = target.orbital_radius

	# Similar calculation to planet-to-planet
	var synodic = OrbitalMechanics.synodic_period(
		OrbitalMechanics.get_orbital_period(ship_radius, sun_mu),
		target.get_orbital_period()
	)

	var transfer = OrbitalMechanics.hohmann_transfer(ship_radius, r_target, sun_mu)

	var required_phase = OrbitalMechanics.hohmann_phase_angle(ship_radius, r_target, sun_mu)
	var transferring_outward = r_target > ship_radius
	if not transferring_outward:
		required_phase = TAU - required_phase

	# Current phase (ship to target)
	var ship_world_pos = ship.world_position if ship.has_method("get") else ship_orbit.position
	var target_pos = target.world_position - sun.world_position
	var ship_pos = ship_world_pos - sun.world_position
	var current_phase = OrbitalMechanics.calculate_phase_angle(ship_pos, target_pos)

	var n_ship = OrbitalMechanics.get_mean_motion(ship_radius, sun_mu)
	var n_target = OrbitalMechanics.get_mean_motion(r_target, sun_mu)
	var angular_rate_diff = n_target - n_ship

	var phase_diff = required_phase - current_phase
	if angular_rate_diff < 0:
		while phase_diff < 0:
			phase_diff += TAU
	else:
		while phase_diff > 0:
			phase_diff -= TAU
		phase_diff = -phase_diff

	var time_to_first = phase_diff / abs(angular_rate_diff)
	if time_to_first < 60.0:
		time_to_first += synodic

	var windows: Array[TransferWindow] = []
	var start_time = TimeManager.simulation_time

	for i in range(count):
		var window = TransferWindow.new()
		window.departure_time = start_time + time_to_first + i * synodic
		window.transfer_time = transfer.transfer_time
		window.arrival_time = window.departure_time + transfer.transfer_time
		window.departure_dv = abs(transfer.dv1)
		window.arrival_dv = abs(transfer.dv2)
		window.total_dv = transfer.total_dv
		window.phase_angle = required_phase
		window.origin_name = "Ship"
		window.target_name = target.body_name
		windows.append(window)

	return windows


# === Patched Conic Calculations ===

static func calculate_patched_conic_transfer(
		origin_planet: Planet,
		parking_altitude: float,
		target_planet: Planet,
		target_orbit_altitude: float,
		departure_time: float
	) -> PatchedConicTransfer:
	## Calculate a complete patched conic interplanetary transfer
	##
	## This accounts for:
	## 1. Escape burn from origin planet's parking orbit
	## 2. Heliocentric Hohmann transfer
	## 3. Capture burn into destination orbit

	var transfer = PatchedConicTransfer.new()
	transfer.origin_planet = origin_planet
	transfer.target_planet = target_planet
	transfer.origin_parking_altitude = parking_altitude
	transfer.target_orbit_altitude = target_orbit_altitude

	if origin_planet == null or target_planet == null:
		return transfer
	if origin_planet.parent_body == null:
		return transfer

	var sun = origin_planet.parent_body
	var sun_mu = sun.mu
	var origin_mu = origin_planet.mu
	var target_mu = target_planet.mu

	var r_origin = origin_planet.orbital_radius  # Heliocentric orbital radius
	var r_target = target_planet.orbital_radius
	transfer.is_outward = r_target > r_origin

	# === Phase 2: Heliocentric Transfer (calculate first to get v_infinity values) ===
	var excess = OrbitalMechanics.calculate_hyperbolic_excess_velocity(r_origin, r_target, sun_mu)
	transfer.escape_v_infinity = excess.v_inf_departure
	transfer.capture_v_infinity = excess.v_inf_arrival
	transfer.transfer_time = excess.transfer_time
	transfer.helio_departure_v = excess.v_departure_helio
	transfer.helio_arrival_v = excess.v_arrival_helio

	# === Phase 1: Escape from Origin Planet ===
	var parking_radius = origin_planet.radius + parking_altitude
	var escape_data = OrbitalMechanics.calculate_escape_burn(
		parking_radius,
		transfer.escape_v_infinity,
		origin_mu
	)
	transfer.escape_dv = escape_data.dv
	transfer.escape_c3 = escape_data.c3

	# === Phase 3: Capture at Target Planet ===
	var target_radius = target_planet.radius + target_orbit_altitude
	var capture_data = OrbitalMechanics.calculate_capture_burn(
		transfer.capture_v_infinity,
		target_radius,
		target_mu
	)
	transfer.capture_dv = capture_data.dv

	return transfer


static func calculate_patched_conic_windows(
		ship: Node,
		target: Planet,
		count: int = 5
	) -> Array[TransferWindow]:
	## Calculate transfer windows with full patched conic data
	## Use this when ship is orbiting a planet (not the Sun directly)

	if ship == null or target == null:
		return []

	var ship_orbit = ship.orbit_state as OrbitState
	var ship_parent = ship.parent_body as CelestialBody

	if ship_orbit == null or ship_parent == null:
		return []

	var windows: Array[TransferWindow] = []

	# Check if ship is in heliocentric orbit (orbiting Sun)
	var sun = GameManager.get_sun()
	if ship_parent == sun or ship_parent.body_name == "Sun":
		# Use simple heliocentric calculation
		return calculate_transfer_from_ship(ship, target, count)

	# Ship is orbiting a planet - use patched conic approach
	var origin_planet = ship_parent as Planet
	if origin_planet == null:
		return []

	# Don't allow transfer to the planet we're orbiting
	if origin_planet == target:
		return []

	# Get ship's parking orbit altitude
	var parking_altitude = ship_orbit.semi_major_axis - origin_planet.radius

	# Default target orbit altitude (400 km)
	var target_altitude = 400.0 * 1000.0

	# Get base Hohmann windows for timing (planet-to-planet)
	var base_windows = calculate_transfer_windows(origin_planet, target, count)

	# Enhance each window with patched conic data
	for base in base_windows:
		var patched = calculate_patched_conic_transfer(
			origin_planet,
			parking_altitude,
			target,
			target_altitude,
			base.departure_time
		)

		var window = TransferWindow.new()
		window.departure_time = base.departure_time
		window.arrival_time = base.arrival_time
		window.transfer_time = base.transfer_time
		window.phase_angle = base.phase_angle
		window.origin_name = origin_planet.body_name
		window.target_name = target.body_name

		# Patched conic data
		window.is_patched_conic = true
		window.patched_conic = patched
		window.escape_dv = patched.escape_dv
		window.capture_dv = patched.capture_dv
		window.total_dv = patched.total_dv

		# Keep old fields for compatibility (now represent escape/capture)
		window.departure_dv = patched.escape_dv
		window.arrival_dv = patched.capture_dv

		# Copy flyby data from base window
		window.flyby_opportunities = base.flyby_opportunities

		windows.append(window)

	return windows


# === Utility Functions ===

static func get_available_targets(exclude_body: CelestialBody = null, sort_by_distance: bool = true) -> Array[Planet]:
	## Get list of planets that can be targeted for transfer
	## Optionally exclude a specific body (e.g., the one the ship is orbiting)
	## Sorted by orbital radius (distance from Sun) by default
	var planets: Array[Planet] = []
	var bodies = GameManager.get_all_celestial_bodies()

	for body in bodies:
		if body is Planet:
			# Exclude the specified body if provided
			if exclude_body != null and body == exclude_body:
				continue
			planets.append(body as Planet)

	# Sort by orbital radius (distance from Sun)
	if sort_by_distance:
		planets.sort_custom(func(a, b): return a.orbital_radius < b.orbital_radius)

	return planets


static func estimate_transfer_dv(r1: float, r2: float, mu: float) -> float:
	## Quick estimate of total delta-v for a transfer
	var transfer = OrbitalMechanics.hohmann_transfer(r1, r2, mu)
	return transfer.total_dv


static func format_transfer_summary(window: TransferWindow) -> String:
	## Format a transfer window for display
	var time_until = window.departure_time - TimeManager.simulation_time
	var summary = "%s → %s | T-%s | ΔV: %.1f km/s" % [
		window.origin_name,
		window.target_name,
		OrbitalConstantsClass.format_time(time_until),
		window.total_dv / 1000.0
	]
	if window.has_viable_flybys():
		var best = window.get_best_flyby()
		summary += " [%s assist]" % best.planet_name
	return summary


# === Flyby Detection ===

static func detect_flybys_for_window(window: TransferWindow, origin: Planet,
		target: Planet) -> void:
	## Detect potential gravity assist opportunities along a transfer trajectory
	## Modifies window.flyby_opportunities in place

	if origin == null or target == null:
		return
	if origin.parent_body == null:
		return

	var sun = origin.parent_body
	var sun_mu = sun.mu
	var r_origin = origin.orbital_radius
	var r_target = target.orbital_radius

	# Get transfer orbit parameters
	var a_transfer = (r_origin + r_target) / 2.0
	var e_transfer = abs(r_target - r_origin) / (r_target + r_origin)

	# Determine transfer direction
	var is_outward = r_target > r_origin

	# Get all other planets that might be along the path
	var all_bodies = GameManager.get_all_celestial_bodies()

	for body in all_bodies:
		if not body is Planet:
			continue
		var planet = body as Planet

		# Skip origin and target
		if planet == origin or planet == target:
			continue

		# Skip if not orbiting the same parent
		if planet.parent_body != sun:
			continue

		var r_planet = planet.orbital_radius

		# Check if planet's orbit intersects our transfer ellipse
		var r_pe_transfer = r_origin if is_outward else r_target
		var r_ap_transfer = r_target if is_outward else r_origin

		# Planet must be between origin and target orbital radii
		if r_planet < r_pe_transfer * 0.9 or r_planet > r_ap_transfer * 1.1:
			continue

		# Calculate where on the transfer orbit we'd be at this radius
		var flyby = _calculate_flyby_opportunity(window, planet, sun_mu,
			a_transfer, e_transfer, r_origin, is_outward)

		if flyby != null:
			window.flyby_opportunities.append(flyby)


static func _calculate_flyby_opportunity(window: TransferWindow, planet: Planet,
		sun_mu: float, a_transfer: float, e_transfer: float,
		r_origin: float, is_outward: bool) -> FlybyOpportunity:
	## Calculate details of a potential flyby opportunity

	var r_planet = planet.orbital_radius
	var flyby = FlybyOpportunity.new()
	flyby.planet = planet
	flyby.planet_name = planet.body_name

	# Calculate true anomaly where transfer orbit crosses planet's orbital radius
	# r = a(1-e²)/(1 + e*cos(ν)) => cos(ν) = (a(1-e²)/r - 1) / e
	var p = a_transfer * (1.0 - e_transfer * e_transfer)  # Semi-latus rectum

	if e_transfer < 0.001:
		# Nearly circular transfer - shouldn't happen for Hohmann
		return null

	var cos_nu = (p / r_planet - 1.0) / e_transfer

	# Check if orbit actually reaches this radius
	if abs(cos_nu) > 1.0:
		return null

	var nu = acos(cos_nu)

	# For outward transfer, we start at periapsis (ν=0) and travel to apoapsis (ν=π)
	# For inward transfer, we start at apoapsis (ν=π) and travel to periapsis (ν=2π)
	if not is_outward:
		nu = TAU - nu  # Use the other crossing point

	# Calculate time from departure to reach this true anomaly
	# Using Kepler's equation
	var E = OrbitalMechanics.true_to_eccentric_anomaly(nu, e_transfer)
	var M = E - e_transfer * sin(E)
	var n = sqrt(sun_mu / pow(a_transfer, 3))  # Mean motion
	var time_to_crossing = M / n

	flyby.encounter_time = window.departure_time + time_to_crossing

	# Calculate where the planet will be at encounter time
	var planet_period = planet.get_orbital_period()
	var planet_n = TAU / planet_period
	var dt_from_now = flyby.encounter_time - TimeManager.simulation_time

	# Get planet's current position angle
	var planet_current_angle = atan2(
		planet.world_position.y - planet.parent_body.world_position.y,
		planet.world_position.x - planet.parent_body.world_position.x
	)

	# Planet position at encounter
	var planet_angle_at_encounter = planet_current_angle + planet_n * dt_from_now

	# Ship position at encounter (angle on transfer orbit)
	var ship_angle_at_encounter: float
	if is_outward:
		# Starting from periapsis at origin's position
		var origin_angle = atan2(
			planet.parent_body.world_position.y,  # Sun at origin
			planet.parent_body.world_position.x
		)
		# Actually we need the origin planet's angle at departure
		# For simplicity, use argument of periapsis as origin direction
		ship_angle_at_encounter = nu  # True anomaly on transfer orbit
	else:
		ship_angle_at_encounter = nu

	# Angular separation at encounter (simplified - assumes coplanar)
	var angle_diff = abs(planet_angle_at_encounter - ship_angle_at_encounter)
	angle_diff = fmod(angle_diff, TAU)
	if angle_diff > PI:
		angle_diff = TAU - angle_diff

	# Convert angular separation to approximate distance
	flyby.closest_approach = r_planet * angle_diff

	# Check if within planet's SOI
	var planet_soi = planet.sphere_of_influence
	if planet_soi <= 0:
		planet_soi = r_planet * 0.01  # Fallback: 1% of orbital radius

	flyby.is_viable = flyby.closest_approach < planet_soi

	if flyby.is_viable:
		# Calculate potential delta-v benefit from gravity assist
		flyby.dv_benefit = _estimate_gravity_assist_dv(
			planet, r_planet, sun_mu, a_transfer, e_transfer, flyby.closest_approach
		)
		flyby.turn_angle = _estimate_turn_angle(planet, flyby.closest_approach)

	return flyby


static func _estimate_gravity_assist_dv(planet: Planet, r_planet: float,
		sun_mu: float, a_transfer: float, e_transfer: float,
		closest_approach: float) -> float:
	## Estimate the delta-v benefit from a gravity assist
	## Uses the patched conic approximation

	# Spacecraft velocity relative to Sun at the flyby point
	var v_spacecraft = OrbitalMechanics.vis_viva(r_planet, a_transfer, sun_mu)

	# Planet's orbital velocity
	var v_planet = sqrt(sun_mu / r_planet)

	# Relative velocity (simplified - assumes optimal geometry)
	var v_inf = abs(v_spacecraft - v_planet)

	# Turn angle depends on closest approach and planet's gravity
	var planet_mu = planet.mu
	if planet_mu <= 0:
		return 0.0

	# Minimum safe periapsis (above atmosphere/surface)
	var min_periapsis = planet.radius * 1.1  # 10% above surface
	var periapsis = maxf(closest_approach, min_periapsis)

	# Turn angle: sin(δ/2) = 1 / (1 + r_p * v_inf² / μ)
	var turn_param = 1.0 + periapsis * v_inf * v_inf / planet_mu
	var sin_half_delta = 1.0 / turn_param
	var delta = 2.0 * asin(minf(sin_half_delta, 1.0))  # Clamp to valid range

	# Delta-v from turning the velocity vector
	# Δv = 2 * v_inf * sin(δ/2)
	var dv_benefit = 2.0 * v_inf * sin_half_delta

	return dv_benefit


static func _estimate_turn_angle(planet: Planet, closest_approach: float) -> float:
	## Estimate the trajectory turn angle for a flyby

	var planet_mu = planet.mu
	if planet_mu <= 0:
		return 0.0

	# Assuming a typical interplanetary v_infinity of ~5 km/s
	var v_inf = 5000.0  # m/s (rough estimate)

	var min_periapsis = planet.radius * 1.1
	var periapsis = maxf(closest_approach, min_periapsis)

	var turn_param = 1.0 + periapsis * v_inf * v_inf / planet_mu
	var sin_half_delta = 1.0 / turn_param

	return 2.0 * asin(minf(sin_half_delta, 1.0))
