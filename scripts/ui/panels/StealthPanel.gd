class_name StealthPanel
extends PanelContainer
## Displays current stealth status and ship signatures on cockpit HUD
## Shows thermal/radar/visual readings and stealth rating

@onready var stealth_rating_bar: ProgressBar = null
@onready var thermal_readout: Label = null
@onready var radar_readout: Label = null
@onready var visual_readout: Label = null
@onready var stealth_status_label: Label = null
@onready var mode_label: Label = null
@onready var signature_bars_container: HBoxContainer = null

var _stealth_manager: StealthManager = null
var _stealth_bar_segments: Array = []
var _update_interval: float = 0.1
var _update_timer: float = 0.0

func _ready() -> void:
	_setup_ui()
	_set_process(true)

func _setup_ui() -> void:
	# Style the panel
	add_theme_stylebox_override("panel", _create_panel_style())
	
	# Create vertical container
	var vbox = VBoxContainer.new()
	vbox.set("custom_constants/separation", 8)
	add_child(vbox)
	
	# Header
	var header = Label.new()
	header.text = "◆ STEALTH STATUS"
	header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(header)
	
	# Stealth status
	stealth_status_label = Label.new()
	stealth_status_label.text = "[ STEALTH ACTIVE ]"
	stealth_status_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.0, 1.0))
	vbox.add_child(stealth_status_label)
	
	# Stealth rating bar
	var rating_container = HBoxContainer.new()
	rating_container.set("custom_constants/separation", 4)
	
	var rating_label = Label.new()
	rating_label.text = "STEALTH:"
	vbox.add_child(rating_label)
	
	stealth_rating_bar = ProgressBar.new()
	stealth_rating_bar.min_value = 0.0
	stealth_rating_bar.max_value = 100.0
	stealth_rating_bar.value = 75.0
	stealth_rating_bar.custom_minimum_size = Vector2(150, 16)
	_setup_progress_bar_style(stealth_rating_bar, Color(0.0, 0.8, 0.3, 1.0))
	vbox.add_child(stealth_rating_bar)
	
	# Mode indicator
	mode_label = Label.new()
	mode_label.text = "MODE: COLD COAST"
	mode_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7, 1.0))
	vbox.add_child(mode_label)
	
	# Separator
	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(sep)
	
	# Signature readings
	var sig_header = Label.new()
	sig_header.text = "SIGNATURE OUTPUT"
	sig_header.add_theme_font_size_override("font_size", 12)
	vbox.add_child(sig_header)
	
	# Create signature bars
	signature_bars_container = HBoxContainer.new()
	signature_bars_container.set("custom_constants/separation", 12)
	vbox.add_child(signature_bars_container)
	
	thermal_readout = _create_signature_bar("THERMAL", Color(1.0, 0.3, 0.0, 1.0))
	radar_readout = _create_signature_bar("RADAR", Color(0.3, 0.8, 1.0, 1.0))
	visual_readout = _create_signature_bar("VISUAL", Color(0.8, 0.8, 0.3, 1.0))
	
	signature_bars_container.add_child(thermal_readout)
	signature_bars_container.add_child(radar_readout)
	signature_bars_container.add_child(visual_readout)

func _create_signature_bar(label_text: String, bar_color: Color) -> VBoxContainer:
	var container = VBoxContainer.new()
	container.set("custom_constants/separation", 2)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 9)
	container.add_child(label)
	
	var bar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 20.0
	bar.custom_minimum_size = Vector2(50, 10)
	_setup_progress_bar_style(bar, bar_color)
	container.add_child(bar)
	
	return container

func _create_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.05, 0.9)
	style.border_color = Color(0.0, 0.5, 0.2, 0.7)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style

func _setup_progress_bar_style(bar: ProgressBar, fill_color: Color) -> void:
	# These are set via theme overrides in Godot 4
	bar.set("custom_minimum_size", Vector2(50, 10))

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= _update_interval:
		_update_timer = 0.0
		_refresh_display()

func _refresh_display() -> void:
	if _stealth_manager == null:
		# Try to find stealth manager from ship
		_stealth_manager = find_stealth_manager()
		if _stealth_manager == null:
			return
	
	var signature = _stealth_manager.get_signature()
	if signature == null:
		return
	
	# Update stealth rating
	var rating = _stealth_manager.get_stealth_rating()
	stealth_rating_bar.value = rating * 100.0
	
	# Update status color based on stealth
	var status_color: Color
	if _stealth_manager.is_stealthy():
		status_color = Color(0.0, 1.0, 0.3, 1.0)
		stealth_status_label.text = "[ STEALTH ACTIVE ]"
	else:
		status_color = Color(1.0, 0.6, 0.0, 1.0)
		stealth_status_label.text = "[ ⚠ DETECTABLE ]"
	stealth_status_label.add_theme_color_override("font_color", status_color)
	
	# Update mode label
	if signature.is_cold_coasting:
		mode_label.text = "MODE: COLD COAST"
		mode_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.7, 1.0))
	elif signature.is_thrusting:
		mode_label.text = "MODE: ACTIVE BURN"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.0, 1.0))
	else:
		mode_label.text = "MODE: IDLE"
		mode_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	
	# Update signature bars (get bar at index 1, which is after the label)
	if thermal_readout.get_child_count() > 1:
		(thermal_readout.get_child(1) as ProgressBar).value = signature.thermal_signature * 100.0
	if radar_readout.get_child_count() > 1:
		(radar_readout.get_child(1) as ProgressBar).value = signature.radar_signature * 100.0
	if visual_readout.get_child_count() > 1:
		(visual_readout.get_child(1) as ProgressBar).value = signature.visual_signature * 100.0

func find_stealth_manager() -> StealthManager:
	# Search in parent tree for a node with stealth manager
	var parent = get_parent()
	while parent:
		if parent.has_method("get_stealth_manager"):
			return parent.get_stealth_manager()
		if parent.has("stealth_manager"):
			return parent.stealth_manager
		parent = parent.get_parent()
	return null

func set_stealth_manager(manager: StealthManager) -> void:
	_stealth_manager = manager

func set_update_rate(rate: float) -> void:
	_update_interval = clamp(rate, 0.05, 1.0)