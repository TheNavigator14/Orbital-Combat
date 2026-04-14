class_name ManeuverRenderer
extends RefCounted
## Renders maneuver nodes and predicted trajectories on the tactical display

# === Visual Settings ===
const MANEUVER_NODE_COLOR := Color(1.0, 0.8, 0.0, 1.0)  # Gold/Yellow
const MANEUVER_SELECTED_COLOR := Color(1.0, 1.0, 0.0, 1.0)  # Bright yellow
const PREDICTED_ORBIT_COLOR := Color(0.8, 0.6, 0.0, 0.6)  # Amber
const HANDLE_PROGRADE_COLOR := Color(0.0, 1.0, 0.4, 1.0)  # Green
const HANDLE_RADIAL_COLOR := Color(0.0, 0.8, 1.0, 1.0)  # Cyan
const DELTA_V_ARROW_COLOR := Color(1.0, 0.7, 0.0, 0.9)  # Orange

const NODE_SIZE := 8.0  # Diamond marker size
const HANDLE_RADIUS := 6.0  # Drag handle radius
const HANDLE_LINE_LENGTH := 40.0  # Distance to handles
const ARROW_HEAD_SIZE := 8.0  # Delta-v arrow head size

# === State ===
var selected_maneuver: ManeuverNode = null
var hovered_maneuver: ManeuverNode = null
var scale_converter: ScaleConverter = null


func set_scale_converter(converter: ScaleConverter) -> void:
	scale_converter = converter


func set_selected(node: ManeuverNode) -> void:
	selected_maneuver = node


func set_hovered(node: ManeuverNode) -> void:
	hovered_maneuver = node


# === Main Draw Function ===

func draw_maneuvers(canvas: CanvasItem, ship: Ship) -> void:
	## Draw all planned maneuvers for a ship
	if ship == null or scale_converter == null:
		return

	for maneuver in ship.planned_maneuvers:
		_draw_maneuver_node(canvas, ship, maneuver)

		# Draw predicted orbit for selected maneuver
		if maneuver == selected_maneuver and maneuver.resulting_orbit:
			_draw_predicted_orbit(canvas, ship, maneuver)


# === Individual Drawing Functions ===

func _draw_maneuver_node(canvas: CanvasItem, ship: Ship, maneuver: ManeuverNode) -> void:
	## Draw a single maneuver node marker
	var screen_pos = _get_maneuver_screen_position(ship, maneuver)
	if screen_pos == null:
		return

	# Determine color based on selection state
	var color = MANEUVER_NODE_COLOR
	if maneuver == selected_maneuver:
		color = MANEUVER_SELECTED_COLOR
	elif maneuver == hovered_maneuver:
		color = color.lightened(0.3)

	# Draw diamond marker
	_draw_diamond(canvas, screen_pos, NODE_SIZE, color)

	# Draw delta-v arrow
	if maneuver.delta_v.length() > 0.1:
		_draw_delta_v_arrow(canvas, screen_pos, maneuver)

	# Draw time label
	_draw_time_label(canvas, screen_pos, maneuver)

	# Draw handles if selected
	if maneuver == selected_maneuver:
		_draw_handles(canvas, screen_pos, maneuver)


func _draw_diamond(canvas: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	## Draw a diamond/rhombus shape
	var points = PackedVector2Array([
		center + Vector2(0, -size),      # Top
		center + Vector2(size, 0),       # Right
		center + Vector2(0, size),       # Bottom
		center + Vector2(-size, 0)       # Left
	])
	canvas.draw_colored_polygon(points, color)
	canvas.draw_polyline(points, color.darkened(0.3), 1.5)
	# Close the shape
	canvas.draw_line(points[3], points[0], color.darkened(0.3), 1.5)


func _draw_delta_v_arrow(canvas: CanvasItem, screen_pos: Vector2, maneuver: ManeuverNode) -> void:
	## Draw an arrow showing the delta-v direction and magnitude
	var dv_magnitude = maneuver.delta_v.length()
	if dv_magnitude < 1.0:
		return

	# Arrow length proportional to delta-v (capped)
	var arrow_length = clampf(dv_magnitude / 50.0, 15.0, 60.0)

	# Direction in screen space (use world direction)
	var dv_dir = maneuver.delta_v.normalized()
	var arrow_end = screen_pos + dv_dir * arrow_length

	# Draw arrow line
	canvas.draw_line(screen_pos, arrow_end, DELTA_V_ARROW_COLOR, 2.0)

	# Draw arrow head
	var head_dir = dv_dir
	var perpendicular = Vector2(-head_dir.y, head_dir.x)
	var head_points = PackedVector2Array([
		arrow_end,
		arrow_end - head_dir * ARROW_HEAD_SIZE + perpendicular * ARROW_HEAD_SIZE * 0.5,
		arrow_end - head_dir * ARROW_HEAD_SIZE - perpendicular * ARROW_HEAD_SIZE * 0.5
	])
	canvas.draw_colored_polygon(head_points, DELTA_V_ARROW_COLOR)


func _draw_time_label(canvas: CanvasItem, screen_pos: Vector2, maneuver: ManeuverNode) -> void:
	## Draw time until maneuver label
	var time_until = maneuver.get_time_until(TimeManager.simulation_time)
	var label: String

	if time_until < 0:
		label = "PAST"
	else:
		label = "T-" + OrbitalConstantsClass.format_time(time_until)

	var label_pos = screen_pos + Vector2(-30, -NODE_SIZE - 15)
	canvas.draw_string(ThemeDB.fallback_font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 60, 10, MANEUVER_NODE_COLOR)


func _draw_handles(canvas: CanvasItem, screen_pos: Vector2, maneuver: ManeuverNode) -> void:
	## Draw drag handles for adjusting delta-v
	# Prograde handle
	var prograde_pos = screen_pos + maneuver.prograde * HANDLE_LINE_LENGTH
	canvas.draw_line(screen_pos, prograde_pos, HANDLE_PROGRADE_COLOR.darkened(0.3), 1.5)
	canvas.draw_circle(prograde_pos, HANDLE_RADIUS, HANDLE_PROGRADE_COLOR)

	# Retrograde handle
	var retrograde_pos = screen_pos - maneuver.prograde * HANDLE_LINE_LENGTH
	canvas.draw_line(screen_pos, retrograde_pos, HANDLE_PROGRADE_COLOR.darkened(0.5), 1.5)
	canvas.draw_circle(retrograde_pos, HANDLE_RADIUS * 0.7, HANDLE_PROGRADE_COLOR.darkened(0.3))

	# Radial out handle
	var radial_pos = screen_pos + maneuver.radial_out * HANDLE_LINE_LENGTH
	canvas.draw_line(screen_pos, radial_pos, HANDLE_RADIAL_COLOR.darkened(0.3), 1.5)
	canvas.draw_circle(radial_pos, HANDLE_RADIUS, HANDLE_RADIAL_COLOR)

	# Radial in handle
	var radial_in_pos = screen_pos - maneuver.radial_out * HANDLE_LINE_LENGTH
	canvas.draw_line(screen_pos, radial_in_pos, HANDLE_RADIAL_COLOR.darkened(0.5), 1.5)
	canvas.draw_circle(radial_in_pos, HANDLE_RADIUS * 0.7, HANDLE_RADIAL_COLOR.darkened(0.3))


func _draw_predicted_orbit(canvas: CanvasItem, ship: Ship, maneuver: ManeuverNode) -> void:
	## Draw the predicted orbit after a maneuver
	if maneuver.resulting_orbit == null or ship.parent_body == null:
		return

	var points = maneuver.resulting_orbit.sample_orbit_points(100)
	var screen_points = PackedVector2Array()

	for point in points:
		var world_pos = point + ship.parent_body.world_position
		var screen_pos = scale_converter.world_to_screen(world_pos)
		screen_points.append(screen_pos)

	if screen_points.size() > 1:
		# For elliptical orbits, close the path
		if maneuver.resulting_orbit.eccentricity < 1.0:
			screen_points.append(screen_points[0])

		# Draw as dashed line
		_draw_dashed_polyline(canvas, screen_points, PREDICTED_ORBIT_COLOR, 1.5, 8.0, 4.0)

	# Draw predicted apsides
	_draw_predicted_apsides(canvas, ship, maneuver)


func _draw_predicted_apsides(canvas: CanvasItem, ship: Ship, maneuver: ManeuverNode) -> void:
	## Draw apoapsis and periapsis markers for predicted orbit
	var orbit = maneuver.resulting_orbit
	if orbit == null:
		return

	# Periapsis
	var pe_angle = orbit.argument_of_periapsis
	var pe_radius = orbit.periapsis
	var pe_world = Vector2(pe_radius * cos(pe_angle), pe_radius * sin(pe_angle)) + ship.parent_body.world_position
	var pe_screen = scale_converter.world_to_screen(pe_world)

	canvas.draw_circle(pe_screen, 3, Color.CYAN.darkened(0.3))
	canvas.draw_string(ThemeDB.fallback_font, pe_screen + Vector2(5, 3), "Pe'", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.CYAN.darkened(0.3))

	# Apoapsis (only for elliptical)
	if orbit.eccentricity < 1.0:
		var ap_angle = orbit.argument_of_periapsis + PI
		var ap_radius = orbit.apoapsis
		var ap_world = Vector2(ap_radius * cos(ap_angle), ap_radius * sin(ap_angle)) + ship.parent_body.world_position
		var ap_screen = scale_converter.world_to_screen(ap_world)

		canvas.draw_circle(ap_screen, 3, Color.ORANGE.darkened(0.3))
		canvas.draw_string(ThemeDB.fallback_font, ap_screen + Vector2(5, 3), "Ap'", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.ORANGE.darkened(0.3))


func _draw_dashed_polyline(canvas: CanvasItem, points: PackedVector2Array, color: Color,
		width: float = 1.0, dash_length: float = 10.0, gap_length: float = 5.0) -> void:
	## Draw a dashed polyline
	if points.size() < 2:
		return

	var total_segment = dash_length + gap_length
	var accumulated_length = 0.0
	var in_dash = true

	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i + 1]
		var segment_length = p1.distance_to(p2)
		var segment_dir = (p2 - p1).normalized()

		var pos_in_segment = 0.0

		while pos_in_segment < segment_length:
			var remaining_in_state: float
			if in_dash:
				remaining_in_state = dash_length - fmod(accumulated_length, total_segment)
			else:
				remaining_in_state = gap_length - fmod(accumulated_length - dash_length, total_segment)
				if remaining_in_state < 0:
					remaining_in_state += gap_length

			var draw_length = minf(remaining_in_state, segment_length - pos_in_segment)

			if in_dash:
				var start_pos = p1 + segment_dir * pos_in_segment
				var end_pos = p1 + segment_dir * (pos_in_segment + draw_length)
				canvas.draw_line(start_pos, end_pos, color, width)

			pos_in_segment += draw_length
			accumulated_length += draw_length

			# Check if we need to switch states
			if in_dash and fmod(accumulated_length, total_segment) >= dash_length:
				in_dash = false
			elif not in_dash and fmod(accumulated_length, total_segment) < dash_length:
				in_dash = true


# === Hit Testing ===

func get_maneuver_at_position(ship: Ship, screen_pos: Vector2, threshold: float = 15.0) -> ManeuverNode:
	## Check if a screen position is near a maneuver node
	if ship == null or scale_converter == null:
		return null

	for maneuver in ship.planned_maneuvers:
		var node_screen = _get_maneuver_screen_position(ship, maneuver)
		if node_screen == null:
			continue

		if screen_pos.distance_to(node_screen) < threshold:
			return maneuver

	return null


func get_handle_at_position(ship: Ship, maneuver: ManeuverNode, screen_pos: Vector2,
		threshold: float = 10.0) -> String:
	## Check if screen position is on a handle, returns handle type or empty string
	if maneuver == null or scale_converter == null:
		return ""

	var node_screen = _get_maneuver_screen_position(ship, maneuver)
	if node_screen == null:
		return ""

	var prograde_pos = node_screen + maneuver.prograde * HANDLE_LINE_LENGTH
	var retrograde_pos = node_screen - maneuver.prograde * HANDLE_LINE_LENGTH
	var radial_pos = node_screen + maneuver.radial_out * HANDLE_LINE_LENGTH
	var radial_in_pos = node_screen - maneuver.radial_out * HANDLE_LINE_LENGTH

	if screen_pos.distance_to(prograde_pos) < threshold:
		return "prograde"
	elif screen_pos.distance_to(retrograde_pos) < threshold:
		return "retrograde"
	elif screen_pos.distance_to(radial_pos) < threshold:
		return "radial_out"
	elif screen_pos.distance_to(radial_in_pos) < threshold:
		return "radial_in"

	return ""


# === Utility Functions ===

func _get_maneuver_screen_position(ship: Ship, maneuver: ManeuverNode) -> Variant:
	## Get the screen position of a maneuver node
	if ship.orbit_state == null or ship.parent_body == null:
		return null

	# Get orbital position at execution time
	var state = ship.orbit_state.get_state_at_time(maneuver.execution_time)
	var world_pos = state.position + ship.parent_body.world_position

	return scale_converter.world_to_screen(world_pos)


func get_maneuver_world_position(ship: Ship, maneuver: ManeuverNode) -> Vector2:
	## Get the world position of a maneuver node
	if ship.orbit_state == null or ship.parent_body == null:
		return Vector2.ZERO

	var state = ship.orbit_state.get_state_at_time(maneuver.execution_time)
	return state.position + ship.parent_body.world_position
