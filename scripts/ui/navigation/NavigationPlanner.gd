class_name NavigationPlanner
extends Control
## Navigation Computer popup window for planning interplanetary transfers
## and orbital maneuvers

signal maneuvers_created(plan: TrajectoryPlanner.ManeuverPlan)
signal closed()

# === CRT Visual Style ===
const PANEL_BG_COLOR := Color(0.02, 0.06, 0.03, 0.95)
const BORDER_COLOR := Color(0.0, 0.5, 0.0, 1.0)
const TEXT_COLOR := Color(0.0, 0.9, 0.0, 1.0)
const HIGHLIGHT_COLOR := Color(0.0, 1.0, 0.0, 1.0)
const BUTTON_BG_COLOR := Color(0.0, 0.2, 0.0, 0.8)
const BUTTON_HOVER_COLOR := Color(0.0, 0.3, 0.0, 0.9)
const WINDOW_COLOR := Color(0.0, 0.8, 0.0, 1.0)
const FLYBY_COLOR := Color(1.0, 0.8, 0.0, 1.0)  # Gold/amber for flyby indicators

# === State ===
enum Goal { TRANSFER, CIRCULARIZE_AP, CIRCULARIZE_PE, RAISE_AP, LOWER_AP, RAISE_PE, LOWER_PE }

var current_goal: Goal = Goal.TRANSFER
var selected_target: Planet = null
var selected_window: TransferCalculator.TransferWindow = null
var transfer_windows: Array[TransferCalculator.TransferWindow] = []
var auto_pause: bool = true

# === References ===
var ship: Ship = null

# === UI Elements (created in code for CRT style) ===
var goal_buttons: Array[Button] = []
var target_buttons: Array[Button] = []
var window_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Center the window
	custom_minimum_size = Vector2(450, 620)


func _draw() -> void:
	if not visible:
		return

	var rect = Rect2(Vector2.ZERO, size)

	# Background
	draw_rect(rect, PANEL_BG_COLOR)

	# Border
	draw_rect(rect, BORDER_COLOR, false, 2.0)

	# Title bar
	var title_rect = Rect2(0, 0, size.x, 35)
	draw_rect(title_rect, BORDER_COLOR.darkened(0.3))
	draw_string(ThemeDB.fallback_font, Vector2(size.x / 2 - 80, 24), "NAVIGATION COMPUTER",
		HORIZONTAL_ALIGNMENT_CENTER, 160, 14, WINDOW_COLOR)

	# Draw separator lines
	draw_line(Vector2(0, 35), Vector2(size.x, 35), BORDER_COLOR, 1.0)
	draw_line(Vector2(0, 120), Vector2(size.x, 120), BORDER_COLOR.darkened(0.5), 1.0)

	# Goal section header
	draw_string(ThemeDB.fallback_font, Vector2(15, 55), "GOAL:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)

	# Draw goal buttons
	_draw_goal_buttons()

	# Draw content based on goal
	if current_goal == Goal.TRANSFER:
		_draw_transfer_ui()
	else:
		_draw_adjustment_ui()

	# Bottom buttons area
	draw_line(Vector2(0, size.y - 50), Vector2(size.x, size.y - 50), BORDER_COLOR.darkened(0.5), 1.0)
	_draw_bottom_buttons()


func _draw_goal_buttons() -> void:
	## Draw the goal selection buttons
	var goals = [
		{"goal": Goal.TRANSFER, "label": "TRANSFER"},
		{"goal": Goal.CIRCULARIZE_AP, "label": "CIRC @ AP"},
		{"goal": Goal.CIRCULARIZE_PE, "label": "CIRC @ PE"}
	]

	var button_width = (size.x - 40) / 3
	var button_height = 28.0
	var start_x = 15.0
	var start_y = 65.0

	for i in range(goals.size()):
		var goal_data = goals[i]
		var is_selected = current_goal == goal_data.goal
		var rect = Rect2(start_x + i * (button_width + 5), start_y, button_width, button_height)

		# Button background
		var bg_color = HIGHLIGHT_COLOR.darkened(0.6) if is_selected else BUTTON_BG_COLOR
		draw_rect(rect, bg_color)

		# Button border
		var border_color = HIGHLIGHT_COLOR if is_selected else BORDER_COLOR
		draw_rect(rect, border_color, false, 1.5)

		# Button text
		var text_color = HIGHLIGHT_COLOR if is_selected else TEXT_COLOR
		var text_pos = rect.position + Vector2(rect.size.x / 2 - 30, rect.size.y / 2 + 4)
		draw_string(ThemeDB.fallback_font, text_pos, goal_data.label, HORIZONTAL_ALIGNMENT_CENTER, 60, 10, text_color)


func _draw_bottom_buttons() -> void:
	## Draw Cancel and Create Maneuvers buttons
	var button_height = 35.0
	var button_y = size.y - 45

	# Cancel button (left half)
	var cancel_rect = Rect2(15, button_y, size.x / 2 - 25, button_height)
	draw_rect(cancel_rect, BUTTON_BG_COLOR)
	draw_rect(cancel_rect, BORDER_COLOR, false, 1.5)
	draw_string(ThemeDB.fallback_font, cancel_rect.position + Vector2(cancel_rect.size.x / 2 - 25, 22), "CANCEL", HORIZONTAL_ALIGNMENT_CENTER, 50, 11, TEXT_COLOR)

	# Create button (right half) - only enabled if we have a valid selection
	var can_create = (current_goal == Goal.TRANSFER and selected_window != null) or (current_goal != Goal.TRANSFER)
	var create_rect = Rect2(size.x / 2 + 10, button_y, size.x / 2 - 25, button_height)
	var create_bg = HIGHLIGHT_COLOR.darkened(0.6) if can_create else BUTTON_BG_COLOR.darkened(0.5)
	var create_text = HIGHLIGHT_COLOR if can_create else TEXT_COLOR.darkened(0.5)

	draw_rect(create_rect, create_bg)
	draw_rect(create_rect, BORDER_COLOR if can_create else BORDER_COLOR.darkened(0.5), false, 1.5)
	draw_string(ThemeDB.fallback_font, create_rect.position + Vector2(create_rect.size.x / 2 - 50, 22), "CREATE MANEUVERS", HORIZONTAL_ALIGNMENT_CENTER, 100, 11, create_text)


func _draw_target_buttons(y_start: float) -> void:
	## Draw the target planet selection buttons
	var exclude_body = ship.parent_body if ship else null
	var planets = TransferCalculator.get_available_targets(exclude_body)
	if planets.size() == 0:
		draw_string(ThemeDB.fallback_font, Vector2(15, y_start + 20), "No targets available", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.5))
		return

	var button_width = 52.0
	var button_height = 24.0
	var buttons_per_row = 7
	var start_x = 15.0
	var row_y = y_start + 8

	for i in range(planets.size()):
		var planet = planets[i]
		var col = i % buttons_per_row
		var row = i / buttons_per_row

		var is_selected = selected_target == planet
		var rect = Rect2(start_x + col * (button_width + 4), row_y + row * (button_height + 4), button_width, button_height)

		# Button background
		var bg_color = HIGHLIGHT_COLOR.darkened(0.6) if is_selected else BUTTON_BG_COLOR
		draw_rect(rect, bg_color)

		# Button border
		var border_color = HIGHLIGHT_COLOR if is_selected else BORDER_COLOR.darkened(0.3)
		draw_rect(rect, border_color, false, 1.0)

		# Planet name (shortened)
		var label = _shorten_planet_name(planet.body_name)
		var text_color = HIGHLIGHT_COLOR if is_selected else TEXT_COLOR
		var text_pos = rect.position + Vector2(rect.size.x / 2 - 18, rect.size.y / 2 + 4)
		draw_string(ThemeDB.fallback_font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 40, 9, text_color)


func _shorten_planet_name(name: String) -> String:
	## Shorten planet names to fit in buttons
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


func _draw_transfer_ui() -> void:
	## Draw the interplanetary transfer interface
	var y_offset = 125.0

	# Target section
	draw_string(ThemeDB.fallback_font, Vector2(15, y_offset), "TARGET:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)

	# Draw target planet buttons
	_draw_target_buttons(y_offset + 5)
	y_offset += 60

	# Transfer windows section
	if selected_target != null:
		draw_line(Vector2(0, y_offset), Vector2(size.x, y_offset), BORDER_COLOR.darkened(0.5), 1.0)
		y_offset += 5
		draw_string(ThemeDB.fallback_font, Vector2(15, y_offset + 15), "TRANSFER WINDOWS to %s:" % selected_target.body_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HIGHLIGHT_COLOR)
		y_offset += 30

		# Window list header
		draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12), "Depart", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.3))
		draw_string(ThemeDB.fallback_font, Vector2(110, y_offset + 12), "Arrive", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.3))
		draw_string(ThemeDB.fallback_font, Vector2(200, y_offset + 12), "Delta-V", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.3))
		draw_string(ThemeDB.fallback_font, Vector2(285, y_offset + 12), "Time", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.3))
		draw_string(ThemeDB.fallback_font, Vector2(345, y_offset + 12), "Flyby", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.3))
		y_offset += 20

		if transfer_windows.size() == 0:
			draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12), "Calculating...", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR.darkened(0.5))
		else:
			# Windows
			for i in range(min(transfer_windows.size(), 5)):
				var window = transfer_windows[i]
				var is_selected = window == selected_window
				var row_color = HIGHLIGHT_COLOR if is_selected else TEXT_COLOR

				if is_selected:
					draw_rect(Rect2(10, y_offset - 2, size.x - 20, 22), BUTTON_BG_COLOR)

				draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
					"Day %d" % int(window.departure_time / OrbitalConstantsClass.SECONDS_PER_DAY),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, row_color)
				draw_string(ThemeDB.fallback_font, Vector2(110, y_offset + 12),
					"Day %d" % int(window.arrival_time / OrbitalConstantsClass.SECONDS_PER_DAY),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, row_color)
				draw_string(ThemeDB.fallback_font, Vector2(200, y_offset + 12),
					"%.2f km/s" % (window.total_dv / 1000.0),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, row_color)
				draw_string(ThemeDB.fallback_font, Vector2(285, y_offset + 12),
					"%dd" % int(window.transfer_time / OrbitalConstantsClass.SECONDS_PER_DAY),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, row_color)

				# Show flyby indicator if available
				if window.has_viable_flybys():
					var best_flyby = window.get_best_flyby()
					var flyby_text = _shorten_planet_name(best_flyby.planet_name)
					draw_string(ThemeDB.fallback_font, Vector2(345, y_offset + 12),
						flyby_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FLYBY_COLOR)
				else:
					draw_string(ThemeDB.fallback_font, Vector2(345, y_offset + 12),
						"-", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR.darkened(0.5))

				y_offset += 22
	else:
		y_offset += 10
		draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12), "Select a target planet above", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR.darkened(0.5))

	# Selected transfer summary
	if selected_window != null:
		y_offset = size.y - 180  # Move up to make room for 3-phase display
		draw_line(Vector2(0, y_offset), Vector2(size.x, y_offset), BORDER_COLOR.darkened(0.5), 1.0)
		y_offset += 10

		draw_string(ThemeDB.fallback_font, Vector2(15, y_offset + 12), "SELECTED TRANSFER:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HIGHLIGHT_COLOR)
		y_offset += 20

		var info_text = "%s → %s" % [selected_window.origin_name, selected_window.target_name]
		draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
		y_offset += 16

		draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
			"Transfer Time: %s" % OrbitalConstantsClass.format_time(selected_window.transfer_time),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
		y_offset += 16

		# Show 3-phase breakdown for patched conic transfers
		if selected_window.is_patched_conic and selected_window.patched_conic != null:
			var pc = selected_window.patched_conic

			# Phase 1: Escape
			draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
				"1. ESCAPE: %.2f km/s (v∞=%.1f km/s)" % [pc.escape_dv / 1000.0, pc.escape_v_infinity / 1000.0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 1.0, 0.4))
			y_offset += 14

			# Phase 2: Coast
			draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
				"2. COAST: %s" % OrbitalConstantsClass.format_time(pc.transfer_time),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR.darkened(0.2))
			y_offset += 14

			# Phase 3: Capture
			draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
				"3. CAPTURE: %.2f km/s (v∞=%.1f km/s)" % [pc.capture_dv / 1000.0, pc.capture_v_infinity / 1000.0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.6, 0.4))
			y_offset += 16

		# Total delta-v
		draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
			"Total ΔV: %.2f km/s" % (selected_window.total_dv / 1000.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HIGHLIGHT_COLOR)

		# Show flyby opportunities if any
		if selected_window.has_viable_flybys():
			y_offset += 18
			draw_string(ThemeDB.fallback_font, Vector2(15, y_offset + 12), "FLYBY ASSIST:", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FLYBY_COLOR)
			y_offset += 14

			for flyby in selected_window.flyby_opportunities:
				if flyby.is_viable:
					var flyby_text = "%s: ΔV savings ~%.0f m/s" % [flyby.planet_name, flyby.dv_benefit]
					draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12), flyby_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, FLYBY_COLOR.darkened(0.2))
					y_offset += 12


func _draw_adjustment_ui() -> void:
	## Draw the orbital adjustment interface
	var y_offset = 130.0

	if ship == null or ship.orbit_state == null:
		draw_string(ThemeDB.fallback_font, Vector2(15, y_offset), "No ship orbit data", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.RED)
		return

	var orbit = ship.orbit_state

	# Current orbit info
	draw_string(ThemeDB.fallback_font, Vector2(15, y_offset), "CURRENT ORBIT:", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
	y_offset += 20

	draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
		"Apoapsis: %s" % OrbitalConstantsClass.format_distance(orbit.apoapsis),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
	y_offset += 18

	draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
		"Periapsis: %s" % OrbitalConstantsClass.format_distance(orbit.periapsis),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
	y_offset += 18

	draw_string(ThemeDB.fallback_font, Vector2(20, y_offset + 12),
		"Period: %s" % OrbitalConstantsClass.format_time(orbit.orbital_period),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEXT_COLOR)
	y_offset += 30

	# Maneuver preview
	var goal_name = _get_goal_name(current_goal)
	draw_string(ThemeDB.fallback_font, Vector2(15, y_offset + 12),
		"MANEUVER: %s" % goal_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HIGHLIGHT_COLOR)


func _get_goal_name(goal: Goal) -> String:
	match goal:
		Goal.TRANSFER: return "Transfer to Planet"
		Goal.CIRCULARIZE_AP: return "Circularize at Apoapsis"
		Goal.CIRCULARIZE_PE: return "Circularize at Periapsis"
		Goal.RAISE_AP: return "Raise Apoapsis"
		Goal.LOWER_AP: return "Lower Apoapsis"
		Goal.RAISE_PE: return "Raise Periapsis"
		Goal.LOWER_PE: return "Lower Periapsis"
		_: return "Unknown"


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
	## Handle click within the window
	# Check goal buttons (y: 65-93)
	if pos.y >= 65 and pos.y <= 95:
		var goals = [Goal.TRANSFER, Goal.CIRCULARIZE_AP, Goal.CIRCULARIZE_PE]
		var button_width = (size.x - 40) / 3
		var index = int((pos.x - 15) / (button_width + 5))
		if index >= 0 and index < goals.size():
			_select_goal(goals[index])
			return

	# Check target buttons (for transfer goal) - y: 138-175
	if current_goal == Goal.TRANSFER and pos.y >= 138 and pos.y <= 175:
		var exclude_body = ship.parent_body if ship else null
		var planets = TransferCalculator.get_available_targets(exclude_body)
		var button_width = 52.0
		var button_height = 24.0
		var buttons_per_row = 7
		var start_x = 15.0
		var row_y = 138.0

		for i in range(planets.size()):
			var col = i % buttons_per_row
			var row = i / buttons_per_row
			var rect = Rect2(start_x + col * (button_width + 4), row_y + row * (button_height + 4), button_width, button_height)

			if rect.has_point(pos):
				_select_target(planets[i])
				return

	# Check window selection (y starts at ~240 after headers)
	if current_goal == Goal.TRANSFER and selected_target != null:
		var window_start_y = 240.0
		var window_height = 22.0
		if pos.y >= window_start_y and pos.y <= window_start_y + window_height * 5:
			var index = int((pos.y - window_start_y) / window_height)
			if index >= 0 and index < transfer_windows.size():
				_select_window(transfer_windows[index])
				return

	# Check bottom buttons
	if pos.y >= size.y - 50:
		if pos.x < size.x / 2:
			# Cancel button
			close()
		else:
			# Create maneuvers button
			var can_create = (current_goal == Goal.TRANSFER and selected_window != null) or (current_goal != Goal.TRANSFER)
			if can_create:
				_create_maneuvers()


func _select_goal(goal: Goal) -> void:
	current_goal = goal
	selected_target = null
	selected_window = null
	transfer_windows.clear()
	queue_redraw()


func _select_target(target: Planet) -> void:
	selected_target = target
	selected_window = null
	_calculate_windows()
	queue_redraw()


func _select_window(window: TransferCalculator.TransferWindow) -> void:
	selected_window = window
	queue_redraw()


func _calculate_windows() -> void:
	## Calculate transfer windows to the selected target
	if ship == null or selected_target == null:
		return

	# Check what the ship is orbiting
	var sun = GameManager.get_sun()
	var ship_parent = ship.parent_body

	if ship_parent == sun or (ship_parent != null and ship_parent.body_name == "Sun"):
		# Ship is in heliocentric orbit - use simple calculation
		transfer_windows = TransferCalculator.calculate_transfer_from_ship(ship, selected_target, 5)
	else:
		# Ship is orbiting a planet - use patched conic calculation
		# This accounts for escape and capture burns
		transfer_windows = TransferCalculator.calculate_patched_conic_windows(ship, selected_target, 5)


func _create_maneuvers() -> void:
	## Create the planned maneuvers
	if ship == null:
		return

	var plan: TrajectoryPlanner.ManeuverPlan

	match current_goal:
		Goal.TRANSFER:
			if selected_window != null and selected_target != null:
				plan = TrajectoryPlanner.plan_transfer_to_planet(ship, selected_target, selected_window)

		Goal.CIRCULARIZE_AP:
			plan = TrajectoryPlanner.plan_circularize(ship, true)

		Goal.CIRCULARIZE_PE:
			plan = TrajectoryPlanner.plan_circularize(ship, false)

		# TODO: Implement other goals with altitude input
		_:
			push_warning("Goal not yet implemented: %s" % _get_goal_name(current_goal))
			return

	if plan != null and plan.is_valid:
		maneuvers_created.emit(plan)
		close()
	else:
		push_warning("Failed to create maneuvers: %s" % (plan.error_message if plan else "Unknown error"))


func open(p_ship: Ship) -> void:
	## Open the navigation planner for a ship
	ship = p_ship
	current_goal = Goal.TRANSFER
	selected_target = null
	selected_window = null
	transfer_windows.clear()

	# Pause if auto-pause is enabled
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

	# Resume if we paused
	if auto_pause:
		TimeManager.resume()

	closed.emit()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
