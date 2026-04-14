class_name ManeuverNode
extends Resource
## Represents a planned velocity change (maneuver) at a specific time

signal node_modified()

# === Maneuver Definition ===
@export var execution_time: float = 0.0  # Simulation time to execute (seconds)
@export var delta_v: Vector2 = Vector2.ZERO  # Velocity change in world coordinates (m/s)

# === Burn Type (for patched conic transfers) ===
var burn_type: String = "NORMAL"  # NORMAL, ESCAPE, CAPTURE, MIDCOURSE

# === Pending Capture Burn (activates on SOI entry) ===
var is_pending_capture: bool = false
var target_planet: Planet = null
var expected_dv_magnitude: float = 0.0  # For display before actual direction is known

# === Calculated Values ===
var burn_duration: float = 0.0  # Estimated burn time (seconds)
var resulting_orbit: OrbitState = null  # Predicted orbit after maneuver

# === Orbital Frame at Execution ===
var prograde: Vector2 = Vector2.RIGHT
var radial_out: Vector2 = Vector2.UP


func calculate_for_ship(ship) -> void:
	## Calculate burn parameters based on ship stats
	## ship should have: max_thrust, total_mass, exhaust_velocity

	# Calculate burn duration (assuming constant mass for simplicity)
	# More accurate would account for mass loss during burn
	var acceleration = ship.max_thrust / ship.total_mass
	burn_duration = delta_v.length() / acceleration

	# Get orbital frame at execution time
	if ship.orbit_state:
		var state = ship.orbit_state.get_state_at_time(execution_time)
		prograde = OrbitalMechanics.get_prograde_direction(state.velocity)
		radial_out = OrbitalMechanics.get_radial_direction(state.position)

		# Calculate resulting orbit
		var new_velocity = state.velocity + delta_v
		resulting_orbit = OrbitState.create_from_state_vectors(
			state.position,
			new_velocity,
			ship.parent_body.mu,
			execution_time
		)


func get_delta_v_magnitude() -> float:
	## Get total delta-v magnitude
	return delta_v.length()


func get_prograde_component() -> float:
	## Get delta-v in prograde direction
	return delta_v.dot(prograde)


func get_radial_component() -> float:
	## Get delta-v in radial direction
	return delta_v.dot(radial_out)


func set_from_components(prograde_dv: float, radial_dv: float) -> void:
	## Set delta-v from prograde and radial components
	delta_v = prograde * prograde_dv + radial_out * radial_dv
	node_modified.emit()


func adjust_prograde(amount: float) -> void:
	## Adjust prograde component
	delta_v += prograde * amount
	node_modified.emit()


func adjust_radial(amount: float) -> void:
	## Adjust radial component
	delta_v += radial_out * amount
	node_modified.emit()


func get_time_until(current_time: float) -> float:
	## Get time until this maneuver
	return execution_time - current_time


func is_past(current_time: float) -> bool:
	## Check if maneuver time has passed
	return current_time > execution_time


func get_info_string() -> String:
	var type_label = ""
	match burn_type:
		"ESCAPE":
			type_label = "[ESCAPE]\n"
		"CAPTURE":
			type_label = "[CAPTURE]\n"
		"MIDCOURSE":
			type_label = "[MIDCOURSE]\n"

	var dv_value = delta_v.length()
	if is_pending_capture and expected_dv_magnitude > 0:
		dv_value = expected_dv_magnitude

	return "%sT%s\nDelta-v: %s\nBurn: %.1f s" % [
		type_label,
		OrbitalConstantsClass.format_time(execution_time - TimeManager.simulation_time),
		OrbitalConstantsClass.format_velocity(dv_value),
		burn_duration
	]
