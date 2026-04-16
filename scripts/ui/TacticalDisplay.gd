class_name TacticalDisplay
extends Control
## Orbital map tactical display with maneuver visualization and drag handles

signal maneuver_node_selected(node: ManeuverNode)
signal maneuver_node_updated(node: ManeuverNode)

# === References ===
@export var ship: Ship = null

# === Visual Settings ===
@export var orbit_line_color: Color = Color(0.2, 0.8, 0.2, 0.8)
@export var orbit_fill_color: Color = Color(0.2, 0.8, 0.2, 0.1)
@export var maneuver_color: Color = Color(1.0, 0.8, 0.2, 1.0)
@export var handle_color: Color = Color(1.0, 0.4, 0.2, 1.0)
@export var handle_hover_color: Color = Color(1.0, 0.8, 0.2, 1.0)
@export var handle_selected_color: Color = Color(0.2, 1.0, 0.4, 1.0)
@export var trajectory_color: Color = Color(0.4, 0.6, 1.0, 0.9)
@export var ship_color: Color = Color.GREEN
@export var grid_color: Color = Color(0.15, 0.15, 0.15, 0.5)
@export var body_label_color: Color = Color(0.7, 0.7, 0.7, 1.0)
@export var ship_label_color: Color = Color.GREEN

# === Scale Settings ===
@export var min_zoom: float = 0.00000005  # Show entire solar system
@export var max_zoom: float = 0.0001      # Street-level view
@export var zoom_speed: float = 1.15
@export var initial_zoom: float = 0.00001

# === State ===
var current_zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var celestial_bodies: Array = []
var projected_bodies: Array = []
var player_ship: Ship = null

# === Maneuver Handles ===
var maneuvers: Array = []  # Array of ManeuverNode
var selected_maneuver: ManeuverNode = null
var hovered_handle: ManeuverNode = null
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_maneuver_original_dv: Vector2 = Vector2.ZERO

# === Trajectory Preview ===
var show_trajectory_preview: bool = true
var preview_future_seconds: float = 86400.0 * 7  # 1 week

# === Coordinate Conversion ===
var scale_converter: ScaleConverter = null

# === Sensor Contacts ===
var sensor_manager: SensorManager = null
var show_contact_markers: bool = true
var contact_marker_size: float = 8.0  # pixels
var contact_labels: Dictionary = {}  # contact_id -> Label

# === Thermal Contact Markers ===
var thermal_contact_colors: Dictionary = {
	0.0: Color(0.3, 0.3, 0.3),   # Cold - dim gray
	0.2: Color(0.5, 0.3, 0.2),   # Cool - warm gray
	0.5: Color(1.0, 0.5, 0.1),   # Warm - amber
	0.8: Color(1.0, 0.2, 0.1),   # Hot - red
	1.0: Color(1.0, 1.0, 0.5)    # Very hot - yellow-white
}

# === Radar System ===
var radar_mode_active: bool = false
var radar_sweep_angle: float = 0.0
var radar_sweep_speed: float = 2.0  # radians per second
var radar_range_display: float = 1000000.0  # 1 Mm default
var locked_contact_id: String = ""
var show_radar_sweep: bool = true
var radar_sweep_color: Color = Color(1.0, 0.6, 0.2, 0.15)  # Amber arc
var radar_range_color: Color = Color(1.0, 0.6, 0.2, 0.4)   # Amber range rings
var lock_acquired: bool = false
var lock_progress: float = 0.0
var lock_duration: float = 2.0  # seconds to acquire lock

func _ready() -> void:
	scale_converter = ScaleConverter.new()
	custom_minimum_size = Vector2(800, 600)
	_current_zoom_changed()


func set_celestial_bodies(bodies: Array) -> void:
	celestial_bodies = bodies
	queue_redraw()


func set_player_ship(ship: Ship) -> void:
	player_ship = ship
	if player_ship:
		center_on_position(player_ship.world_position)
	queue_redraw()


func set_maneuvers(nodes: Array) -> void:
	maneuvers = nodes
	queue_redraw()


func set_sensor_manager(manager: SensorManager) -> void:
	sensor_manager = manager
	_update_contact_labels()
	queue_redraw()


func _update_contact_labels() -> void:
	# Remove old labels
	for label in contact_labels.values():
		if is_instance_valid(label):
			label.queue_free()
	contact_labels.clear()
	
	if sensor_manager == null:
		return
	
	# Create labels for detected contacts
	var contacts = sensor_manager.get_all_detected_contacts()
	for contact in contacts:
		_create_contact_label(contact)


func _create_contact_label(contact: SensorContact) -> void:
	var label = Label.new()
	label.text = contact.get_display_name()
	label.add_theme_font_size_override("font_size", 10)
	
	# Color based on thermal signal strength
	var signal_color = _get_contact_color(contact.thermal_signal_strength)
	label.add_theme_color_override("font_color", signal_color)
	
	add_child(label)
	contact_labels[contact.contact_id] = label


func _get_contact_color(signal_strength: float) -> Color:
	if signal_strength > 0.7:
		return Color(1.0, 0.3, 0.2, 1.0)  # Bright red - strong signal
	elif signal_strength > 0.4:
		return Color(1.0, 0.6, 0.2, 1.0)  # Amber - moderate
	elif signal_strength > 0.1:
		return Color(0.6, 0.6, 0.2, 1.0)  # Dim yellow - weak
	else:
		return Color(0.4, 0.4, 0.3, 1.0)  # Gray - barely detectable


func add_maneuver(node: ManeuverNode) -> void:
	if not maneuvers.has(node):
		maneuvers.append(node)
	queue_redraw()


func remove_maneuver(node: ManeuverNode) -> void:
	maneuvers.erase(node)
	if selected_maneuver == node:
		selected_maneuver = null
	queue_redraw()


func _current_zoom_changed() -> void:
	scale_converter.zoom_level = current_zoom


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		scale_converter.viewport_size = size
		queue_redraw()


func _draw() -> void:
	if scale_converter == null:
		return

	# Draw background grid
	_draw_grid()

	# Draw celestial bodies (orbit paths first, then bodies)
	_draw_celestial_orbits()

	# Draw maneuver trajectories
	if show_trajectory_preview and player_ship and player_ship.orbit_state:
		_draw_maneuver_trajectories()

	# Draw maneuver nodes and handles
	_draw_maneuver_handles()

	# Draw sensor contact markers
	if show_contact_markers and sensor_manager:
		_draw_contact_markers()

	# Draw ship
	if player_ship:
		_draw_ship()

	# Draw celestial bodies on top
	_draw_celestial_bodies()


func _draw_grid() -> void:
	var grid_spacing = _get_comfortable_grid_spacing()

	# Vertical lines
	var start_x = int(pan_offset.x / grid_spacing) * grid_spacing
	var y = 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)
		y += grid_spacing

	# Horizontal lines
	var start_y = int(pan_offset.y / grid_spacing) * grid_spacing
	var x = 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
		x += grid_spacing


func _get_comfortable_grid_spacing() -> float:
	var meters_per_pixel = scale_converter.meters_per_pixel
	if meters_per_pixel > 1e10:
		return 1e11
	elif meters_per_pixel > 1e9:
		return 1e10
	elif meters_per_pixel > 1e8:
		return 1e9
	elif meters_per_pixel > 1e7:
		return 1e8
	elif meters_per_pixel > 1e6:
		return 1e7
	elif meters_per_pixel > 1e5:
		return 1e6
	elif meters_per_pixel > 1e4:
		return 1e5
	elif meters_per_pixel > 1000.0:
		return 10000.0
	else:
		return 1000.0


func _draw_celestial_orbits() -> void:
	for body in celestial_bodies:
		if not is_instance_valid(body):
			continue

		# Draw orbit path for bodies with orbits
		if body.has("orbit_state") and body.orbit_state:
			_draw_orbit_path(body)


func _draw_orbit_path(body: CelestialBody) -> void:
	if not body.orbit_state or not body.parent_body:
		return

	var orbit = body.orbit_state
	var mu = body.mu
	var parent_pos = scale_converter.world_to_screen(body.parent_body.world_position)

	# Draw orbit ellipse
	var points = []
	var steps = 180
	for i in range(steps):
		var angle = TAU * i / steps
		var r = orbit.get_radius_at_angle(angle)
		var world_pos = _get_world_orbit_point(r, angle, parent_pos)
		var screen_pos = scale_converter.world_to_screen(world_pos)
		points.append(screen_pos)

	# Fill
	var fill_points = PackedVector2Array(points)
	draw_colored_polygon(fill_points, orbit_fill_color)

	# Outline
	for i in range(points.size()):
		var next_i = (i + 1) % points.size()
		draw_line(points[i], points[next_i], orbit_line_color, 1.5)


func _get_world_orbit_point(radius: float, angle: float, parent_pos: Vector2) -> Vector2:
	var local_x = cos(angle) * radius
	var local_y = -sin(angle) * radius  # Godot uses screen coords (y down)
	return parent_pos + Vector2(local_x, local_y)


func _draw_celestial_bodies() -> void:
	# Sort by size for proper layering (larger bodies drawn first)
	var sorted_bodies = celestial_bodies.duplicate()
	sorted_bodies.sort_custom(func(a, b): return a.radius > b.radius)

	for body in sorted_bodies:
		if not is_instance_valid(body):
			continue

		var screen_pos = scale_converter.world_to_screen(body.world_position)
		var projected_radius = scale_converter.meters_to_pixels(body.radius)

		# Minimum visual size for small bodies
		var min_visual_radius = max(projected_radius, 3.0)
		var max_visual_radius = min(projected_radius * 1.5, 40.0)
		var visual_radius = clamp(min_visual_radius, 4.0, max_visual_radius)

		# Body color
		var body_color = _get_body_color(body)

		# Draw body
		draw_circle(screen_pos, visual_radius, body_color)

		# Draw name label if big enough
		if visual_radius >= 8.0 and body.has("body_name"):
			var label_text = body.body_name
			var font_size = int(clamp(visual_radius * 0.4, 10.0, 16.0))
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(visual_radius + 4, -visual_radius * 0.3),
				label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, body_label_color)


func _get_body_color(body: CelestialBody) -> Color:
	if body.has("body_type"):
		match body.body_type:
			"star":
				return Color(1.0, 0.9, 0.4, 1.0)
			"planet":
				return Color(0.3, 0.5, 0.8, 1.0)
			"moon":
				return Color(0.6, 0.6, 0.6, 1.0)
			_:
				return Color(0.4, 0.4, 0.5, 1.0)
	return Color(0.5, 0.5, 0.5, 1.0)


func _draw_ship() -> void:
	var screen_pos = scale_converter.world_to_screen(player_ship.world_position)

	# Ship icon (triangle pointing in velocity direction)
	var ship_size = max(6.0, 3.0)  # Minimum size for visibility

	# Get velocity direction for orientation
	var velocity_dir = Vector2.UP
	if player_ship.orbit_state:
		velocity_dir = player_ship.orbit_state.velocity.normalized()

	# Rotate velocity to screen coordinates
	var angle = -velocity_dir.angle() + PI/2

	var points = PackedVector2Array([
		_rotate_point(Vector2(0, -ship_size), angle),
		_rotate_point(Vector2(-ship_size * 0.6, ship_size * 0.6), angle),
		_rotate_point(Vector2(0, ship_size * 0.3), angle),
		_rotate_point(Vector2(ship_size * 0.6, ship_size * 0.6), angle)
	])

	for i in range(points.size()):
		points[i] += screen_pos

	draw_colored_polygon(points, ship_color)

	# Draw thrust indicator
	if player_ship.is_thrusting:
		var thrust_dir = player_ship._get_thrust_direction_vector()
		if thrust_dir.length_squared() > 0.1:
			var thrust_length = ship_size * 1.5 * player_ship.throttle
			var thrust_screen = scale_converter.vector_world_to_screen(thrust_dir)
			draw_line(screen_pos, screen_pos + thrust_screen.normalized() * thrust_length,
				Color.ORANGE, 2.0)
	
	# Draw fuel status indicator
	_draw_fuel_indicator(screen_pos, ship_size)


func _rotate_point(point: Vector2, angle: float) -> Vector2:
	var cos_a = cos(angle)
	var sin_a = sin(angle)
	return Vector2(
		point.x * cos_a - point.y * sin_a,
		point.x * sin_a + point.y * cos_a
	)


func _draw_fuel_indicator(screen_pos: Vector2, ship_size: float) -> void:
	## Draw a small fuel indicator next to the ship
	if player_ship == null:
		return
	
	var fuel_pct = player_ship.get_fuel_percent()
	
	# Position indicator below the ship
	var indicator_pos = screen_pos + Vector2(0, ship_size + 8)
	
	# Bar dimensions
	var bar_width = 20.0
	var bar_height = 4.0
	
	# Determine color based on fuel level
	var bar_color: Color
	if fuel_pct > 50:
		bar_color = Color(0.2, 1.0, 0.4)  # Green
	elif fuel_pct > 25:
		bar_color = Color(1.0, 0.6, 0.2)  # Amber
	else:
		bar_color = Color(1.0, 0.3, 0.2)  # Red
	
	# Draw background bar
	var bg_rect = Rect2(indicator_pos - Vector2(bar_width / 2, bar_height / 2), Vector2(bar_width, bar_height))
	draw_rect(bg_rect, Color(0.2, 0.2, 0.2, 0.8), true)
	
	# Draw fuel level
	var fill_width = bar_width * (fuel_pct / 100.0)
	var fill_rect = Rect2(indicator_pos - Vector2(bar_width / 2, bar_height / 2), Vector2(fill_width, bar_height))
	draw_rect(fill_rect, bar_color, true)
	
	# Draw border
	draw_rect(bg_rect, Color(0.5, 0.5, 0.5, 0.6), false, 1.0)


func _draw_maneuver_handles() -> void:
	for node in maneuvers:
		if not is_instance_valid(node):
			continue

		# Calculate screen position of maneuver node
		var screen_pos = _get_maneuver_screen_position(node)
		if screen_pos == Vector2(-1, -1):
			continue

		# Determine handle color based on state
		var handle_col = handle_color
		if node == selected_maneuver:
			handle_col = handle_selected_color
		elif node == hovered_handle:
			handle_col = handle_hover_color

		# Draw handle (circle with border)
		var handle_radius = 10.0
		draw_circle(screen_pos, handle_radius, handle_col)

		# Draw inner circle (darker)
		draw_circle(screen_pos, handle_radius * 0.6, Color(0.1, 0.1, 0.1, 1.0))

		# Draw delta-v arrow
		if node.delta_v.length() > 0.1:
			var dv_screen = scale_converter.vector_world_to_screen(node.delta_v)
			var arrow_end = screen_pos + dv_screen
			draw_line(screen_pos, arrow_end, handle_col, 2.0)
			_draw_arrow_head(arrow_end, dv_screen.normalized(), handle_col)

		# Draw orbit ring at maneuver position
		_draw_maneuver_orbit_marker(node, screen_pos)


func _draw_maneuver_orbit_marker(node: ManeuverNode, screen_pos: Vector2) -> void:
	if not player_ship or not player_ship.orbit_state or not player_ship.parent_body:
		return

	# Draw a small arc or ring at the maneuver position showing orbit
	var orbit = player_ship.orbit_state
	var mu = player_ship.parent_body.mu
	var parent_screen = scale_converter.world_to_screen(player_ship.parent_body.world_position)

	# Get the angle of the maneuver position
	var local_pos = node.node_position - player_ship.parent_body.world_position
	var angle = local_pos.angle()

	# Draw small arc around the orbit at this position
	var orbit_radius_screen = scale_converter.meters_to_pixels(node.node_position.length())

	# Calculate arc angle range (small segment around the maneuver)
	var arc_span = PI / 8  # 45 degrees
	var arc_points = []
	for i in range(13):
		var a = angle - arc_span/2 + arc_span * i / 12
		var point = parent_screen + Vector2(cos(a), sin(a)) * orbit_radius_screen
		arc_points.append(point)

	# Draw the arc
	for i in range(arc_points.size() - 1):
		draw_line(arc_points[i], arc_points[i + 1], maneuver_color, 2.0)


func _draw_arrow_head(pos: Vector2, direction: Vector2, col: Color) -> void:
	var size = 6.0
	var angle = direction.angle()
	var p1 = pos + Vector2(cos(angle + PI * 0.8), sin(angle + PI * 0.8)) * size
	var p2 = pos + Vector2(cos(angle - PI * 0.8), sin(angle - PI * 0.8)) * size
	draw_line(pos, p1, col, 2.0)
	draw_line(pos, p2, col, 2.0)


func _get_maneuver_screen_position(node: ManeuverNode) -> Vector2:
	if not player_ship or not player_ship.orbit_state:
		return Vector2(-1, -1)

	# Calculate where the maneuver node is on the orbit at the maneuver time
	# For simplicity, use the node's stored position
	return scale_converter.world_to_screen(node.node_position)


func _draw_maneuver_trajectories() -> void:
	# Draw predicted trajectory based on current maneuvers
	var state = player_ship.orbit_state.duplicate()

	# Apply maneuver delta-v to get new state for preview
	if maneuvers.size() > 0:
		var first_node = maneuvers[0]
		if first_node.delta_v.length() > 0.1:
			_draw_predicted_orbit(state, first_node.delta_v)


func _draw_predicted_orbit(state: OrbitState, dv: Vector2) -> void:
	# Calculate new orbit after burn
	var new_vel = state.velocity + dv
	var new_orbit = OrbitalMechanics.calculate_orbit_from_state(
		state.position, new_vel, player_ship.parent_body.mu, TimeManager.simulation_time)

	if not new_orbit.is_valid():
		return

	# Draw predicted orbit
	var parent_pos = scale_converter.world_to_screen(player_ship.parent_body.world_position)
	var points = []
	var steps = 180
	for i in range(steps):
		var angle = TAU * i / steps
		var r = new_orbit.get_radius_at_angle(angle)
		var world_pos = _get_world_orbit_point(r, angle, parent_pos)
		var screen_pos = scale_converter.world_to_screen(world_pos)
		points.append(screen_pos)

	# Draw predicted orbit with dashed effect (we use opacity)
	var pred_fill = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, 0.15)
	var pred_line = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, 0.6)

	draw_colored_polygon(PackedVector2Array(points), pred_fill)
	for i in range(points.size()):
		var next_i = (i + 1) % points.size()
		draw_line(points[i], points[next_i], pred_line, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var mouse_pos = event.position

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Check if clicking on a maneuver handle
			var clicked_node = _get_maneuver_at_position(mouse_pos)
			if clicked_node:
				_select_maneuver(clicked_node)
				is_dragging = true
				drag_start_pos = mouse_pos
				if clicked_node.delta_v.length() > 0:
					drag_maneuver_original_dv = clicked_node.delta_v
				else:
					# Default to prograde direction if no delta-v yet
					drag_maneuver_original_dv = player_ship.orbit_state.get_prograde() * 100.0
			else:
				# Deselect if clicking empty space
				_deselect_maneuver()
		else:
			# Mouse released
			if is_dragging and selected_maneuver:
				maneuver_node_updated.emit(selected_maneuver)
			is_dragging = false

	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			# Toggle maneuver direction (prograde/retrograde)
			var clicked_node = _get_maneuver_at_position(mouse_pos)
			if clicked_node:
				_toggle_maneuver_direction(clicked_node)

	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom(1.0 / zoom_speed)

	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom(zoom_speed)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var mouse_pos = event.position

	if is_dragging and selected_maneuver:
		_update_maneuver_from_drag(mouse_pos)
	else:
		# Update hover state
		var hovered = _get_maneuver_at_position(mouse_pos)
		if hovered != hovered_handle:
			hovered_handle = hovered
			queue_redraw()


func _get_maneuver_at_position(pos: Vector2) -> ManeuverNode:
	for node in maneuvers:
		if not is_instance_valid(node):
			continue
		var screen_pos = _get_maneuver_screen_position(node)
		if screen_pos != Vector2(-1, -1) and pos.distance_to(screen_pos) < 15.0:
			return node
	return null


func _select_maneuver(node: ManeuverNode) -> void:
	selected_maneuver = node
	maneuver_node_selected.emit(node)
	queue_redraw()


func _deselect_maneuver() -> void:
	selected_maneuver = null
	queue_redraw()


func _toggle_maneuver_direction(node: ManeuverNode) -> void:
	if node.delta_v.length() < 0.1:
		return

	# Reverse the direction
	node.delta_v = -node.delta_v
	maneuver_node_updated.emit(node)
	queue_redraw()


func _update_maneuver_from_drag(mouse_pos: Vector2) -> void:
	if not selected_maneuver or not player_ship or not player_ship.orbit_state:
		return

	# Get the screen position of the maneuver node
	var maneuver_screen = _get_maneuver_screen_position(selected_maneuver)
	if maneuver_screen == Vector2(-1, -1):
		return

	# Calculate drag delta in screen space
	var drag_delta = mouse_pos - maneuver_screen

	# Convert to world space for magnitude
	var drag_world_magnitude = scale_converter.pixels_to_meters(drag_delta.length())
	var drag_direction = drag_delta.normalized()

	# Convert screen drag direction to world space
	# We need to figure out the world direction from the screen drag
	# For now, calculate delta-v based on drag direction relative to screen

	# Map screen drag to world space using approximate conversion
	# This is a simplified version - for more accuracy we'd track camera orientation
	var drag_world_dir = _screen_direction_to_world(drag_direction)

	# Calculate new delta-v magnitude (clamped)
	var dv_magnitude = drag_world_magnitude * 10  # Scale factor for usability
	dv_magnitude = clamp(dv_magnitude, 0.0, 10000.0)

	# Apply direction
	var new_dv = drag_world_dir * dv_magnitude

	# If shift is held, constrain to prograde/retrograde only
	if Input.is_key_pressed(KEY_SHIFT):
		var prograde = player_ship.orbit_state.get_prograde().normalized()
		var radial = player_ship.orbit_state.get_radial_out().normalized()
		var prograde_component = new_dv.dot(prograde)
		var radial_component = new_dv.dot(radial)

		# Determine if primarily prograde or retrograde
		if abs(prograde_component) > abs(radial_component):
			new_dv = prograde * sign(prograde_component) * dv_magnitude
		else:
			new_dv = radial * sign(radial_component) * dv_magnitude

	selected_maneuver.delta_v = new_dv
	queue_redraw()


func _screen_direction_to_world(screen_dir: Vector2) -> Vector2:
	# Approximate conversion: for orbital view, assume screen X = tangent, screen Y = radial
	# This gives reasonable control for maneuver planning
	if not player_ship or not player_ship.orbit_state:
		return Vector2.RIGHT

	var orbit = player_ship.orbit_state

	# Get local orbital directions at current position
	var radial = orbit.position.normalized()  # Radial outward
	var tangent = Vector2(-radial.y, radial.x)  # Prograde direction (perpendicular)

	// Note: screen Y is inverted (down is positive)
	// Map screen right to tangent, screen down to inward radial
	var world_dir = tangent * screen_dir.x + Vector2(radial.y, -radial.x) * (-screen_dir.y)

	if world_dir.length_squared() > 0.001:
		world_dir = world_dir.normalized()

	return world_dir


func _zoom(factor: float) -> void:
	var old_zoom = current_zoom
	current_zoom = clamp(current_zoom * factor, min_zoom, max_zoom)

	# Adjust pan offset to zoom toward center
	var zoom_ratio = current_zoom / old_zoom
	pan_offset = pan_offset * zoom_ratio

	scale_converter.zoom_level = current_zoom
	queue_redraw()


func _pan(delta: Vector2) -> void:
	pan_offset += delta
	scale_converter.offset = pan_offset
	queue_redraw()


func center_on_position(world_pos: Vector2) -> void:
	var screen_pos = scale_converter.world_to_screen(world_pos)
	pan_offset = size / 2 - screen_pos
	scale_converter.offset = pan_offset
	queue_redraw()


func get_viewport_center_world() -> Vector2:
	return scale_converter.screen_to_world(size / 2)


func world_to_screen(world_pos: Vector2) -> Vector2:
	return scale_converter.world_to_screen(world_pos)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return scale_converter.screen_to_world(screen_pos)


func refresh_contact_display() -> void:
	## Refresh contact labels and redraw when sensor contacts change
	_update_contact_labels()
	queue_redraw()


func _draw_thermal_contact_markers() -> void:
	## Draw thermal contact markers on the tactical display
	if sensor_manager == null or not show_contact_markers:
		return
	
	var contacts = sensor_manager.get_all_detected_contacts()
	
	for contact in contacts:
		if not is_instance_valid(contact) or not is_instance_valid(contact.body):
			continue
		
		# Get contact position
		var contact_pos: Vector2
		if contact.body.has_method("world_position"):
			contact_pos = contact.body.world_position
		elif contact.body is Node2D:
			contact_pos = contact.body.position
		else:
			continue
		
		# Convert to screen position
		var screen_pos = scale_converter.world_to_screen(contact_pos)
		
		# Check if on screen
		if not _is_on_screen(screen_pos):
			continue
		
		# Determine marker color based on thermal signal
		var heat_level = contact.thermal_signal_strength
		var marker_color = _get_thermal_marker_color(heat_level)
		
		# Draw marker based on contact status
		var marker_size = contact_marker_size
		match contact.status:
			SensorManager.ContactStatus.UNKNOWN:
				# Question mark marker for unknown contacts
				_draw_contact_marker_unknown(screen_pos, marker_color, marker_size)
			SensorManager.ContactStatus.INVESTIGATING:
				# Circle marker for investigating
				_draw_contact_marker_investigating(screen_pos, marker_color, marker_size)
			SensorManager.ContactStatus.IDENTIFIED:
				# Filled marker for identified
				_draw_contact_marker_identified(screen_pos, marker_color, marker_size)
			SensorManager.ContactStatus.LOST:
				# X marker for lost contacts
				_draw_contact_marker_lost(screen_pos, marker_color, marker_size)


func _get_thermal_marker_color(heat_level: float) -> Color:
	## Get marker color based on heat signature level
	if heat_level >= 0.8:
		return thermal_contact_colors[1.0]
	elif heat_level >= 0.5:
		return thermal_contact_colors[0.8]
	elif heat_level >= 0.2:
		return thermal_contact_colors[0.5]
	elif heat_level >= 0.1:
		return thermal_contact_colors[0.2]
	else:
		return thermal_contact_colors[0.0]


func _draw_contact_marker_unknown(pos: Vector2, color: Color, size: float) -> void:
	## Draw unknown contact marker (question mark)
	draw_circle(pos, size, Color(color, 0.5))
	draw_string(ThemeDB.fallback_font, pos + Vector2(-size/2, size/2), "?", HORIZONTAL_ALIGNMENT_CENTER, size, size/2, color)


func _draw_contact_marker_investigating(pos: Vector2, color: Color, size: float) -> void:
	## Draw investigating contact marker (circle)
	draw_arc(pos, size, 0, TAU, 24, color, 2.0)


func _draw_contact_marker_identified(pos: Vector2, color: Color, size: float) -> void:
	## Draw identified contact marker (filled circle)
	draw_circle(pos, size, color)
	draw_arc(pos, size + 3, 0, TAU, 24, Color(color, 0.7), 1.0)


func _draw_contact_marker_lost(pos: Vector2, color: Color, size: float) -> void:
	## Draw lost contact marker (X)
	var offset = size * 0.7
	draw_line(pos + Vector2(-offset, -offset), pos + Vector2(offset, offset), color, 2.0)
	draw_line(pos + Vector2(-offset, offset), pos + Vector2(offset, -offset), color, 2.0)


func set_contact_visibility(visible: bool) -> void:
	## Show or hide contact markers
	show_contact_markers = visible
	queue_redraw()


func get_visible_contacts() -> Array:
	## Get list of contacts visible on screen
	var visible: Array = []
	
	if sensor_manager == null:
		return visible
	
	var contacts = sensor_manager.get_all_detected_contacts()
	for contact in contacts:
		if not is_instance_valid(contact) or not is_instance_valid(contact.body):
			continue
		
		var contact_pos: Vector2
		if contact.body.has_method("world_position"):
			contact_pos = contact.body.world_position
		elif contact.body is Node2D:
			contact_pos = contact.body.position
		else:
			continue
		
		var screen_pos = scale_converter.world_to_screen(contact_pos)
		if _is_on_screen(screen_pos):
			visible.append(contact)
	
	return visible# === Radar Functions ===

func set_radar_mode(enabled: bool) -> void:
	## Enable or disable radar mode
	radar_mode_active = enabled
	if enabled:
		radar_sweep_angle = 0.0
	queue_redraw()


func set_radar_range(meters: float) -> void:
	## Set radar range for display
	radar_range_display = meters
	queue_redraw()


func set_lock_target(contact_id: String) -> void:
	## Set contact to lock onto
	locked_contact_id = contact_id
	lock_acquired = false
	lock_progress = 0.0
	queue_redraw()


func clear_lock_target() -> void:
	## Clear current lock target
	locked_contact_id = ""
	lock_acquired = false
	lock_progress = 0.0
	queue_redraw()


func _draw_radar_overlay() -> void:
	## Draw radar sweep and range rings when radar mode is active
	if not radar_mode_active or player_ship == null:
		return
	
	# Player position in screen coordinates
	var player_screen_pos = scale_converter.world_to_screen(player_ship.world_position)
	
	# Draw range rings (concentric circles)
	var num_rings = 4
	for i in range(1, num_rings + 1):
		var ring_radius = (radar_range_display / float(num_rings) / i) * current_zoom
		var alpha = 0.3 - (float(i) / float(num_rings)) * 0.2
		var ring_color = Color(radar_range_color.r, radar_range_color.g, radar_range_color.b, alpha)
		draw_arc(player_screen_pos, ring_radius, 0, TAU, 64, ring_color, 1.0)
	
	# Draw radar sweep (animated arc from current angle)
	var sweep_radius = radar_range_display * current_zoom
	var sweep_width = 0.4  # radians
	_draw_radar_sweep(player_screen_pos, sweep_radius, radar_sweep_angle, sweep_width, radar_sweep_color)
	
	# Draw range labels
	var range_labels = [100, 250, 500, 1000]  # km for display
	for i in range(num_rings):
		var ring_dist = radar_range_display / float(num_rings) * (i + 1)
		var screen_pos = player_screen_pos + Vector2.RIGHT * (ring_dist * current_zoom)
		if _is_on_screen(screen_pos):
			var dist_km = ring_dist / 1000.0
			var label_text = "%.0f km" % dist_km
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(5, 5), label_text, HORIZONTAL_ALIGNMENT_LEFT, 50, 10, Color(radar_range_color.r, radar_range_color.g, radar_range_color.b, 0.6))


func _draw_radar_sweep(center: Vector2, radius: float, angle: float, width: float, color: Color) -> void:
	## Draw a radar sweep arc effect
	var start_angle = angle - width
	var end_angle = angle
	
	# Draw filled arc for sweep
	draw_arc(center, radius, start_angle, end_angle, 24, Color(color.r, color.g, color.b, 0.3), 2.0)
	draw_arc(center, radius * 0.95, start_angle, end_angle, 16, Color(color.r, color.g, color.b, 0.15), 1.0)
	draw_arc(center, radius * 0.85, start_angle, end_angle, 12, Color(color.r, color.g, color.b, 0.08), 1.0)
	
	# Draw sweep line
	draw_line(center, center + Vector2.from_angle(angle) * radius, color, 1.5)
	
	# Draw leading edge glow
	draw_arc(center, radius * 0.02, 0, TAU, 12, Color(color.r, color.g, color.b, 0.8), 1.0)


func _draw_lock_on_marker(contact: SensorContact) -> void:
	## Draw lock-on brackets around a locked contact
	if locked_contact_id == "" or lock_progress <= 0:
		return
	
	# Get contact position
	var contact_pos: Vector2
	if is_instance_valid(contact) and is_instance_valid(contact.body):
		if contact.body.has_method("world_position"):
			contact_pos = contact.body.world_position
		elif contact.body is Node2D:
			contact_pos = contact.body.position
		else:
			return
	else:
		return
	
	var screen_pos = scale_converter.world_to_screen(contact_pos)
	
	if not _is_on_screen(screen_pos):
		return
	
	# Lock bracket parameters
	var bracket_size = 16.0 + (lock_progress / lock_duration) * 8.0
	var bracket_gap = 4.0
	var line_width = 2.0
	var progress = lock_progress / lock_duration
	
	# Draw lock brackets - corners only, growing as lock progresses
	var bracket_color = Color(1.0, 0.3, 0.2, 0.8 + progress * 0.2)  # Red with glow
	
	# Top-left bracket
	if progress >= 0.25:
		var end_x = screen_pos.x - bracket_gap
		var end_y = screen_pos.y - bracket_gap - bracket_size
		var start_x = screen_pos.x - bracket_gap - bracket_size
		draw_line(Vector2(start_x, end_y), Vector2(start_x, end_y + bracket_size * (min(progress * 4.0, 1.0))), bracket_color, line_width)
		draw_line(Vector2(start_x, end_y + bracket_size), Vector2(start_x + bracket_size * (min(progress * 4.0 - 1.0, 1.0)), end_y + bracket_size), bracket_color, line_width)
	
	# Top-right bracket
	if progress >= 0.5:
		var start_y = screen_pos.y - bracket_gap - bracket_size
		var end_x = screen_pos.x + bracket_gap + bracket_size
		var start_x = screen_pos.x + bracket_gap
		var progress_adj = (progress - 0.5) * 4.0
		draw_line(Vector2(end_x - bracket_size * min(progress_adj, 1.0), start_y), Vector2(end_x, start_y), bracket_color, line_width)
		draw_line(Vector2(end_x, start_y), Vector2(end_x, start_y + bracket_size * min(progress_adj, 1.0)), bracket_color, line_width)
	
	# Bottom-right bracket
	if progress >= 0.75:
		var start_x = screen_pos.x + bracket_gap + bracket_size
		var start_y = screen_pos.y + bracket_gap
		var progress_adj = (progress - 0.75) * 4.0
		draw_line(Vector2(start_x, start_y), Vector2(start_x - bracket_size * min(progress_adj, 1.0), start_y), bracket_color, line_width)
		draw_line(Vector2(start_x - bracket_size, start_y), Vector2(start_x - bracket_size, start_y + bracket_size * min(progress_adj, 1.0)), bracket_color, line_width)
	
	# Bottom-left bracket
	if progress >= 1.0:
		var end_y = screen_pos.y + bracket_gap + bracket_size
		var start_x = screen_pos.x - bracket_gap - bracket_size
		draw_line(Vector2(start_x, screen_pos.y + bracket_gap), Vector2(start_x, end_y), bracket_color, line_width)
	
	# Draw "LOCK" text when complete
	if progress >= 1.0 and not lock_acquired:
		lock_acquired = true
		draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-16, -20), "LOCK", HORIZONTAL_ALIGNMENT_LEFT, 32, 12, bracket_color)


func is_lock_acquired() -> bool:
	## Check if a lock is currently acquired
	return lock_acquired


func _process(delta: float) -> void:
	# Update radar sweep
	if radar_mode_active:
		radar_sweep_angle += radar_sweep_speed * delta
		if radar_sweep_angle > TAU:
			radar_sweep_angle -= TAU
	
	# Update lock progress
	if locked_contact_id != "" and not lock_acquired:
		lock_progress += delta / lock_duration
		if lock_progress >= 1.0:
			lock_progress = 1.0
			lock_acquired = true
	
	queue_redraw()


func _draw_lock_brackets(pos: Vector2, size: float, color: Color) -> void:
	## Draw target lock brackets
	var half = size / 2
	
	# Top-left bracket
	draw_line(pos + Vector2(-half, -half), pos + Vector2(-half, 0), color, 2.0)
	draw_line(pos + Vector2(-half, -half), pos + Vector2(0, -half), color, 2.0)
	
	# Top-right bracket
	draw_line(pos + Vector2(half, -half), pos + Vector2(half, 0), color, 2.0)
	draw_line(pos + Vector2(half, -half), pos + Vector2(0, -half), color, 2.0)
	
	# Bottom-left bracket
	draw_line(pos + Vector2(-half, half), pos + Vector2(-half, 0), color, 2.0)
	draw_line(pos + Vector2(-half, half), pos + Vector2(0, half), color, 2.0)
	
	# Bottom-right bracket
	draw_line(pos + Vector2(half, half), pos + Vector2(half, 0), color, 2.0)
	draw_line(pos + Vector2(half, half), pos + Vector2(0, half), color, 2.0)


func _draw_maneuver_nodes() -> void:
	## Draw maneuver nodes and their predictions on the tactical display
	if maneuvers.is_empty():
		return
	
	for node in maneuvers:
		if not is_instance_valid(node):
			continue
		
		# Get position at execution time
		if player_ship == null or player_ship.orbit_state == null:
			continue
		
		var ship_state = player_ship.orbit_state.get_state_at_time(node.execution_time)
		var screen_pos = scale_converter.world_to_screen(ship_state.position)
		
		# Check if on screen (with margin for labels)
		if not _is_on_screen(screen_pos) and screen_pos.distance_to(size * 0.5) > size.length() * 0.6:
			continue
		
		# Draw maneuver node marker
		_draw_maneuver_marker(screen_pos, node)
		
		# Draw delta-v vector
		_draw_delta_v_vector(screen_pos, node)
		
		# Draw resulting orbit prediction
		if node.resulting_orbit:
			_draw_resulting_orbit(node)


func _draw_maneuver_marker(pos: Vector2, node: ManeuverNode) -> void:
	## Draw maneuver node marker (filled circle with ring)
	var node_size = 12.0
	var is_selected = node == selected_maneuver
	var is_hovered = node == hovered_handle
	
	# Outer ring
	var ring_color = handle_color
	if is_selected:
		ring_color = handle_selected_color
	elif is_hovered:
		ring_color = handle_hover_color
	
	draw_arc(pos, node_size, 0, TAU, 32, ring_color, 2.0, true)
	
	# Inner dot
	var inner_color = maneuver_color
	if is_selected:
		inner_color = handle_selected_color
	elif is_hovered:
		inner_color = handle_hover_color
	
	draw_circle(pos, node_size * 0.4, inner_color)
	
	# Draw time label
	var time_str = OrbitalConstants.format_time(node.execution_time - TimeManager.simulation_time)
	var label_offset = Vector2(node_size + 4, -node_size * 0.5)
	draw_string(ThemeDB.fallback_font, pos + label_offset, time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, maneuver_color)


func _draw_delta_v_vector(start_pos: Vector2, node: ManeuverNode) -> void:
	## Draw delta-v vector from maneuver node
	var dv = node.delta_v
	
	# Scale for display (1 pixel = some velocity value)
	var scale = 0.00001  # 1 pixel per 100 m/s (adjustable)
	var end_pos = start_pos + dv * scale
	
	# Clamp to reasonable display range
	var max_length = 200.0
	if start_pos.distance_to(end_pos) > max_length:
		var direction = (end_pos - start_pos).normalized()
		end_pos = start_pos + direction * max_length
	
	# Draw vector line
	var dv_color = Color(1.0, 0.8, 0.2, 0.8)
	draw_line(start_pos, end_pos, dv_color, 2.0)
	
	# Draw arrowhead
	var arrow_size = 8.0
	var angle = (end_pos - start_pos).angle()
	var arrow_dir = Vector2.from_angle(angle)
	var perp_dir = Vector2.from_angle(angle + PI * 0.5)
	
	var tip_left = end_pos - arrow_dir * arrow_size + perp_dir * arrow_size * 0.5
	var tip_right = end_pos - arrow_dir * arrow_size - perp_dir * arrow_size * 0.5
	
	draw_line(end_pos, tip_left, dv_color, 2.0)
	draw_line(end_pos, tip_right, dv_color, 2.0)
	
	# Draw delta-v magnitude label
	var mid_pos = start_pos + (end_pos - start_pos) * 0.5
	var dv_mag = node.get_delta_v_magnitude()
	var dv_str = OrbitalConstants.format_velocity(dv_mag)
	draw_string(ThemeDB.fallback_font, mid_pos + Vector2(-16, -8), dv_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, dv_color)


func _draw_resulting_orbit(node: ManeuverNode) -> void:
	## Draw the predicted orbit after maneuver
	if node.resulting_orbit == null or player_ship == null:
		return
	
	var parent_body = player_ship.parent_body
	if parent_body == null:
		return
	
	var parent_pos = scale_converter.world_to_screen(parent_body.world_position)
	var orbit = node.resulting_orbit
	
	# Sample orbit points
	var points = []
	var steps = 180
	var semi_major = orbit.semi_major_axis
	var eccentricity = orbit.eccentricity
	
	if semi_major <= 0 or semi_major > 1e15:
		return
	
	var max_eccentricity = 0.95  # Skip highly eccentric orbits
	if eccentricity > max_eccentricity:
		eccentricity = max_eccentricity
	
	for i in range(steps):
		var angle = TAU * i / steps
		var r = semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(angle))
		var world_pos = _get_world_orbit_point(r, angle, parent_pos)
		var screen_pos = scale_converter.world_to_screen(world_pos)
		points.append(screen_pos)
	
	# Draw predicted orbit as dashed line
	var predicted_color = Color(0.8, 0.6, 0.2, 0.5)
	
	for i in range(points.size()):
		# Draw every other segment for dashed effect
		if i % 2 == 0:
			var next_i = (i + 1) % points.size()
			if _is_on_screen(points[i]) or _is_on_screen(points[next_i]):
				draw_line(points[i], points[next_i], predicted_color, 1.0)


func _get_time_until_maneuver(node: ManeuverNode) -> float:
	## Get time until a maneuver executes
	return max(0.0, node.execution_time - TimeManager.simulation_time)


func _draw_contact_markers() -> void:
	## Draw thermal contact markers on the tactical display
	if sensor_manager == null or not show_contact_markers:
		return
	
	var contacts = sensor_manager.get_all_detected_contacts()
	
	for contact in contacts:
		if not is_instance_valid(contact) or not is_instance_valid(contact.body):
			continue
		
		# Get contact position
		var contact_pos: Vector2
		if contact.body.has_method("world_position"):
			contact_pos = contact.body.world_position
		elif contact.body is Node2D:
			contact_pos = contact.body.position
		else:
			continue
		
		# Convert to screen position
		var screen_pos = scale_converter.world_to_screen(contact_pos)
		
		# Check if on screen
		if not _is_on_screen(screen_pos):
			continue
		
		# Determine marker color based on thermal signal
		var heat_level = contact.thermal_signal_strength
		var marker_color = _get_thermal_marker_color(heat_level)
		
		# Draw marker based on contact status
		var marker_size = contact_marker_size
		match contact.contact_status:
			SensorManager.ContactStatus.UNKNOWN:
				# Question mark marker for unknown contacts
				_draw_contact_marker_unknown(screen_pos, marker_color, marker_size)
			SensorManager.ContactStatus.INVESTIGATING:
				# Circle marker for investigating
				_draw_contact_marker_investigating(screen_pos, marker_color, marker_size)
			SensorManager.ContactStatus.IDENTIFIED:
				# Filled marker for identified
				_draw_contact_marker_identified(screen_pos, marker_color, marker_size)
			SensorManager.ContactStatus.LOST:
				# X marker for lost contacts
				_draw_contact_marker_lost(screen_pos, marker_color, marker_size)