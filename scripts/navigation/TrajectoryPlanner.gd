class_name TrajectoryPlanner
extends RefCounted
## Converts high-level navigation goals into ManeuverNodes
## Used by the Navigation Planner UI to create executable maneuvers

# === Navigation Goals ===

enum Goal {
	TRANSFER_TO_PLANET,    # Interplanetary transfer
	CIRCULARIZE_AT_AP,     # Circularize at apoapsis
	CIRCULARIZE_AT_PE,     # Circularize at periapsis
	RAISE_APOAPSIS,        # Increase apoapsis altitude
	LOWER_APOAPSIS,        # Decrease apoapsis altitude
	RAISE_PERIAPSIS,       # Increase periapsis altitude
	LOWER_PERIAPSIS,       # Decrease periapsis altitude
	CHANGE_ALTITUDE,       # Hohmann to new altitude
}

# === Planned Maneuvers Result ===

class ManeuverPlan:
	var maneuvers: Array[ManeuverNode] = []
	var goal: Goal = Goal.CIRCULARIZE_AT_AP
	var description: String = ""
	var total_delta_v: float = 0.0
	var total_time: float = 0.0
	var is_valid: bool = false
	var error_message: String = ""

	func add_maneuver(node: ManeuverNode) -> void:
		maneuvers.append(node)
		total_delta_v += node.get_delta_v_magnitude()
		if maneuvers.size() > 1:
			total_time = maneuvers[-1].execution_time - maneuvers[0].execution_time


# === Main Planning Functions ===

static func plan_transfer_to_planet(ship: Node, target: Planet,
		window: TransferCalculator.TransferWindow) -> ManeuverPlan:
	## Plan a transfer to another planet using a specific window
	## Handles both simple heliocentric transfers and patched conic (escape/capture) transfers
	var plan = ManeuverPlan.new()
	plan.goal = Goal.TRANSFER_TO_PLANET

	if ship == null or target == null or window == null:
		plan.error_message = "Invalid ship, target, or window"
		return plan

	var ship_orbit = ship.orbit_state as OrbitState
	if ship_orbit == null:
		plan.error_message = "Ship has no orbit state"
		return plan

	# Check if this is a patched conic transfer (ship in planetary orbit)
	if window.is_patched_conic and window.patched_conic != null:
		return _plan_patched_conic_transfer(ship, target, window)

	# Simple heliocentric transfer (ship already in solar orbit)
	return _plan_heliocentric_transfer(ship, target, window)


static func _plan_heliocentric_transfer(ship: Node, target: Planet,
		window: TransferCalculator.TransferWindow) -> ManeuverPlan:
	## Plan a simple heliocentric Hohmann transfer (ship already orbiting the Sun)
	var plan = ManeuverPlan.new()
	plan.goal = Goal.TRANSFER_TO_PLANET

	var ship_orbit = ship.orbit_state as OrbitState

	# Get orbital state at departure time
	var departure_state = ship_orbit.get_state_at_time(window.departure_time)
	var prograde = OrbitalMechanics.get_prograde_direction(departure_state.velocity)

	# Departure burn (prograde for outward transfer)
	var departure_dv = prograde * window.departure_dv
	var departure_node = ship.plan_maneuver(window.departure_time, departure_dv)
	plan.maneuvers.append(departure_node)

	# Arrival burn - need to recalculate prograde at arrival
	if departure_node.resulting_orbit:
		var arrival_state = departure_node.resulting_orbit.get_state_at_time(window.arrival_time)
		var arrival_prograde = OrbitalMechanics.get_prograde_direction(arrival_state.velocity)

		var r_ship = ship_orbit.position.length()
		var r_target = target.orbital_radius
		var is_outward = r_target > r_ship

		var arrival_dv: Vector2
		if is_outward:
			arrival_dv = arrival_prograde * window.arrival_dv
		else:
			arrival_dv = -arrival_prograde * window.arrival_dv

		var arrival_node = ship.plan_maneuver(window.arrival_time, arrival_dv)
		plan.maneuvers.append(arrival_node)

	plan.total_delta_v = window.total_dv
	plan.total_time = window.transfer_time
	plan.description = "Transfer to %s" % target.body_name
	plan.is_valid = true

	return plan


static func _plan_patched_conic_transfer(ship: Node, target: Planet,
		window: TransferCalculator.TransferWindow) -> ManeuverPlan:
	## Plan a patched conic transfer with escape and capture burns
	## Used when ship is orbiting a planet (not the Sun directly)
	var plan = ManeuverPlan.new()
	plan.goal = Goal.TRANSFER_TO_PLANET

	var ship_orbit = ship.orbit_state as OrbitState
	var patched = window.patched_conic
	var origin_planet = ship.parent_body as Planet

	if origin_planet == null:
		plan.error_message = "Ship not orbiting a planet"
		return plan

	# === BURN 1: ESCAPE BURN ===
	# The escape burn happens at periapsis of the parking orbit for maximum efficiency
	# We need to burn prograde to increase orbital energy and escape

	var current_time = TimeManager.simulation_time

	# Find next periapsis (best place to burn for escape)
	var time_to_pe = ship_orbit.time_to_periapsis(current_time)
	var escape_time = current_time + time_to_pe

	# Make sure escape happens before the transfer window closes
	# The window.departure_time is when we should leave the planet's SOI
	# We need to escape early enough to reach the SOI boundary at the right time
	# For now, use the transfer window time as the escape burn time
	# (In reality, we'd calculate backwards from SOI boundary)
	escape_time = window.departure_time

	# If escape time is too soon, wait for next orbit
	if escape_time < current_time + 60.0:
		escape_time += ship_orbit.orbital_period

	# Get state at escape burn time
	var escape_state = ship_orbit.get_state_at_time(escape_time)
	var escape_prograde = OrbitalMechanics.get_prograde_direction(escape_state.velocity)

	# Escape burn is always prograde (to increase energy and escape)
	var escape_dv = escape_prograde * patched.escape_dv
	var escape_node = ship.plan_maneuver(escape_time, escape_dv)
	escape_node.burn_type = "ESCAPE"
	plan.maneuvers.append(escape_node)

	# === BURN 2: CAPTURE BURN (Deferred) ===
	# The capture burn happens when we enter the target planet's SOI
	# We can't precisely calculate its direction until we're there
	# Create a "pending" capture maneuver that will be activated on SOI entry

	var capture_node = ManeuverNode.new()
	capture_node.execution_time = window.arrival_time
	capture_node.burn_type = "CAPTURE"
	capture_node.is_pending_capture = true
	capture_node.target_planet = target
	capture_node.expected_dv_magnitude = patched.capture_dv

	# For the capture burn, we'll need to burn retrograde when entering the SOI
	# The magnitude is capture_dv, direction will be recalculated on SOI entry
	# For now, set a placeholder that shows the expected delta-v
	capture_node.delta_v = Vector2.LEFT * patched.capture_dv  # Placeholder direction

	# Note: Don't add capture node to ship's planned_maneuvers yet
	# It will be activated when entering target SOI
	# But we add it to the plan for display purposes
	plan.maneuvers.append(capture_node)

	plan.total_delta_v = patched.total_dv
	plan.total_time = window.transfer_time
	plan.description = "Transfer: %s → %s (Patched Conic)" % [origin_planet.body_name, target.body_name]
	plan.is_valid = true

	return plan


static func plan_circularize(ship: Node, at_apoapsis: bool = true) -> ManeuverPlan:
	## Plan a burn to circularize the orbit at apoapsis or periapsis
	var plan = ManeuverPlan.new()
	plan.goal = Goal.CIRCULARIZE_AT_AP if at_apoapsis else Goal.CIRCULARIZE_AT_PE

	if ship == null:
		plan.error_message = "Invalid ship"
		return plan

	var ship_orbit = ship.orbit_state as OrbitState
	var parent = ship.parent_body as CelestialBody
	if ship_orbit == null or parent == null:
		plan.error_message = "Ship has no valid orbit"
		return plan

	var current_time = TimeManager.simulation_time

	# Get execution time and orbital radius at that point
	var execution_time: float
	var target_radius: float

	if at_apoapsis:
		execution_time = current_time + ship_orbit.time_to_apoapsis(current_time)
		target_radius = ship_orbit.apoapsis
		plan.description = "Circularize at Apoapsis"
	else:
		execution_time = current_time + ship_orbit.time_to_periapsis(current_time)
		target_radius = ship_orbit.periapsis
		plan.description = "Circularize at Periapsis"

	# Ensure execution is in the future
	if execution_time < current_time + 30.0:
		# Add one orbit
		execution_time += ship_orbit.orbital_period

	# Calculate delta-v needed
	# Current velocity at that point
	var state_at_burn = ship_orbit.get_state_at_time(execution_time)
	var current_velocity = state_at_burn.velocity.length()

	# Circular velocity at that radius
	var circular_velocity = OrbitalMechanics.calculate_circular_velocity(target_radius, parent.mu)

	# Delta-v (positive = prograde, negative = retrograde)
	var delta_v_magnitude = circular_velocity - current_velocity

	# Get prograde direction at burn time
	var prograde = OrbitalMechanics.get_prograde_direction(state_at_burn.velocity)
	var delta_v = prograde * delta_v_magnitude

	var node = ship.plan_maneuver(execution_time, delta_v)
	plan.add_maneuver(node)
	plan.is_valid = true

	return plan


static func plan_change_apoapsis(ship: Node, new_apoapsis: float) -> ManeuverPlan:
	## Plan a burn at periapsis to change the apoapsis altitude
	var plan = ManeuverPlan.new()

	if ship == null:
		plan.error_message = "Invalid ship"
		return plan

	var ship_orbit = ship.orbit_state as OrbitState
	var parent = ship.parent_body as CelestialBody
	if ship_orbit == null or parent == null:
		plan.error_message = "Ship has no valid orbit"
		return plan

	var current_time = TimeManager.simulation_time
	var current_ap = ship_orbit.apoapsis
	var current_pe = ship_orbit.periapsis

	# Burn at periapsis to change apoapsis
	var execution_time = current_time + ship_orbit.time_to_periapsis(current_time)
	if execution_time < current_time + 30.0:
		execution_time += ship_orbit.orbital_period

	# Calculate new orbit semi-major axis
	var new_a = (current_pe + new_apoapsis) / 2.0

	# Current velocity at periapsis
	var v_current = OrbitalMechanics.vis_viva(current_pe, ship_orbit.semi_major_axis, parent.mu)

	# Required velocity for new orbit
	var v_required = OrbitalMechanics.vis_viva(current_pe, new_a, parent.mu)

	var delta_v_magnitude = v_required - v_current

	# Get state at burn time
	var state_at_burn = ship_orbit.get_state_at_time(execution_time)
	var prograde = OrbitalMechanics.get_prograde_direction(state_at_burn.velocity)
	var delta_v = prograde * delta_v_magnitude

	var node = ship.plan_maneuver(execution_time, delta_v)
	plan.add_maneuver(node)

	if new_apoapsis > current_ap:
		plan.goal = Goal.RAISE_APOAPSIS
		plan.description = "Raise Apoapsis to %s" % OrbitalConstantsClass.format_distance(new_apoapsis)
	else:
		plan.goal = Goal.LOWER_APOAPSIS
		plan.description = "Lower Apoapsis to %s" % OrbitalConstantsClass.format_distance(new_apoapsis)

	plan.is_valid = true
	return plan


static func plan_change_periapsis(ship: Node, new_periapsis: float) -> ManeuverPlan:
	## Plan a burn at apoapsis to change the periapsis altitude
	var plan = ManeuverPlan.new()

	if ship == null:
		plan.error_message = "Invalid ship"
		return plan

	var ship_orbit = ship.orbit_state as OrbitState
	var parent = ship.parent_body as CelestialBody
	if ship_orbit == null or parent == null:
		plan.error_message = "Ship has no valid orbit"
		return plan

	var current_time = TimeManager.simulation_time
	var current_ap = ship_orbit.apoapsis
	var current_pe = ship_orbit.periapsis

	# Burn at apoapsis to change periapsis
	var execution_time = current_time + ship_orbit.time_to_apoapsis(current_time)
	if execution_time < current_time + 30.0:
		execution_time += ship_orbit.orbital_period

	# Calculate new orbit semi-major axis
	var new_a = (current_ap + new_periapsis) / 2.0

	# Current velocity at apoapsis
	var v_current = OrbitalMechanics.vis_viva(current_ap, ship_orbit.semi_major_axis, parent.mu)

	# Required velocity for new orbit
	var v_required = OrbitalMechanics.vis_viva(current_ap, new_a, parent.mu)

	var delta_v_magnitude = v_required - v_current

	# Get state at burn time
	var state_at_burn = ship_orbit.get_state_at_time(execution_time)
	var prograde = OrbitalMechanics.get_prograde_direction(state_at_burn.velocity)
	var delta_v = prograde * delta_v_magnitude

	var node = ship.plan_maneuver(execution_time, delta_v)
	plan.add_maneuver(node)

	if new_periapsis > current_pe:
		plan.goal = Goal.RAISE_PERIAPSIS
		plan.description = "Raise Periapsis to %s" % OrbitalConstantsClass.format_distance(new_periapsis)
	else:
		plan.goal = Goal.LOWER_PERIAPSIS
		plan.description = "Lower Periapsis to %s" % OrbitalConstantsClass.format_distance(new_periapsis)

	plan.is_valid = true
	return plan


static func plan_hohmann_transfer(ship: Node, target_altitude: float) -> ManeuverPlan:
	## Plan a Hohmann transfer to a new circular orbit altitude
	## This is a two-burn maneuver
	var plan = ManeuverPlan.new()
	plan.goal = Goal.CHANGE_ALTITUDE

	if ship == null:
		plan.error_message = "Invalid ship"
		return plan

	var ship_orbit = ship.orbit_state as OrbitState
	var parent = ship.parent_body as CelestialBody
	if ship_orbit == null or parent == null:
		plan.error_message = "Ship has no valid orbit"
		return plan

	# Use the ship's built-in Hohmann function
	var nodes = ship.plan_hohmann_to_altitude(target_altitude)
	for node in nodes:
		plan.add_maneuver(node)

	plan.description = "Hohmann to %s altitude" % OrbitalConstantsClass.format_distance(target_altitude)
	plan.is_valid = nodes.size() == 2

	return plan


# === Goal Descriptions ===

static func get_goal_name(goal: Goal) -> String:
	match goal:
		Goal.TRANSFER_TO_PLANET:
			return "Transfer to Planet"
		Goal.CIRCULARIZE_AT_AP:
			return "Circularize at Apoapsis"
		Goal.CIRCULARIZE_AT_PE:
			return "Circularize at Periapsis"
		Goal.RAISE_APOAPSIS:
			return "Raise Apoapsis"
		Goal.LOWER_APOAPSIS:
			return "Lower Apoapsis"
		Goal.RAISE_PERIAPSIS:
			return "Raise Periapsis"
		Goal.LOWER_PERIAPSIS:
			return "Lower Periapsis"
		Goal.CHANGE_ALTITUDE:
			return "Change Orbit Altitude"
		_:
			return "Unknown"


static func get_available_goals() -> Array[Goal]:
	## Get list of goals available for local orbit adjustments
	return [
		Goal.CIRCULARIZE_AT_AP,
		Goal.CIRCULARIZE_AT_PE,
		Goal.RAISE_APOAPSIS,
		Goal.LOWER_APOAPSIS,
		Goal.RAISE_PERIAPSIS,
		Goal.LOWER_PERIAPSIS,
	]


# === Immediate Transfer Planning ===

static func plan_immediate_transfer(ship: Node, target: Planet, transfer_info: Dictionary) -> ManeuverPlan:
	## Plan a transfer using pre-calculated immediate transfer info
	## transfer_info comes from TransferCalculator.calculate_immediate_transfer()
	var plan = ManeuverPlan.new()
	plan.goal = Goal.TRANSFER_TO_PLANET

	if ship == null or target == null or transfer_info.is_empty():
		plan.error_message = "Invalid ship, target, or transfer info"
		return plan

	var ship_orbit = ship.orbit_state as OrbitState
	if ship_orbit == null:
		plan.error_message = "Ship has no orbit state"
		return plan

	var departure_time = transfer_info.get("departure_time", TimeManager.simulation_time + 60.0)
	var is_patched_conic = transfer_info.get("is_patched_conic", false)

	if is_patched_conic:
		# Patched conic transfer - escape burn from planetary orbit
		var patched = transfer_info.get("patched_conic") as TransferCalculator.PatchedConicTransfer
		var escape_dv_mag = transfer_info.get("escape_dv", 0.0)

		# Get state at departure time
		var state_at_burn = ship_orbit.get_state_at_time(departure_time)
		var prograde = OrbitalMechanics.get_prograde_direction(state_at_burn.velocity)

		# Escape burn is prograde
		var escape_dv = prograde * escape_dv_mag
		var escape_node = ship.plan_maneuver(departure_time, escape_dv)
		escape_node.burn_type = "ESCAPE"
		plan.add_maneuver(escape_node)

		# Capture burn will be created on SOI entry
		var capture_dv_mag = transfer_info.get("capture_dv", 0.0)
		var arrival_time = departure_time + transfer_info.get("transfer_time", 0.0)

		var capture_node = ManeuverNode.new()
		capture_node.execution_time = arrival_time
		capture_node.burn_type = "CAPTURE"
		capture_node.is_pending_capture = true
		capture_node.target_planet = target
		capture_node.expected_dv_magnitude = capture_dv_mag
		capture_node.delta_v = Vector2.LEFT * capture_dv_mag  # Placeholder
		plan.maneuvers.append(capture_node)

		plan.total_delta_v = escape_dv_mag + capture_dv_mag
		plan.description = "Transfer to %s" % target.body_name

	else:
		# Heliocentric transfer
		var departure_dv_mag = transfer_info.get("departure_dv", 0.0)
		var arrival_dv_mag = transfer_info.get("arrival_dv", 0.0)
		var transfer_time = transfer_info.get("transfer_time", 0.0)

		# Get state at departure
		var state_at_burn = ship_orbit.get_state_at_time(departure_time)
		var prograde = OrbitalMechanics.get_prograde_direction(state_at_burn.velocity)

		# Determine direction based on inner/outer planet
		var ship_radius = ship_orbit.semi_major_axis
		var target_radius = target.orbital_radius
		var is_outward = target_radius > ship_radius

		# Departure burn
		var departure_dv = prograde * departure_dv_mag if is_outward else -prograde * departure_dv_mag
		var departure_node = ship.plan_maneuver(departure_time, departure_dv)
		plan.add_maneuver(departure_node)

		# Arrival burn
		var arrival_time = departure_time + transfer_time
		if departure_node.resulting_orbit:
			var arrival_state = departure_node.resulting_orbit.get_state_at_time(arrival_time)
			var arrival_prograde = OrbitalMechanics.get_prograde_direction(arrival_state.velocity)
			var arrival_dv = arrival_prograde * arrival_dv_mag if is_outward else -arrival_prograde * arrival_dv_mag
			var arrival_node = ship.plan_maneuver(arrival_time, arrival_dv)
			plan.add_maneuver(arrival_node)

		plan.total_delta_v = departure_dv_mag + arrival_dv_mag
		plan.description = "Transfer to %s" % target.body_name

	plan.total_time = transfer_info.get("transfer_time", 0.0)
	plan.is_valid = true

	return plan
