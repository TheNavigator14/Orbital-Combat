class_name ManeuverPlanningPanel
extends Control
## Panel for planning and executing orbital maneuvers

signal maneuver_planned(node: ManeuverNode)
signal maneuver_executed(node: ManeuverNode)
signal maneuver_cancelled(node: ManeuverNode)

# === References ===
var ship: Ship = null
var tactical_display: Control = null

# === Current Maneuver ===
var current_node: ManeuverNode = null
var is_planned: bool = false
var countdown_active: bool = false
var time_until_burn: float = 0.0

# === Node References ===
@onready var burn_time_input: SpinBox = $VBoxContainer/BurnTimeContainer/BurnTimeInput
@onready var delta_v_input: SpinBox = $VBoxContainer/DeltaVContainer/DeltaVInput
@onready var direction_button: OptionButton = $VBoxContainer/DirectionContainer/DirectionButton
@onready var preview_label: Label = $VBoxContainer/PreviewLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var plan_button: Button = $VBoxContainer/PlanButton
@onready var execute_button: Button = $VBoxContainer/ExecuteButton
@onready var cancel_button: Button = $VBoxContainer/CancelButton

# === Direction Constants ===
enum Direction { PROGRADE, RETROGRADE, RADIAL_OUT, RADIAL_IN, NORMAL, ANTI_NORMAL }
var direction_names = ["Prograde", "Retrograde", "Radial Out", "Radial In", "Normal", "Anti-Normal"]

func _ready() -> void:
	_setup_direction_options()
	_reset_inputs()
	_update_button_states()

func _setup_direction_options() -> void:
	direction_button.clear()
	for dir_name in direction_names:
		direction_button.add_item(dir_name)
	direction_button.selected = Direction.PROGRADE

func _reset_inputs() -> void:
	burn_time_input.value = 60.0
	delta_v_input.value = 100.0
	preview_label.text = ""
	status_label.text = "Ready"
	is_planned = false
	current_node = null
	countdown_active = false
	time_until_burn = 0.0

func _update_button_states() -> void:
	execute_button.disabled = not is_planned
	cancel_button.disabled = not is_planned

func set_ship(s: Ship) -> void:
	ship = s
	if ship:
		status_label.text = "Ship: %s" % ship.ship_name
	else:
		status_label.text = "No ship"

func set_tactical_display(display: Control) -> void:
	tactical_display = display

# === Input Handlers ===

func _on_burn_time_input_value_changed(value: float) -> void:
	_update_preview()

func _on_delta_v_input_value_changed(value: float) -> void:
	_update_preview()

func _on_direction_button_item_selected(index: int) -> void:
	_update_preview()

func _on_plan_button_pressed() -> void:
	if ship == null:
		status_label.text = "Error: No ship"
		return
	
	_plan_maneuver()
	_update_button_states()

func _on_execute_button_pressed() -> void:
	if current_node == null or ship == null:
		return
	
	# Execute immediately
	ship.execute_maneuver(current_node)
	maneuver_executed.emit(current_node)
	
	status_label.text = "Executing maneuver!"
	_clear_planned_maneuver()

func _on_cancel_button_pressed() -> void:
	if current_node:
		maneuver_cancelled.emit(current_node)
	
	_clear_planned_maneuver()
	status_label.text = "Maneuver cancelled"

func _clear_planned_maneuver() -> void:
	current_node = null
	is_planned = false
	countdown_active = false
	burn_time_input.editable = true
	delta_v_input.editable = true
	direction_button.disabled = false
	plan_button.disabled = false
	plan_button.text = "PLAN MANEUVER"
	_update_button_states()
	_update_preview()

# === Maneuver Planning ===

func _plan_maneuver() -> void:
	if ship == null or ship.orbit_state == null:
		status_label.text = "Error: No valid orbit"
		return
	
	var burn_time: float = burn_time_input.value
	var dv_magnitude: float = delta_v_input.value
	var direction: int = direction_button.selected
	
	# Calculate execution time (from now)
	var execution_time = TimeManager.simulation_time + burn_time
	
	# Get direction vector
	var dv_vector = _calculate_direction_vector(direction, dv_magnitude)
	
	# Create maneuver node
	current_node = ManeuverNode.new()
	current_node.execution_time = execution_time
	current_node.delta_v = dv_vector
	
	# Calculate burn parameters
	current_node.calculate_for_ship(ship)
	
	is_planned = true
	plan_button.text = "PLANNED"
	
	# Show preview info
	_preview_result()
	
	# Emit signal
	maneuver_planned.emit(current_node)
	
	status_label.text = "Maneuver planned for T+%s" % OrbitalConstantsClass.format_time(burn_time)

func _calculate_direction_vector(direction: int, magnitude: float) -> Vector2:
	if ship == null or ship.orbit_state == null:
		return Vector2.RIGHT * magnitude
	
	var prograde = ship.orbit_state.get_prograde()
	var radial = ship.orbit_state.get_radial_out()
	
	match direction:
		Direction.PROGRADE:
			return prograde * magnitude
		Direction.RETROGRADE:
			return -prograde * magnitude
		Direction.RADIAL_OUT:
			return radial * magnitude
		Direction.RADIAL_IN:
			return -radial * magnitude
		Direction.NORMAL:
			return ship.orbit_state.get_normal() * magnitude
		Direction.ANTI_NORMAL:
			return -ship.orbit_state.get_normal() * magnitude
	
	return prograde * magnitude

func _get_direction_name(direction: int) -> String:
	if direction >= 0 and direction < direction_names.size():
		return direction_names[direction]
	return "Unknown"

# === Preview ===

func _update_preview() -> void:
	if not is_planned:
		preview_label.text = ""
		return
	
	_preview_result()

func _preview_result() -> void:
	if current_node == null or current_node.resulting_orbit == null:
		preview_label.text = ""
		return
	
	var orbit = current_node.resulting_orbit
	var orbit_type = "Unknown"
	
	if orbit.eccentricity < 0.01:
		orbit_type = "Circular"
	elif orbit.eccentricity < 0.2:
		orbit_type = "Elliptical"
	else:
		orbit_type = "Highly Eccentric"
	
	var preview_text = "Result: %s Orbit\nAp: %s  Pe: %s\nPeriod: %s" % [
		orbit_type,
		OrbitalConstantsClass.format_distance(orbit.apoapsis),
		OrbitalConstantsClass.format_distance(orbit.periapsis),
		OrbitalConstantsClass.format_time(orbit.orbital_period)
	]
	
	preview_label.text = preview_text

# === Countdown & Auto-Execute ===

func _process(delta: float) -> void:
	if not is_planned or current_node == null:
		return
	
	# Update time until burn
	time_until_burn = current_node.get_time_until(TimeManager.simulation_time)
	
	# Update countdown display
	if time_until_burn > 0:
		status_label.text = "T-%s until burn" % OrbitalConstantsClass.format_time(time_until_burn)
	else:
		status_label.text = "BURN TIME!"
	
	# Auto-execute when burn time arrives (if enabled)
	if countdown_active and time_until_burn <= 0 and ship:
		_execute_burn()

func start_countdown() -> void:
	"""Enable auto-execution when burn time arrives"""
	countdown_active = true
	burn_time_input.editable = false
	delta_v_input.editable = false
	direction_button.disabled = true
	plan_button.disabled = true

func stop_countdown() -> void:
	"""Disable auto-execution"""
	countdown_active = false

func _execute_burn() -> void:
	if current_node == null or ship == null:
		_clear_planned_maneuver()
		return
	
	# Give a short burn (use 10% of planned duration for visual feedback)
	var burn_duration = min(5.0, current_node.burn_duration * 0.1)
	
	ship.start_thrust(Ship.ThrustDirection.MANUAL, current_node.delta_v.normalized(), 1.0)
	
	# Stop after short burn
	await get_tree().create_timer(burn_duration).timeout
	ship.stop_thrust()
	
	# For demo: complete the maneuver after visual feedback
	_complete_maneuver()

func _complete_maneuver() -> void:
	if current_node:
		maneuver_executed.emit(current_node)
		status_label.text = "Maneuver complete!"
	
	_clear_planned_maneuver()

# === External Interface ===

func load_maneuver(node: ManeuverNode) -> void:
	"""Load an existing maneuver node for editing"""
	if node == null:
		return
	
	current_node = node
	is_planned = true
	
	# Update UI to reflect loaded maneuver
	burn_time_input.value = node.get_time_until(TimeManager.simulation_time)
	delta_v_input.value = node.get_delta_v_magnitude()
	
	# Determine direction
	var prograde_dv = node.get_prograde_component()
	var radial_dv = node.get_radial_component()
	
	if absf(prograde_dv) >= absf(radial_dv):
		if prograde_dv >= 0:
			direction_button.selected = Direction.PROGRADE
		else:
			direction_button.selected = Direction.RETROGRADE
	else:
		if radial_dv >= 0:
			direction_button.selected = Direction.RADIAL_OUT
		else:
			direction_button.selected = Direction.RADIAL_IN
	
	_update_preview()
	_update_button_states()
	plan_button.text = "PLANNED"

func clear_maneuver() -> void:
	"""Clear current maneuver plan"""
	_clear_planned_maneuver()
	_reset_inputs()

# === Utility ===

func has_active_maneuver() -> bool:
	return is_planned and current_node != null

func get_current_maneuver() -> ManeuverNode:
	return current_node