class_name ShipPanel
extends Control

## Panel displaying ship status: fuel, delta-v, thrust, systems
## Includes manual thrust control buttons for player input
## CRT phosphor-green aesthetic with scanlines and glow effects

signal thrust_command(direction: Ship.ThrustDirection)
signal stop_thrust_command()

# === References ===
var ship: Ship = null

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
@onready var ship_name_label: Label = $VBoxContainer/ShipNameLabel
@onready var thrust_status_label: Label = $VBoxContainer/ThrustStatusContainer/ThrustStatusLabel
@onready var thrust_direction_label: Label = $VBoxContainer/ThrustDirectionContainer/ThrustDirectionLabel
@onready var fuel_bar: ProgressBar = $VBoxContainer/FuelContainer/FuelBar
@onready var fuel_percent_label: Label = $VBoxContainer/FuelContainer/FuelPercentLabel
@onready var fuel_label: Label = $VBoxContainer/FuelContainer/FuelLabel
@onready var delta_v_label: Label = $VBoxContainer/DeltaVContainer/DeltaVLabel
@onready var max_delta_v_label: Label = $VBoxContainer/DeltaVContainer/MaxDeltaVLabel
@onready var twr_label: Label = $VBoxContainer/TWRContainer/TWRLabel
@onready var mass_label: Label = $VBoxContainer/MassContainer/MassLabel
@onready var thrust_watts_label: Label = $VBoxContainer/ThrustWattsContainer/ThrustWattsLabel

# === Thrust Control Buttons ===
@onready var prograde_btn: Button = $VBoxContainer/ThrustControls/ThrustRow1/ProgradeBtn
@onready var retrograde_btn: Button = $VBoxContainer/ThrustControls/ThrustRow1/RetrogradeBtn
@onready var radial_in_btn: Button = $VBoxContainer/ThrustControls/ThrustRow1/RadialInBtn
@onready var radial_out_btn: Button = $VBoxContainer/ThrustControls/ThrustRow2/RadialOutBtn
@onready var normal_btn: Button = $VBoxContainer/ThrustControls/ThrustRow2/NormalBtn
@onready var anti_normal_btn: Button = $VBoxContainer/ThrustControls/ThrustRow2/AntiNormalBtn
@onready var stop_btn: Button = $VBoxContainer/ThrustControls/StopContainer/StopBtn
@onready var throttle_slider: HSlider = $VBoxContainer/ThrottleContainer/ThrottleSlider
@onready var throttle_label: Label = $VBoxContainer/ThrottleContainer/ThrottleLabel
@onready var heading_label: Label = $VBoxContainer/HeadingContainer/HeadingLabel
@onready var soi_label: Label = $VBoxContainer/SOIContainer/SOILabel
@onready var altitude_label: Label = $VBoxContainer/AltitudeContainer/AltitudeLabel

func _ready() -> void:
	custom_minimum_size = Vector2(280, 460)
	_apply_crt_theme()
	_connect_signals()

func _apply_crt_theme() -> void:
	# Apply phosphor-green color scheme to labels
	var all_labels = [
		ship_name_label, thrust_status_label, thrust_direction_label,
		fuel_percent_label, fuel_label, delta_v_label, max_delta_v_label,
		twr_label, mass_label, thrust_watts_label, throttle_label, heading_label
	]
	
	for label in all_labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_constant_override("shadow_outline_size", 2)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)
	
	# Style fuel bar
	if fuel_bar:
		fuel_bar.add_theme_color_override("font_color", CRT_GREEN_DIM)
	
	# Style thrust buttons
	var thrust_buttons = [prograde_btn, retrograde_btn, radial_in_btn, radial_out_btn, normal_btn, anti_normal_btn, stop_btn]
	for btn in thrust_buttons:
		if btn:
			_style_crt_button(btn)

func _style_crt_button(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_color_override("font_color", CRT_GREEN)
	btn.add_theme_color_override("font_hover_color", CRT_GREEN_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", CRT_GREEN_DIM)

func _connect_signals() -> void:
	prograde_btn.pressed.connect(_on_prograde)
	retrograde_btn.pressed.connect(_on_retrograde)
	radial_in_btn.pressed.connect(_on_radial_in)
	radial_out_btn.pressed.connect(_on_radial_out)
	normal_btn.pressed.connect(_on_normal)
	anti_normal_btn.pressed.connect(_on_anti_normal)
	stop_btn.pressed.connect(_on_stop_thrust)
	throttle_slider.value_changed.connect(_on_throttle_changed)

func set_ship(s: Ship) -> void:
	ship = s
	if ship:
		ship_name_label.text = "[ %s ]" % ship.ship_name
		_update_button_states()
	else:
		ship_name_label.text = "[ NO SHIP ]"

func _process(delta: float) -> void:
	_update_crt_flicker(delta)
	
	if ship == null:
		_clear_status()
		return
	
	# Ship name
	ship_name_label.text = "[ %s ]" % ship.ship_name
	
	# Thrust status with CRT highlighting
	if ship.is_thrusting:
		thrust_status_label.text = ">>> ACTIVE <<<"
		thrust_status_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	else:
		thrust_status_label.text = "IDLE"
		thrust_status_label.add_theme_color_override("font_color", CRT_GREEN)
	
	# Thrust direction
	_update_thrust_direction_display()
	
	# Fuel gauge
	var fuel_pct = ship.get_fuel_percent()
	fuel_bar.value = fuel_pct
	
	# Fuel bar color based on level
	if fuel_pct < 10:
		fuel_bar.add_theme_color_override("fill_color", CRT_RED)
	elif fuel_pct < 25:
		fuel_bar.add_theme_color_override("fill_color", CRT_AMBER)
	else:
		fuel_bar.add_theme_color_override("fill_color", CRT_GREEN)
	
	fuel_percent_label.text = "%.1f%%" % fuel_pct
	
	var fuel_kg = ship.fuel_mass
	if fuel_kg >= 1000:
		fuel_label.text = "FUEL: %.1f t" % (fuel_kg / 1000.0)
	else:
		fuel_label.text = "FUEL: %.0f kg" % fuel_kg
	
	# Delta-v
	var dv_info = ship.get_delta_v_info()
	delta_v_label.text = "dV: %s" % OrbitalConstantsClass.format_velocity(dv_info.current)
	max_delta_v_label.text = "Max: %s" % OrbitalConstantsClass.format_velocity(dv_info.max)
	
	# Thrust-to-weight
	var twr = ship.get_thrust_weight_ratio()
	if twr > 0:
		twr_label.text = "TWR: %.2f" % twr
		if twr < 0.1:
			twr_label.add_theme_color_override("font_color", CRT_RED)
		elif twr < 0.5:
			twr_label.add_theme_color_override("font_color", CRT_AMBER)
		else:
			twr_label.add_theme_color_override("font_color", CRT_GREEN)
	else:
		twr_label.text = "TWR: ---"
	
	# Mass
	mass_label.text = "Mass: %.1f t" % (ship.mass / 1000.0)
	
	# Thrust output
	var thrust_n = ship.get_current_thrust()
	var thrust_kw = thrust_n / 1000.0
	if thrust_n > 0:
		thrust_watts_label.text = "Thrust: %.1f kN" % thrust_kw
		thrust_watts_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	else:
		thrust_watts_label.text = "Thrust: ---"
	
	# Heading display
	var orbit_info = ship.get_orbit_info()
	var heading_rad = atan2(orbit_info.prograde_dir.y, orbit_info.prograde_dir.x)
	var heading_deg = rad_to_deg(heading_rad)
	if heading_deg < 0:
		heading_deg += 360.0
	var heading_str = "HDG: %.0f°" % heading_deg
	
	var vel = ship.velocity.length()
	var speed_str = OrbitalConstantsClass.format_velocity(vel)
	heading_label.text = "%s | %s" % [heading_str, speed_str]
	
	# Update button states
	_update_button_states()

func _update_thrust_direction_display() -> void:
	if ship == null or not ship.is_thrusting:
		thrust_direction_label.text = "---"
		return
	
	var dir_name = "UNKNOWN"
	match ship.current_thrust_direction:
		Ship.ThrustDirection.PROGRADE:
			dir_name = "PROGRADE"
		Ship.ThrustDirection.RETROGRADE:
			dir_name = "RETROGRADE"
		Ship.ThrustDirection.RADIAL_IN:
			dir_name = "RADIAL IN"
		Ship.ThrustDirection.RADIAL_OUT:
			dir_name = "RADIAL OUT"
		Ship.ThrustDirection.NORMAL:
			dir_name = "NORMAL"
		Ship.ThrustDirection.ANTI_NORMAL:
			dir_name = "ANTI-NORM"
	
	thrust_direction_label.text = dir_name
	thrust_direction_label.add_theme_color_override("font_color", CRT_AMBER)

func _update_button_states() -> void:
	var has_fuel = ship and ship.fuel_mass > 0
	var can_thrust = has_fuel and not (ship and ship.is_thrusting)
	
	# Enable/disable buttons based on state
	prograde_btn.disabled = not can_thrust
	retrograde_btn.disabled = not can_thrust
	radial_in_btn.disabled = not can_thrust
	radial_out_btn.disabled = not can_thrust
	normal_btn.disabled = not can_thrust
	anti_normal_btn.disabled = not can_thrust
	stop_btn.disabled = not (ship and ship.is_thrusting)
	throttle_slider.editable = has_fuel
	
	# Highlight active thrust button
	_set_button_highlight(prograde_btn, ship and ship.current_thrust_direction == Ship.ThrustDirection.PROGRADE)
	_set_button_highlight(retrograde_btn, ship and ship.current_thrust_direction == Ship.ThrustDirection.RETROGRADE)
	_set_button_highlight(radial_in_btn, ship and ship.current_thrust_direction == Ship.ThrustDirection.RADIAL_IN)
	_set_button_highlight(radial_out_btn, ship and ship.current_thrust_direction == Ship.ThrustDirection.RADIAL_OUT)
	_set_button_highlight(normal_btn, ship and ship.current_thrust_direction == Ship.ThrustDirection.NORMAL)
	_set_button_highlight(anti_normal_btn, ship and ship.current_thrust_direction == Ship.ThrustDirection.ANTI_NORMAL)

func _set_button_highlight(btn: Button, is_active: bool) -> void:
	if btn == null:
		return
	if is_active:
		btn.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
		btn.add_theme_color_override("bg_color", Color(0.15, 0.35, 0.15))
	else:
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_color_override("bg_color")

# === Thrust Control Signals ===

func _on_prograde() -> void:
	if ship == null or ship.fuel_mass <= 0:
		return
	_apply_throttle()
	thrust_command.emit(Ship.ThrustDirection.PROGRADE)

func _on_retrograde() -> void:
	if ship == null or ship.fuel_mass <= 0:
		return
	_apply_throttle()
	thrust_command.emit(Ship.ThrustDirection.RETROGRADE)

func _on_radial_in() -> void:
	if ship == null or ship.fuel_mass <= 0:
		return
	_apply_throttle()
	thrust_command.emit(Ship.ThrustDirection.RADIAL_IN)

func _on_radial_out() -> void:
	if ship == null or ship.fuel_mass <= 0:
		return
	_apply_throttle()
	thrust_command.emit(Ship.ThrustDirection.RADIAL_OUT)

func _on_normal() -> void:
	if ship == null or ship.fuel_mass <= 0:
		return
	_apply_throttle()
	thrust_command.emit(Ship.ThrustDirection.NORMAL)

func _on_anti_normal() -> void:
	if ship == null or ship.fuel_mass <= 0:
		return
	_apply_throttle()
	thrust_command.emit(Ship.ThrustDirection.ANTI_NORMAL)

func _on_stop_thrust() -> void:
	if ship == null:
		return
	stop_thrust_command.emit()

func _on_throttle_changed(value: float) -> void:
	if ship == null:
		return
	ship.throttle = value / 100.0
	throttle_label.text = "THROTTLE: %.0f%%" % value

func _apply_throttle() -> void:
	if ship == null:
		return
	ship.throttle = throttle_slider.value / 100.0

func _clear_status() -> void:
	ship_name_label.text = "[ NO SHIP ]"
	thrust_status_label.text = "---"
	thrust_direction_label.text = "---"
	fuel_bar.value = 0
	fuel_percent_label.text = "0%"
	fuel_label.text = "FUEL: ---"
	delta_v_label.text = "dV: ---"
	max_delta_v_label.text = "Max: ---"
	twr_label.text = "TWR: ---"
	mass_label.text = "Mass: ---"
	thrust_watts_label.text = "Thrust: ---"
	heading_label.text = "HDG: ---"

func _update_crt_flicker(delta: float) -> void:
	# Subtle phosphor flicker
	flicker_timer += delta
	if flicker_timer > 0.1:
		flicker_timer = 0.0
		if randf() > 0.97:
			modulate = Color(0.88, 0.88, 0.88, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)