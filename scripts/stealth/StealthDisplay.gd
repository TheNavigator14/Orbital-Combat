class_name StealthDisplay
extends Control

## UI panel showing current stealth status and signature management.

@onready var thermal_bar: TextureProgressBar = $VBox/thermal_panel/thermal_bar
@onready var radar_bar: TextureProgressBar = $VBox/radar_panel/radar_bar
@onready var em_bar: TextureProgressBar = $VBox/em_panel/em_bar
@onready var heat_bar: TextureProgressBar = $VBox/heat_panel/heat_bar
@onready var heat_temp_label: Label = $VBox/heat_panel/heat_temp

@onready var stealth_state_label: Label = $VBox/stealth_state/label
@onready var stealth_button: Button = $VBox/stealth_button

@onready var suite_check: CheckBox = $VBox/equipment/suite_check
@onready var coating_check: CheckBox = $VBox/equipment/coating_check
@onready var ir_suppress_check: CheckBox = $VBox/equipment/ir_suppress_check

@onready var cold_run_button: Button = $VBox/cold_run/button
@onready var cool_vent_button: Button = $VBox/cool_vent/button

var stealth_manager: StealthManager = null
var current_ship_id: String = ""

func _ready() -> void:
	hide()
	
	stealth_button.pressed.connect(_on_stealth_pressed)
	suite_check.toggled.connect(_on_suite_toggled)
	coating_check.toggled.connect(_on_coating_toggled)
	ir_suppress_check.toggled.connect(_on_ir_suppress_toggled)
	cold_run_button.pressed.connect(_on_cold_run_pressed)
	cool_vent_button.pressed.connect(_on_cool_vent_pressed)

## Set the stealth manager reference
func set_stealth_manager(manager: StealthManager) -> void:
	stealth_manager = manager

## Show stealth panel for a specific ship
func show_for_ship(ship_id: String) -> void:
	current_ship_id = ship_id
	show()
	update_display()

## Update signature bars based on current ship
func update_display() -> void:
	if not stealth_manager or current_ship_id.is_empty():
		return
	
	var sig: ShipSignature = stealth_manager.get_ship_signature(current_ship_id)
	if not sig:
		return
	
	# Update thermal bar
	var thermal = sig.get_effective_thermal()
	thermal_bar.value = thermal * 100
	
	if thermal < 0.3:
		thermal_bar.modulate = Color(0.2, 1.0, 0.2)
	elif thermal < 0.7:
		thermal_bar.modulate = Color(1.0, 1.0, 0.2)
	else:
		thermal_bar.modulate = Color(1.0, 0.2, 0.2)
	
	# Update radar bar
	var radar = sig.get_effective_radar()
	radar_bar.value = min(radar * 10, 100)
	
	if radar < 1.0:
		radar_bar.modulate = Color(0.2, 1.0, 0.2)
	elif radar < 10.0:
		radar_bar.modulate = Color(1.0, 1.0, 0.2)
	else:
		radar_bar.modulate = Color(1.0, 0.2, 0.2)
	
	# Update EM bar
	var em = sig.get_effective_electromagnetic()
	em_bar.value = em * 100
	
	if em < 0.1:
		em_bar.modulate = Color(0.2, 1.0, 0.2)
	elif em < 0.5:
		em_bar.modulate = Color(1.0, 1.0, 0.2)
	else:
		em_bar.modulate = Color(1.0, 0.2, 0.2)
	
	# Update heat bar and temperature
	var temp_kelvin = sig.get_hull_temperature()
	var temp_celsius = temp_kelvin - 273.15
	heat_temp_label.text = "%.1f°C" % temp_celsius
	
	# Heat bar: 0-1500K range
	var heat_percent = (temp_kelvin / 1500.0) * 100
	heat_bar.value = heat_percent
	
	if temp_kelvin < 250.0:
		heat_bar.modulate = Color(0.3, 0.5, 1.0)  # Blue - cold
	elif temp_kelvin < 350.0:
		heat_bar.modulate = Color(0.2, 1.0, 0.2)  # Green - cool
	elif temp_kelvin < 500.0:
		heat_bar.modulate = Color(1.0, 1.0, 0.2)  # Yellow - warm
	elif temp_kelvin < 800.0:
		heat_bar.modulate = Color(1.0, 0.6, 0.2)  # Orange - hot
	else:
		heat_bar.modulate = Color(1.0, 0.2, 0.2)  # Red - critical
	
	# Update stealth state label
	match stealth_manager.current_state:
		StealthManager.StealthState.NORMAL:
			stealth_state_label.text = "NORMAL"
			stealth_state_label.modulate = Color(1.0, 1.0, 1.0)
		StealthManager.StealthState.LOW:
			stealth_state_label.text = "LOW"
			stealth_state_label.modulate = Color(1.0, 1.0, 0.2)
		StealthManager.StealthState.SILENT:
			stealth_state_label.text = "SILENT"
			stealth_state_label.modulate = Color(0.2, 1.0, 0.2)
		StealthManager.StealthState.GHOST:
			stealth_state_label.text = "GHOST"
			stealth_state_label.modulate = Color(0.2, 0.5, 1.0)
	
	# Update equipment checkboxes
	suite_check.button_pressed = stealth_manager.stealth_suite_active
	coating_check.button_pressed = stealth_manager.radar_absorbent_coating
	ir_suppress_check.button_pressed = stealth_manager.infrared_suppression

func _on_stealth_pressed() -> void:
	if not stealth_manager:
		return
	
	match stealth_manager.current_state:
		StealthManager.StealthState.NORMAL:
			stealth_manager.set_stealth_state(StealthManager.StealthState.SILENT)
		StealthManager.StealthState.SILENT:
			stealth_manager.set_stealth_state(StealthManager.StealthState.NORMAL)
		StealthManager.StealthState.LOW:
			stealth_manager.set_stealth_state(StealthManager.StealthState.GHOST)
		_:
			pass
	
	update_display()

func _on_suite_toggled(pressed: bool) -> void:
	if stealth_manager:
		stealth_manager.stealth_suite_active = pressed
		update_display()

func _on_coating_toggled(pressed: bool) -> void:
	if stealth_manager:
		stealth_manager.radar_absorbent_coating = pressed
		update_display()

func _on_ir_suppress_toggled(pressed: bool) -> void:
	if stealth_manager:
		stealth_manager.infrared_suppression = pressed
		update_display()

## Engage cold running mode - minimize heat signature
func _on_cold_run_pressed() -> void:
	var sig: ShipSignature = stealth_manager.get_ship_signature(current_ship_id)
	if sig:
		sig.engage_stealth_mode()
		stealth_manager.set_stealth_state(StealthManager.StealthState.GHOST)
		# Start emergency cooling to reach cold target
		sig.start_emergency_cooling()
	update_display()

## Emergency cooling vent - fast heat dissipation
func _on_cool_vent_pressed() -> void:
	var sig: ShipSignature = stealth_manager.get_ship_signature(current_ship_id)
	if sig:
		sig.start_emergency_cooling()
	update_display()