class_name NavigationPlanner
extends Control
## Simplified Navigation Computer for planning orbital maneuvers
## Uses preset buttons for common maneuvers - more intuitive and educational

signal maneuvers_created(plan: TrajectoryPlanner.ManeuverPlan)
signal closed()

# === CRT Visual Style ===
const PANEL_BG_COLOR := Color(0.02, 0.06, 0.03, 0.95)
const BORDER_COLOR := Color(0.0, 0.5, 0.0, 1.0)
const TEXT_COLOR := Color(0.0, 0.9, 0.0, 1.0)
const HIGHLIGHT_COLOR := Color(0.0, 1.0, 0.0, 1.0)
const BUTTON_BG_COLOR := Color(0.0, 0.2, 0.0, 0.8)
const SECTION_COLOR := Color(0.0, 0.7, 0.0, 1.0)
const WARNING_COLOR := Color(1.0, 0.5, 0.0, 1.0)

# === State ===
var ship: Ship = null
var selected_target: Planet = null
var transfer_info: Dictionary = {}  # Cached transfer calculation
var auto_pause: bool = true

# === Button Rects (calculated in _draw) ===
var button_rects: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(340, 480)


func _draw() -> void:
	if not visible:
		return

	button_rects.clear()
	var rect = Rect2(Vector2.ZERO, size)

	# Background
	draw_rect(rect, PANEL_BG_COLOR)
	draw_rect(rect, BORDER_COLOR, false, 2.0)

	# Title bar
	var title_rect = Rect2(0, 0, size.x, 35)
	draw_rect(title_rect, BORDER_COLOR.darkened(0.3))
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 70, 24), "NAVIGATION COMPUTER",
		HORIZONTAL_ALIGNMENT_CENTER, 140, 14, HIGHLIGHT_COLOR)
	draw_line(Vector2(0, 35), Vector2(size.x, 35), BORDER_COLOR, 1.0)

	var y = 50.0

	# === ORBIT ADJUSTMENTS SECTION ===
	draw_string(ThemeDB.fallback_font, Vector2(15, y), "ORBIT ADJUSTMENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SECTION_COLOR)
	y += 20

	# Current orbit info
	if ship and ship.orbit_state:
		var orbit = ship.orbit_state
		var ap_alt = orbit.apoapsis - ship.parent_body.radius
		var pe_alt = orbit.periapsis - ship.parent_body.radius
		draw_string(ThemeDB.fallback_font, Vector2(20, y + 12),
			"Ap: %s  Pe: %s" % [OrbitalConstantsClass.format_distance(ap_alt), OrbitalConstantsClass.format_distance(pe_alt)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.2))
		y += 20

	# Circularize buttons (side by side)
	y += 5
	var half_width = (size.x - 40) / 2
	_draw_button("circ_ap", Rect2(15, y, half_width - 5, 32), "Circularize @ Ap")
	_draw_button("circ_pe", Rect2(20 + half_width, y, half_width - 5, 32), "Circularize @ Pe")
	y += 42

	# Raise/Lower Apoapsis
	_draw_button("raise_ap", Rect2(15, y, half_width - 5, 28), "Raise Ap +100km")
	_draw_button("lower_ap", Rect2(20 + half_width, y, half_width - 5, 28), "Lower Ap -100km")
	y += 35

	# Raise/Lower Periapsis
	_draw_button("raise_pe", Rect2(15, y, half_width - 5, 28), "Raise Pe +100km")
	_draw_button("lower_pe", Rect2(20 + half_width, y, half_width - 5, 28), "Lower Pe -100km")
	y += 45

	# === PLANET TRANSFERS SECTION ===
	draw_line(Vector2(10, y), Vector2(size.x - 10, y), BORDER_COLOR.darkened(0.5), 1.0)
	y += 15
	draw_string(ThemeDB.fallback_font, Vector2(15, y), "PLANET TRANSFER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SECTION_COLOR)
	y += 25

	# Target selection
	draw_string(ThemeDB.fallback_font, Vector2(20, y), "Target:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y += 5
	_draw_target_buttons(y)
	y += 38

	# Transfer info (if target selected)
	if selected_target != null:
		y += 5
		if transfer_info.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(20, y + 12), "Calculating...", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.5))
		else:
			# Show transfer details
			draw_string(ThemeDB.fallback_font, Vector2(20, y + 12),
				"To: %s" % selected_target.body_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HIGHLIGHT_COLOR)
			y += 18

			var total_dv = transfer_info.get("total_dv", 0.0)
			var transfer_time = transfer_info.get("transfer_time", 0.0)

			draw_string(ThemeDB.fallback_font, Vector2(20, y + 12),
				"Delta-V: %.2f km/s" % (total_dv / 1000.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
			y += 16

			draw_string(ThemeDB.fallback_font, Vector2(20, y + 12),
				"Travel time: %s" % OrbitalConstantsClass.format_time(transfer_time),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
			y += 20

			# Transfer button
			_draw_button("transfer", Rect2(15, y, size.x - 30, 32), "CREATE TRANSFER", true)
			y += 40
	else:
		y += 15
		draw_string(ThemeDB.fallback_font, Vector2(20, y), "Select a target planet", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.5))
		y += 25

	# === CLOSE BUTTON ===
	var close_y = size.y - 45
	draw_line(Vector2(0, close_y - 10), Vector2(size.x, close_y - 10), BORDER_COLOR.darkened(0.5), 1.0)
	_draw_button("close", Rect2(15, close_y, size.x - 30, 35), "CLOSE")


func _draw_button(id: String, rect: Rect2, label: String, highlight: bool = false) -> void:
	## Draw a button and store its rect for click detection
	button_rects[id] = rect

	var bg_color = HIGHLIGHT_COLOR.darkened(0.6) if highlight else BUTTON_BG_COLOR
	var border = HIGHLIGHT_COLOR if highlight else BORDER_COLOR
	var text_color = HIGHLIGHT_COLOR if highlight else TEXT_COLOR

	draw_rect(rect, bg_color)
	draw_rect(rect, border, false, 1.5)

	var text_width = label.length() * 6
	var text_x = rect.position.x + (rect.size.x - text_width) / 2
	var text_y = rect.position.y + rect.size.y / 2 + 4
	draw_string(ThemeDB.fallback_font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, text_color)


func _draw_target_buttons(y_start: float) -> void:
	## Draw planet selection buttons
	var planets = _get_available_targets()
	if planets.size() == 0:
		draw_string(ThemeDB.fallback_font, Vector2(20, y_start + 15), "No targets available", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.5))
		return

	var button_width = 42.0
	var button_height = 22.0
	var spacing = 4.0
	var x = 20.0

	for planet in planets:
		var is_selected = selected_target == planet
		var rect = Rect2(x, y_start, button_width, button_height)

		var bg_color = HIGHLIGHT_COLOR.darkened(0.6) if is_selected else BUTTON_BG_COLOR
		var border = HIGHLIGHT_COLOR if is_selected else BORDER_COLOR.darkened(0.3)
		var text_color = HIGHLIGHT_COLOR if is_selected else TEXT_COLOR

		draw_rect(rect, bg_color)
		draw_rect(rect, border, false, 1.0)

		var label = _shorten_planet_name(planet.body_name)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, text_color)

		button_rects["target_" + planet.body_name] = rect
		x += button_width + spacing


func _get_available_targets() -> Array:
	## Get planets we can transfer to
	var planets = []
	var bodies = GameManager.get_all_celestial_bodies()
	var exclude = ship.parent_body if ship else null

	for body in bodies:
		if body is Planet and body != exclude:
			# Only include planets orbiting the Sun (for now)
			if body.parent_body and body.parent_body.body_name == "Sun":
				planets.append(body)

	return planets


func _shorten_planet_name(name: String) -> String:
	match name:
		"Mercury": return "MER"
		"Venus": return "VEN"
		"Earth": return "EAR"
		"Mars": return "MAR"
		"Jupiter": return "JUP"
		"Saturn": return "SAT"
		"Uranus": return "URA"
		"Neptune": return "NEP"
		_: return name.substr(0, 3).to_upper()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click(event.position)
			accept_event()

	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:
			close()
			accept_event()


func _handle_click(pos: Vector2) -> void:
	## Handle click on buttons
	for id in button_rects:
		if button_rects[id].has_point(pos):
			_on_button_pressed(id)
			return


func _on_button_pressed(id: String) -> void:
	## Handle button press
	match id:
		"close":
			close()

		"circ_ap":
			_create_circularize(true)

		"circ_pe":
			_create_circularize(false)

		"raise_ap":
			_create_change_apoapsis(100000.0)  # +100km

		"lower_ap":
			_create_change_apoapsis(-100000.0)  # -100km

		"raise_pe":
			_create_change_periapsis(100000.0)  # +100km

		"lower_pe":
			_create_change_periapsis(-100000.0)  # -100km

		"transfer":
			_create_transfer()

		_:
			# Check for target buttons
			if id.begins_with("target_"):
				var planet_name = id.substr(7)
				_select_target_by_name(planet_name)


func _select_target_by_name(planet_name: String) -> void:
	var planets = _get_available_targets()
	for planet in planets:
		if planet.body_name == planet_name:
			selected_target = planet
			_calculate_transfer()
			queue_redraw()
			return


func _calculate_transfer() -> void:
	## Calculate immediate transfer to selected target
	if ship == null or selected_target == null:
		transfer_info = {}
		return

	# Use simplified "transfer now" calculation
	transfer_info = TransferCalculator.calculate_immediate_transfer(ship, selected_target)


func _create_circularize(at_apoapsis: bool) -> void:
	if ship == null:
		return

	var plan = TrajectoryPlanner.plan_circularize(ship, at_apoapsis)
	if plan != null and plan.is_valid:
		maneuvers_created.emit(plan)
		close()
	else:
		push_warning("Failed to create circularize maneuver")


func _create_change_apoapsis(delta_altitude: float) -> void:
	if ship == null or ship.orbit_state == null:
		return

	var new_ap = ship.orbit_state.apoapsis + delta_altitude
	# Don't go below periapsis
	if new_ap < ship.orbit_state.periapsis + 10000:
		new_ap = ship.orbit_state.periapsis + 10000

	var plan = TrajectoryPlanner.plan_change_apoapsis(ship, new_ap)
	if plan != null and plan.is_valid:
		maneuvers_created.emit(plan)
		close()
	else:
		push_warning("Failed to create change apoapsis maneuver")


func _create_change_periapsis(delta_altitude: float) -> void:
	if ship == null or ship.orbit_state == null:
		return

	var new_pe = ship.orbit_state.periapsis + delta_altitude
	# Don't go below surface
	var min_pe = ship.parent_body.radius + 50000  # 50km minimum altitude
	if new_pe < min_pe:
		new_pe = min_pe
	# Don't go above apoapsis
	if new_pe > ship.orbit_state.apoapsis - 10000:
		new_pe = ship.orbit_state.apoapsis - 10000

	var plan = TrajectoryPlanner.plan_change_periapsis(ship, new_pe)
	if plan != null and plan.is_valid:
		maneuvers_created.emit(plan)
		close()
	else:
		push_warning("Failed to create change periapsis maneuver")


func _create_transfer() -> void:
	if ship == null or selected_target == null or transfer_info.is_empty():
		return

	# Create transfer using immediate calculation
	var plan = TrajectoryPlanner.plan_immediate_transfer(ship, selected_target, transfer_info)
	if plan != null and plan.is_valid:
		maneuvers_created.emit(plan)
		close()
	else:
		push_warning("Failed to create transfer maneuver")


func open(p_ship: Ship) -> void:
	## Open the navigation planner for a ship
	ship = p_ship
	selected_target = null
	transfer_info = {}

	if auto_pause:
		TimeManager.pause()

	visible = true
	queue_redraw()

	# Center in parent
	if get_parent() is Control:
		var parent_size = (get_parent() as Control).size
		position = (parent_size - size) / 2


func close() -> void:
	## Close the navigation planner
	visible = false

	if auto_pause:
		TimeManager.resume()

	closed.emit()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
