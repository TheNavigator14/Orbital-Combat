class_name ManeuverPanel
extends Control

## Panel showing planned maneuver nodes with countdown and execution
## CRT phosphor-green aesthetic with scanlines and glow effects

signal maneuver_executed(node: ManeuverNode)
signal maneuver_removed(node: ManeuverNode)

# === References ===
var ship: Ship = null
var planned_maneuvers: Array = []
var current_node_index: int = 0

# === CRT Effects ===
var flicker_timer: float = 0.0

# === CRT Colors ===
const CRT_GREEN = Color(0.2, 1.0, 0.4)
const CRT_GREEN_DIM = Color(0.1, 0.5, 0.2)
const CRT_GREEN_BRIGHT = Color(0.4, 1.0, 0.6)
const CRT_AMBER = Color(1.0, 0.6, 0.2)
const CRT_RED = Color(1.0, 0.3, 0.2)
const CRT_GLOW = Color(0.1, 0.5, 0.2, 0.3)

# === Node References ===
@onready var node_header: Label = $VBoxContainer/NodeHeader/NodeNumberLabel
@onready var no_maneuver_label: Label = $VBoxContainer/NoManeuverLabel
@onready var node_container: VBoxContainer = $VBoxContainer/NodeContainer
@onready var time_to_label: Label = $VBoxContainer/NodeContainer/NodeTimeContainer/TimeToLabel
@onready var burn_time_label: Label = $VBoxContainer/NodeContainer/BurnTimeContainer/BurnTimeLabel
@onready var delta_v_label: Label = $VBoxContainer/NodeContainer/DeltaVContainer/DeltaVLabel
@onready var dv_components_label: Label = $VBoxContainer/NodeContainer/DVComponentsContainer/DVComponentsLabel
@onready var result_orbit_label: Label = $VBoxContainer/NodeContainer/ResultOrbitLabel
@onready var status_label: Label = $VBoxContainer/StatusContainer/StatusLabel
@onready var execute_button: Button = $VBoxContainer/ButtonContainer/ExecuteButton
@onready var remove_button: Button = $VBoxContainer/ButtonContainer/RemoveButton
@onready var next_node_button: Button = $VBoxContainer/ButtonContainer/NextNodeButton

func _ready() -> void:
	_apply_crt_theme()
	_update_visibility()

func _apply_crt_theme() -> void:
	# Apply phosphor-green color scheme to all labels
	var all_labels = [
		node_header, no_maneuver_label, time_to_label, burn_time_label,
		delta_v_label, dv_components_label, result_orbit_label, status_label
	]
	
	for label in all_labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_constant_override("shadow_outline_size", 2)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)
	
	# Style buttons
	_style_crt_button(execute_button)
	_style_crt_button(remove_button)
	_style_crt_button(next_node_button)

func _style_crt_button(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_color_override("font_color", CRT_GREEN)
	btn.add_theme_color_override("font_hover_color", CRT_GREEN_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

func set_ship(s: Ship) -> void:
	ship = s
	if ship:
		ship.maneuver_started.connect(_on_maneuver_started)
		ship.maneuver_completed.connect(_on_maneuver_completed)

func set_maneuvers(nodes: Array) -> void:
	planned_maneuvers = nodes
	current_node_index = 0
	_update_visibility()
	_update_display()

func add_maneuver(node: ManeuverNode) -> void:
	if not planned_maneuvers.has(node):
		planned_maneuvers.append(node)
	planned_maneuvers.sort_custom(func(a, b): return a.exec_time < b.exec_time)
	_update_visibility()
	_update_display()

func remove_maneuver(node: ManeuverNode) -> void:
	planned_maneuvers.erase(node)
	if current_node_index >= planned_maneuvers.size():
		current_node_index = max(0, planned_maneuvers.size() - 1)
	_update_visibility()
	_update_display()

func clear_all_maneuvers() -> void:
	planned_maneuvers.clear()
	current_node_index = 0
	_update_visibility()

func get_current_node() -> ManeuverNode:
	if planned_maneuvers.size() > 0 and current_node_index < planned_maneuvers.size():
		return planned_maneuvers[current_node_index]
	return null

func _update_visibility() -> void:
	var has_maneuvers = planned_maneuvers.size() > 0
	no_maneuver_label.visible = not has_maneuvers
	node_container.visible = has_maneuvers
	execute_button.disabled = not has_maneuvers
	remove_button.disabled = not has_maneuvers
	
	var total_nodes = planned_maneuvers.size()
	next_node_button.text = "NEXT (%d)" % total_nodes
	next_node_button.disabled = total_nodes <= 1
	
	# Update button colors based on state
	if execute_button:
		if has_maneuvers:
			execute_button.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
		else:
			execute_button.add_theme_color_override("font_color", CRT_GREEN_DIM)

func _update_display() -> void:
	var node = get_current_node()
	
	if node == null:
		node_header.text = "[ NO MANEUVERS ]"
		time_to_label.text = "---"
		burn_time_label.text = "---"
		delta_v_label.text = "0 m/s"
		dv_components_label.text = "Pro: 0 m/s  Rad: 0 m/s"
		result_orbit_label.text = "No orbit preview"
		status_label.text = "No maneuver"
		return
	
	# Update header with CRT glow effect
	node_header.text = "[ NODE %d of %d ]" % [current_node_index + 1, planned_maneuvers.size()]
	node_header.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	
	# Calculate time until burn
	var time_until = node.get_time_until(TimeManager.simulation_time)
	
	if time_until > 0:
		time_to_label.text = "T-%s" % OrbitalConstantsClass.format_time(time_until)
		status_label.text = "Scheduled"
		status_label.add_theme_color_override("font_color", CRT_GREEN)
	else:
		time_to_label.text = ">>> BURN NOW <<<"
		time_to_label.add_theme_color_override("font_color", CRT_AMBER)
		status_label.text = "Ready to execute"
		status_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	
	# Burn duration
	var burn_dur = node.burn_duration
	if burn_dur < 60:
		burn_time_label.text = "Duration: %.1fs" % burn_dur
	else:
		burn_time_label.text = "Duration: %s" % OrbitalConstantsClass.format_time(burn_dur)
	
	# Delta-V
	var dv_mag = node.get_delta_v_magnitude()
	delta_v_label.text = OrbitalConstantsClass.format_velocity(dv_mag)
	delta_v_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	
	# Delta-V components
	var prograde = node.get_prograde_component()
	var radial = node.get_radial_component()
	dv_components_label.text = "Pro: %s  Rad: %s" % [
		OrbitalConstantsClass.format_velocity(prograde),
		OrbitalConstantsClass.format_velocity(radial)
	]
	
	# Result orbit preview
	if node.result_orbit != null:
		var orbit = node.result_orbit
		var orbit_type = "Unknown"
		if orbit.eccentricity < 0.01:
			orbit_type = "Circular"
		elif orbit.eccentricity < 0.2:
			orbit_type = "Elliptical"
		else:
			orbit_type = "Eccentric"
		
		result_orbit_label.text = "%s Orbit\nAp: %s  Pe: %s" % [
			orbit_type,
			OrbitalConstantsClass.format_distance(orbit.apoapsis),
			OrbitalConstantsClass.format_distance(orbit.periapsis)
		]
	else:
		result_orbit_label.text = "No orbit preview"

func _process(delta: float) -> void:
	_update_crt_flicker(delta)
	if planned_maneuvers.size() == 0:
		return
	_update_display()

func _on_execute_button_pressed() -> void:
	var node = get_current_node()
	if node == null or ship == null:
		return
	
	ship.execute_maneuver(node)
	maneuver_executed.emit(node)
	
	# Remove executed maneuver
	planned_maneuvers.erase(node)
	if current_node_index >= planned_maneuvers.size():
		current_node_index = max(0, planned_maneuvers.size() - 1)
	
	_update_visibility()
	_update_display()

func _on_remove_button_pressed() -> void:
	var node = get_current_node()
	if node == null:
		return
	
	maneuver_removed.emit(node)
	planned_maneuvers.erase(node)
	if current_node_index >= planned_maneuvers.size():
		current_node_index = max(0, planned_maneuvers.size() - 1)
	
	_update_visibility()
	_update_display()

func _on_next_node_button_pressed() -> void:
	if planned_maneuvers.size() <= 1:
		return
	
	current_node_index = (current_node_index + 1) % planned_maneuvers.size()
	_update_visibility()
	_update_display()

func _on_maneuver_started(node: ManeuverNode) -> void:
	status_label.text = ">>> EXECUTING BURN <<<"
	status_label.add_theme_color_override("font_color", CRT_AMBER)

func _on_maneuver_completed(node: ManeuverNode) -> void:
	status_label.text = "Maneuver complete!"
	status_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	_update_display()

func _update_crt_flicker(delta: float) -> void:
	# Subtle phosphor flicker
	flicker_timer += delta
	if flicker_timer > 0.12:
		flicker_timer = 0.0
		if randf() > 0.96:
			modulate = Color(0.90, 0.90, 0.90, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)