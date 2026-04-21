class_name ControlsPanel
extends Control
## On-screen controls reference panel
## Shows current keybinds with CRT aesthetic

# === Visual Settings ===
const BACKGROUND_COLOR := Color(0.01, 0.04, 0.02, 0.85)
const BORDER_COLOR := Color(0.0, 0.5, 0.0, 0.8)
const TEXT_COLOR := Color(0.0, 0.9, 0.0, 1.0)
const HEADER_COLOR := Color(0.0, 0.7, 0.0, 1.0)
const HIGHLIGHT_COLOR := Color(0.9, 0.5, 0.0, 1.0)

const PANEL_WIDTH := 150.0
const PANEL_PADDING := 8.0
const LINE_HEIGHT := 14.0
const HEADER_HEIGHT := 20.0

# === State ===
var is_collapsed: bool = false


func _gui_input(event: InputEvent) -> void:
	# Click header to toggle collapsed state
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var header_rect = Rect2(Vector2.ZERO, Vector2(PANEL_WIDTH, HEADER_HEIGHT))
			if header_rect.has_point(event.position):
				is_collapsed = not is_collapsed
				queue_redraw()
				accept_event()


func _draw() -> void:
	var panel_height = _calculate_panel_height()

	# Background
	var panel_rect = Rect2(Vector2.ZERO, Vector2(PANEL_WIDTH, panel_height))
	draw_rect(panel_rect, BACKGROUND_COLOR)

	# Border
	draw_rect(panel_rect, BORDER_COLOR, false, 1.5)

	# Header
	var header_text = "[CONTROLS]" if not is_collapsed else "[CONTROLS] +"
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, HEADER_HEIGHT - 5), header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HEADER_COLOR)

	if is_collapsed:
		return

	# Separator line
	var y_pos = HEADER_HEIGHT + 2
	draw_line(Vector2(PANEL_PADDING, y_pos), Vector2(PANEL_WIDTH - PANEL_PADDING, y_pos), BORDER_COLOR, 1.0)
	y_pos += 8

	# Flight Controls
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "Q/E      Rotate", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y_pos += LINE_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "Space    Main engine", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HIGHLIGHT_COLOR)
	y_pos += LINE_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "W/S      Throttle/RCS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y_pos += LINE_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "A/D      RCS strafe", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y_pos += LINE_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "T        Toggle SAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y_pos += LINE_HEIGHT + 4

	# Separator
	draw_line(Vector2(PANEL_PADDING, y_pos), Vector2(PANEL_WIDTH - PANEL_PADDING, y_pos), BORDER_COLOR, 1.0)
	y_pos += 8

	# Navigation
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "N        Nav planner", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y_pos += LINE_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), ",/.      Time warp", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)
	y_pos += LINE_HEIGHT
	draw_string(ThemeDB.fallback_font, Vector2(PANEL_PADDING, y_pos + LINE_HEIGHT), "Scroll   Zoom", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT_COLOR)


func _calculate_panel_height() -> float:
	if is_collapsed:
		return HEADER_HEIGHT

	# Header + separator + flight controls (6) + separator + nav controls (3) + padding
	return HEADER_HEIGHT + 8 + (6 * LINE_HEIGHT) + 12 + (3 * LINE_HEIGHT) + PANEL_PADDING
