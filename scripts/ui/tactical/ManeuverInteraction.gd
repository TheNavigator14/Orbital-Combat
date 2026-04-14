class_name ManeuverInteraction
extends RefCounted
## Handles interactive editing of maneuver nodes (drag handles, selection)

signal maneuver_selected(maneuver: ManeuverNode)
signal maneuver_deselected()
signal maneuver_modified(maneuver: ManeuverNode)

# === Settings ===
const CLICK_THRESHOLD := 15.0  # Pixels for click detection
const HANDLE_THRESHOLD := 12.0  # Pixels for handle detection
const DV_SENSITIVITY := 5.0  # Delta-v per pixel of drag (at zoom 1.0)

# === State ===
enum DragState { NONE, DRAGGING_HANDLE }

var drag_state: DragState = DragState.NONE
var dragged_handle: String = ""  # "prograde", "retrograde", "radial_out", "radial_in"
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_dv: Vector2 = Vector2.ZERO

var selected_maneuver: ManeuverNode = null
var hovered_maneuver: ManeuverNode = null

# === References ===
var ship: Ship = null
var scale_converter: ScaleConverter = null
var maneuver_renderer: ManeuverRenderer = null


func setup(p_ship: Ship, p_converter: ScaleConverter, p_renderer: ManeuverRenderer) -> void:
	ship = p_ship
	scale_converter = p_converter
	maneuver_renderer = p_renderer


func set_ship(p_ship: Ship) -> void:
	ship = p_ship


# === Input Handling ===

func handle_mouse_button(event: InputEventMouseButton) -> bool:
	## Handle mouse button events. Returns true if event was consumed.
	if ship == null or maneuver_renderer == null:
		return false

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _on_mouse_down(event.position)
		else:
			return _on_mouse_up(event.position)

	return false


func handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	## Handle mouse motion events. Returns true if event was consumed.
	if ship == null or maneuver_renderer == null:
		return false

	# Update hover state
	_update_hover(event.position)

	# Handle drag
	if drag_state == DragState.DRAGGING_HANDLE:
		_on_drag(event.position)
		return true

	return false


func _on_mouse_down(pos: Vector2) -> bool:
	## Handle mouse button down
	# Check if clicking on a handle of the selected maneuver
	if selected_maneuver != null:
		var handle = maneuver_renderer.get_handle_at_position(ship, selected_maneuver, pos, HANDLE_THRESHOLD)
		if handle != "":
			_start_handle_drag(handle, pos)
			return true

	# Check if clicking on a maneuver node
	var clicked = maneuver_renderer.get_maneuver_at_position(ship, pos, CLICK_THRESHOLD)
	if clicked != null:
		select_maneuver(clicked)
		return true

	# Clicked elsewhere - deselect
	if selected_maneuver != null:
		deselect_maneuver()
		return true

	return false


func _on_mouse_up(_pos: Vector2) -> bool:
	## Handle mouse button up
	if drag_state == DragState.DRAGGING_HANDLE:
		_end_handle_drag()
		return true

	return false


func _on_drag(pos: Vector2) -> void:
	## Handle drag motion
	if drag_state != DragState.DRAGGING_HANDLE or selected_maneuver == null:
		return

	var drag_delta = pos - drag_start_pos

	# Calculate delta-v change based on drag
	# Scale sensitivity by zoom level (more zoom = finer control)
	var sensitivity = DV_SENSITIVITY / maxf(scale_converter.zoom_level, 0.001)

	var dv_change: float = 0.0

	match dragged_handle:
		"prograde":
			# Drag along prograde direction
			dv_change = drag_delta.dot(selected_maneuver.prograde) * sensitivity
			selected_maneuver.delta_v = drag_start_dv + selected_maneuver.prograde * dv_change

		"retrograde":
			# Drag along retrograde direction
			dv_change = -drag_delta.dot(selected_maneuver.prograde) * sensitivity
			selected_maneuver.delta_v = drag_start_dv - selected_maneuver.prograde * dv_change

		"radial_out":
			# Drag along radial out direction
			dv_change = drag_delta.dot(selected_maneuver.radial_out) * sensitivity
			selected_maneuver.delta_v = drag_start_dv + selected_maneuver.radial_out * dv_change

		"radial_in":
			# Drag along radial in direction
			dv_change = -drag_delta.dot(selected_maneuver.radial_out) * sensitivity
			selected_maneuver.delta_v = drag_start_dv - selected_maneuver.radial_out * dv_change

	# Recalculate the maneuver
	selected_maneuver.calculate_for_ship(ship)
	maneuver_modified.emit(selected_maneuver)


func _update_hover(pos: Vector2) -> void:
	## Update hover state
	var new_hover = maneuver_renderer.get_maneuver_at_position(ship, pos, CLICK_THRESHOLD)

	if new_hover != hovered_maneuver:
		hovered_maneuver = new_hover
		maneuver_renderer.set_hovered(hovered_maneuver)


# === Drag Handling ===

func _start_handle_drag(handle: String, pos: Vector2) -> void:
	drag_state = DragState.DRAGGING_HANDLE
	dragged_handle = handle
	drag_start_pos = pos
	drag_start_dv = selected_maneuver.delta_v


func _end_handle_drag() -> void:
	drag_state = DragState.NONE
	dragged_handle = ""


# === Selection ===

func select_maneuver(maneuver: ManeuverNode) -> void:
	selected_maneuver = maneuver
	maneuver_renderer.set_selected(selected_maneuver)
	maneuver_selected.emit(selected_maneuver)


func deselect_maneuver() -> void:
	selected_maneuver = null
	maneuver_renderer.set_selected(null)
	maneuver_deselected.emit()


func get_selected_maneuver() -> ManeuverNode:
	return selected_maneuver


# === Maneuver Info ===

func get_selected_maneuver_info() -> Dictionary:
	## Get information about the selected maneuver for display
	if selected_maneuver == null:
		return {}

	var time_until = selected_maneuver.get_time_until(TimeManager.simulation_time)

	return {
		"execution_time": selected_maneuver.execution_time,
		"time_until": time_until,
		"delta_v_magnitude": selected_maneuver.get_delta_v_magnitude(),
		"prograde_component": selected_maneuver.get_prograde_component(),
		"radial_component": selected_maneuver.get_radial_component(),
		"burn_duration": selected_maneuver.burn_duration,
		"resulting_orbit": selected_maneuver.resulting_orbit
	}


func delete_selected_maneuver() -> void:
	## Delete the currently selected maneuver
	if selected_maneuver != null and ship != null:
		ship.remove_maneuver(selected_maneuver)
		deselect_maneuver()


func warp_to_selected_maneuver() -> void:
	## Warp to the selected maneuver's execution time
	if selected_maneuver == null:
		return

	var target_time = selected_maneuver.execution_time - 60.0  # Stop 60 seconds before
	if target_time > TimeManager.simulation_time:
		TimeManager.warp_to_time(target_time, TimeManager.WarpLevel.REAL_TIME)
