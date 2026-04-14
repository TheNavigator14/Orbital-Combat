class_name TacticalDisplay
extends Control
## Main tactical display showing orbits and bodies
## CRT aesthetic inspired by SpaceCombat's ContactDisplay

# === Visual Settings (CRT Aesthetic) ===
const BACKGROUND_COLOR := Color(0.01, 0.04, 0.02, 1.0)  # Near-black with green tint
const GRID_COLOR := Color(0.0, 0.3, 0.0, 0.5)
const ORBIT_COLOR := Color(0.0, 0.6, 0.0, 0.8)
const ORBIT_PREDICTED_COLOR := Color(0.6, 0.5, 0.0, 0.6)
const BODY_COLOR := Color(0.0, 0.8, 0.0, 1.0)
const SHIP_COLOR := Color(0.0, 1.0, 0.0, 1.0)
const TEXT_COLOR := Color(0.0, 0.9, 0.0, 1.0)

const SCANLINE_SPACING := 3.0
const SCANLINE_ALPHA := 0.08
const VIGNETTE_STRENGTH := 0.3

# === Zoom Settings ===
const ZOOM_SPEED := 0.15
const MIN_ZOOM := 0.0001
const MAX_ZOOM := 10000.0

# === References ===
var scale_converter: ScaleConverter
var camera: OrbitalCamera
var maneuver_renderer: ManeuverRenderer
var maneuver_interaction: ManeuverInteraction
var navigation_planner: NavigationPlanner

# === State ===
var solar_system: Node = null
var player_ship: Ship = null
var selected_body: Node = null


func _ready() -> void:
	scale_converter = ScaleConverter.new()
	_update_scale_converter_size()

	# Set initial zoom to see ship's local orbit around Earth
	# At LINEAR_SCALE 1e-6 and zoom 50, the 400km orbit is ~200 pixels radius
	scale_converter.zoom_level = 50.0

	# Initialize maneuver renderer
	maneuver_renderer = ManeuverRenderer.new()
	maneuver_renderer.set_scale_converter(scale_converter)

	# Initialize maneuver interaction
	maneuver_interaction = ManeuverInteraction.new()
	maneuver_interaction.setup(null, scale_converter, maneuver_renderer)
	maneuver_interaction.maneuver_modified.connect(_on_maneuver_modified)

	# Create navigation planner (hidden by default)
	navigation_planner = NavigationPlanner.new()
	navigation_planner.visible = false
	add_child(navigation_planner)
	navigation_planner.maneuvers_created.connect(_on_maneuvers_created)
	navigation_planner.closed.connect(_on_navigation_planner_closed)

	# Connect to GameManager
	if GameManager:
		GameManager.player_ship_changed.connect(_on_player_ship_changed)
		GameManager.focus_body_changed.connect(_on_focus_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_scale_converter_size()


func _update_scale_converter_size() -> void:
	scale_converter.set_screen_size(size)


func _gui_input(event: InputEvent) -> void:
	# Don't process input if navigation planner is open
	if navigation_planner and navigation_planner.visible:
		return

	# Handle mouse clicks
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check PLAN ROUTE button
			if _is_point_in_plan_route_button(event.position):
				_open_navigation_planner()
				accept_event()
				return

		# Let ManeuverInteraction handle mouse buttons
		if maneuver_interaction and maneuver_interaction.handle_mouse_button(event):
			accept_event()
			return

		# Handle zoom with mouse wheel
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_in()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_out()
			accept_event()

	# Handle mouse motion for drag interactions
	if event is InputEventMouseMotion:
		if maneuver_interaction and maneuver_interaction.handle_mouse_motion(event):
			accept_event()
			return

	# Handle keyboard input
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_N:
			_open_navigation_planner()
			accept_event()
		elif event.keycode == KEY_DELETE:
			if maneuver_interaction:
				maneuver_interaction.delete_selected_maneuver()
			accept_event()


func zoom_in() -> void:
	scale_converter.zoom_level = clampf(scale_converter.zoom_level * (1.0 + ZOOM_SPEED), MIN_ZOOM, MAX_ZOOM)


func zoom_out() -> void:
	scale_converter.zoom_level = clampf(scale_converter.zoom_level / (1.0 + ZOOM_SPEED), MIN_ZOOM, MAX_ZOOM)


func setup(p_solar_system: Node, p_camera: OrbitalCamera) -> void:
	solar_system = p_solar_system
	camera = p_camera


func _process(_delta: float) -> void:
	# Always center on player ship
	if player_ship and "world_position" in player_ship:
		scale_converter.set_focus(player_ship.world_position)

	queue_redraw()


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)

	# Distance grid
	_draw_distance_grid()

	# Draw celestial body orbits and bodies
	if solar_system:
		for child in solar_system.get_children():
			if child is Planet:
				_draw_orbit(child)
			if child is CelestialBody:
				_draw_body(child)

	# Draw player ship
	if player_ship:
		_draw_ship_orbit(player_ship)
		_draw_ship(player_ship)

		# Draw maneuver nodes
		if maneuver_renderer:
			maneuver_renderer.draw_maneuvers(self, player_ship)

	# CRT effects
	_draw_scanlines()
	_draw_vignette()

	# UI overlay
	_draw_info_panel()
	_draw_plan_route_button()


func _draw_distance_grid() -> void:
	## Draw distance rings at logarithmic intervals
	var center = size / 2.0

	# Distance rings (in meters)
	var distances = [
		1.0e6,   # 1,000 km
		1.0e7,   # 10,000 km
		1.0e8,   # 100,000 km
		1.0e9,   # 1 million km
		1.0e10,  # 10 million km
		1.0e11,  # 100 million km (~ 0.67 AU)
		OrbitalConstantsClass.AU,  # 1 AU
		5.0 * OrbitalConstantsClass.AU,   # 5 AU (Jupiter area)
		10.0 * OrbitalConstantsClass.AU,  # 10 AU (Saturn area)
		20.0 * OrbitalConstantsClass.AU,  # 20 AU (Uranus area)
		30.0 * OrbitalConstantsClass.AU,  # 30 AU (Neptune area)
	]

	for dist in distances:
		var screen_radius = scale_converter.distance_to_screen(dist)
		if screen_radius > 5 and screen_radius < size.length():
			_draw_dashed_circle(center, screen_radius, GRID_COLOR, 1.0, 8.0, 4.0)

			# Label
			var label = OrbitalConstantsClass.format_distance(dist)
			var label_pos = center + Vector2(screen_radius + 5, 0)
			if label_pos.x < size.x - 100:
				draw_string(ThemeDB.fallback_font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GRID_COLOR)


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float = 1.0, dash_length: float = 10.0, gap_length: float = 5.0) -> void:
	## Draw a dashed circle
	var circumference = TAU * radius
	var total_segment = dash_length + gap_length
	var num_segments = int(circumference / total_segment)

	if num_segments < 4:
		# Too small, draw solid
		draw_arc(center, radius, 0, TAU, 32, color, width)
		return

	var angle_per_segment = TAU / float(num_segments)
	var dash_angle = angle_per_segment * (dash_length / total_segment)

	for i in range(num_segments):
		var start_angle = i * angle_per_segment
		var end_angle = start_angle + dash_angle
		draw_arc(center, radius, start_angle, end_angle, 8, color, width)


func _draw_orbit(planet: Planet) -> void:
	## Draw a planet's orbit
	if planet.orbit_state == null:
		return

	var points = planet.orbit_state.sample_orbit_points(100)
	var screen_points = PackedVector2Array()

	for point in points:
		# Planet orbit is relative to its parent (Sun)
		var world_pos = point + planet.parent_body.world_position
		var screen_pos = scale_converter.world_to_screen(world_pos)
		screen_points.append(screen_pos)

	if screen_points.size() > 1:
		# Close the orbit
		screen_points.append(screen_points[0])
		draw_polyline(screen_points, ORBIT_COLOR, 1.0, true)


func _draw_body(body: CelestialBody) -> void:
	## Draw a celestial body
	var screen_pos = scale_converter.world_to_screen(body.world_position)

	# Check if on screen
	if not Rect2(Vector2.ZERO, size).has_point(screen_pos):
		# Draw off-screen indicator
		_draw_offscreen_indicator(body.body_name, screen_pos)
		return

	# Body circle
	var display_radius = clampf(scale_converter.distance_to_screen(body.radius), 3.0, 50.0)
	draw_circle(screen_pos, display_radius, body.display_color)

	# Label
	var label_pos = screen_pos + Vector2(display_radius + 5, -5)
	draw_string(ThemeDB.fallback_font, label_pos, body.body_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)


func _draw_ship_orbit(ship: Ship) -> void:
	## Draw the player ship's current orbit
	if ship.orbit_state == null or ship.parent_body == null:
		return

	var points = ship.orbit_state.sample_orbit_points(100)
	var screen_points = PackedVector2Array()

	for point in points:
		var world_pos = point + ship.parent_body.world_position
		var screen_pos = scale_converter.world_to_screen(world_pos)
		screen_points.append(screen_pos)

	if screen_points.size() > 1:
		if ship.orbit_state.eccentricity < 1.0:
			screen_points.append(screen_points[0])  # Close ellipse
		draw_polyline(screen_points, SHIP_COLOR, 1.5, true)

	# Draw apoapsis and periapsis markers
	_draw_apsides(ship)


func _draw_apsides(ship: Ship) -> void:
	## Draw apoapsis and periapsis markers
	if ship.orbit_state == null:
		return

	var orbit = ship.orbit_state

	# Periapsis
	var pe_angle = orbit.argument_of_periapsis
	var pe_radius = orbit.periapsis
	var pe_world = Vector2(pe_radius * cos(pe_angle), pe_radius * sin(pe_angle)) + ship.parent_body.world_position
	var pe_screen = scale_converter.world_to_screen(pe_world)

	if Rect2(Vector2.ZERO, size).has_point(pe_screen):
		draw_circle(pe_screen, 4, Color.CYAN)
		draw_string(ThemeDB.fallback_font, pe_screen + Vector2(6, 4), "Pe", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.CYAN)

	# Apoapsis (only for elliptical orbits)
	if orbit.eccentricity < 1.0:
		var ap_angle = orbit.argument_of_periapsis + PI
		var ap_radius = orbit.apoapsis
		var ap_world = Vector2(ap_radius * cos(ap_angle), ap_radius * sin(ap_angle)) + ship.parent_body.world_position
		var ap_screen = scale_converter.world_to_screen(ap_world)

		if Rect2(Vector2.ZERO, size).has_point(ap_screen):
			draw_circle(ap_screen, 4, Color.ORANGE)
			draw_string(ThemeDB.fallback_font, ap_screen + Vector2(6, 4), "Ap", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.ORANGE)


func _draw_ship(ship: Ship) -> void:
	## Draw the player ship
	var screen_pos = scale_converter.world_to_screen(ship.world_position)

	if not Rect2(Vector2.ZERO, size).has_point(screen_pos):
		_draw_offscreen_indicator(ship.ship_name, screen_pos)
		return

	# Ship icon (triangle)
	var ship_size = 8.0
	var points = PackedVector2Array([
		screen_pos + Vector2(0, -ship_size),
		screen_pos + Vector2(-ship_size * 0.6, ship_size * 0.6),
		screen_pos + Vector2(ship_size * 0.6, ship_size * 0.6)
	])
	draw_colored_polygon(points, SHIP_COLOR)

	# Velocity vector
	if ship.orbit_state:
		var vel_dir = ship.orbit_state.velocity.normalized()
		var vel_screen = vel_dir * 20.0
		draw_line(screen_pos, screen_pos + vel_screen, Color.YELLOW, 1.0)


func _draw_offscreen_indicator(name: String, world_screen_pos: Vector2) -> void:
	## Draw an indicator pointing to an off-screen object
	var center = size / 2.0
	var direction = (world_screen_pos - center).normalized()
	var edge_pos = center + direction * minf(size.x, size.y) * 0.45

	draw_circle(edge_pos, 5, Color.RED)
	draw_string(ThemeDB.fallback_font, edge_pos + Vector2(8, 4), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.RED)


func _draw_scanlines() -> void:
	## Draw CRT scanline effect
	var y = 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, SCANLINE_ALPHA), 1.0)
		y += SCANLINE_SPACING


func _draw_vignette() -> void:
	## Draw corner darkening effect
	var center = size / 2.0
	var max_dist = center.length()

	# Draw radial gradient using concentric rectangles
	for i in range(10):
		var t = float(i) / 10.0
		var alpha = t * t * VIGNETTE_STRENGTH
		var margin = size * (1.0 - t) * 0.5
		var rect = Rect2(margin, size - margin * 2)
		draw_rect(rect, Color(0, 0, 0, alpha), false, 2.0)


func _draw_info_panel() -> void:
	## Draw orbital information panel
	var panel_pos = Vector2(10, 10)
	var line_height = 16

	# Time
	draw_string(ThemeDB.fallback_font, panel_pos, "Time: " + TimeManager.get_formatted_time(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT_COLOR)
	panel_pos.y += line_height

	# Time warp
	var warp_color = Color.YELLOW if TimeManager.warp_multiplier > 1 else TEXT_COLOR
	draw_string(ThemeDB.fallback_font, panel_pos, "Warp: " + TimeManager.get_formatted_warp(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, warp_color)
	panel_pos.y += line_height * 2

	# Ship info
	if player_ship and player_ship.orbit_state:
		var orbit = player_ship.orbit_state

		draw_string(ThemeDB.fallback_font, panel_pos, "--- ORBIT ---", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Alt: " + OrbitalConstantsClass.format_distance(orbit.current_altitude - player_ship.parent_body.radius), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Vel: " + OrbitalConstantsClass.format_velocity(orbit.current_speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Ap: " + OrbitalConstantsClass.format_distance(orbit.apoapsis - player_ship.parent_body.radius), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Pe: " + OrbitalConstantsClass.format_distance(orbit.periapsis - player_ship.parent_body.radius), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Period: " + OrbitalConstantsClass.format_time(orbit.orbital_period), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height * 2

		draw_string(ThemeDB.fallback_font, panel_pos, "--- SHIP ---", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Fuel: %.0f kg" % player_ship.fuel_mass, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		panel_pos.y += line_height

		draw_string(ThemeDB.fallback_font, panel_pos, "Delta-v: " + OrbitalConstantsClass.format_velocity(player_ship.delta_v_remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)

		# Thrust indicator
		if player_ship.is_thrusting:
			panel_pos.y += line_height * 2
			draw_string(ThemeDB.fallback_font, panel_pos, "THRUSTING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.ORANGE)


func _on_player_ship_changed(ship: Node) -> void:
	player_ship = ship as Ship
	if maneuver_interaction:
		maneuver_interaction.set_ship(player_ship)


func _on_focus_changed(body: Node) -> void:
	selected_body = body


func _on_maneuver_modified(_maneuver: ManeuverNode) -> void:
	## Called when a maneuver is modified via drag handles
	queue_redraw()


# === Plan Route Button ===

const BUTTON_WIDTH := 100.0
const BUTTON_HEIGHT := 28.0
const BUTTON_MARGIN := 10.0

func _get_plan_route_button_rect() -> Rect2:
	return Rect2(size.x - BUTTON_WIDTH - BUTTON_MARGIN, BUTTON_MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT)


func _draw_plan_route_button() -> void:
	## Draw the PLAN ROUTE button
	var rect = _get_plan_route_button_rect()

	# Button background
	var bg_color = Color(0.0, 0.25, 0.0, 0.8)
	draw_rect(rect, bg_color)

	# Button border
	draw_rect(rect, BODY_COLOR, false, 1.5)

	# Button text
	var text_pos = rect.position + Vector2(rect.size.x / 2 - 35, rect.size.y / 2 + 4)
	draw_string(ThemeDB.fallback_font, text_pos, "PLAN ROUTE", HORIZONTAL_ALIGNMENT_CENTER, 70, 11, TEXT_COLOR)


func _is_point_in_plan_route_button(point: Vector2) -> bool:
	return _get_plan_route_button_rect().has_point(point)


func _open_navigation_planner() -> void:
	## Open the navigation planner window
	if navigation_planner and player_ship:
		navigation_planner.open(player_ship)


func _on_maneuvers_created(plan: TrajectoryPlanner.ManeuverPlan) -> void:
	## Called when navigation planner creates maneuvers
	if plan.maneuvers.size() > 0 and maneuver_interaction:
		# Select the first maneuver
		maneuver_interaction.select_maneuver(plan.maneuvers[0])


func _on_navigation_planner_closed() -> void:
	## Called when navigation planner is closed
	pass
