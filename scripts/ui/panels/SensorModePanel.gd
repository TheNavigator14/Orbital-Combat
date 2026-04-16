class_name SensorModePanel
extends Control

## Panel for controlling sensor mode and displaying radar/thermal status
## Allows switching between passive (thermal) and active (radar) sensor modes
## CRT phosphor-green aesthetic with amber/red for radar states

signal sensor_mode_changed(mode: int)

# === Sensor Modes ===
enum SensorMode {
	PASSIVE = 0,  # Thermal only, no emissions
	RADAR = 1,    # Active radar, high detection but reveals position
}

# === References ===
var sensor_manager: SensorManager = null

# === CRT Colors ===
const CRT_GREEN = Color(0.2, 1.0, 0.4)
const CRT_GREEN_DIM = Color(0.1, 0.5, 0.2)
const CRT_GREEN_BRIGHT = Color(0.4, 1.0, 0.6)
const CRT_AMBER = Color(1.0, 0.6, 0.2)
const CRT_RED = Color(1.0, 0.3, 0.2)
const CRT_GLOW = Color(0.1, 0.5, 0.2, 0.3)
const RADAR_ACTIVE_COLOR = Color(1.0, 0.4, 0.2)
const RADAR_ALERT_COLOR = Color(1.0, 0.1, 0.1)

# === State ===
var current_mode: int = SensorMode.PASSIVE
var is_radar_active: bool = false
var detected_contacts_count: int = 0
var radar_sweep_angle: float = 0.0
var is_scanning: bool = false
var scan_progress: float = 0.0
var scan_duration: float = 2.0  # seconds for a full scan

# === CRT Effects ===
var flicker_timer: float = 0.0
var alert_pulse: float = 0.0

# === Node References ===
@onready var mode_label: Label = $VBoxContainer/ModeContainer/ModeLabel
@onready var passive_btn: Button = $VBoxContainer/ModeButtons/PassiveBtn
@onready var radar_btn: Button = $VBoxContainer/ModeButtons/RadarBtn
@onready var thermal_status_label: Label = $VBoxContainer/ThermalContainer/ThermalStatusLabel
@onready var thermal_range_label: Label = $VBoxContainer/ThermalRangeContainer/ThermalRangeLabel
@onready var radar_status_label: Label = $VBoxContainer/RadarStatusContainer/RadarStatusLabel
@onready var radar_range_label: Label = $VBoxContainer/RadarRangeContainer/RadarRangeLabel
@onready var sweep_indicator: Control = $VBoxContainer/SweepContainer/SweepIndicator
@onready var contacts_count_label: Label = $VBoxContainer/ContactsContainer/ContactsLabel
@onready var emission_warning: Label = $VBoxContainer/EmissionWarning/EmissionLabel
@onready var lock_status_label: Label = $VBoxContainer/LockContainer/LockStatusLabel
@onready var scan_progress_bar: ProgressBar = $VBoxContainer/ScanProgressContainer/ScanProgressBar

func _ready() -> void:
	custom_minimum_size = Vector2(280, 340)
	_apply_crt_theme()
	_update_display()


func _apply_crt_theme() -> void:
	# Apply phosphor-green color scheme
	var labels = [
		mode_label, thermal_status_label, thermal_range_label,
		radar_status_label, radar_range_label, contacts_count_label,
		emission_warning, lock_status_label
	]
	for label in labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_constant_override("shadow_outline_size", 2)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)
	
	# Style buttons
	passive_btn.add_theme_color_override("font_color", CRT_GREEN)
	radar_btn.add_theme_color_override("font_color", CRT_GREEN_DIM)


func set_sensor_manager(manager: SensorManager) -> void:
	sensor_manager = manager
	if sensor_manager:
		if sensor_manager.has_signal("contact_detected"):
			sensor_manager.contact_detected.connect(_on_contact_detected)
		if sensor_manager.has_signal("contact_lost"):
			sensor_manager.contact_lost.connect(_on_contact_lost)
	_update_display()


func set_mode(mode: int) -> void:
	current_mode = mode
	if sensor_manager:
		sensor_manager.active_scan_mode = mode
	is_radar_active = (mode == SensorMode.RADAR)
	_update_display()
	sensor_mode_changed.emit(mode)


func _process(delta: float) -> void:
	# Update CRT effects
	_update_crt_flicker(delta)
	
	# Update radar sweep animation
	if is_radar_active:
		radar_sweep_angle = fmod(radar_sweep_angle + delta * 90.0, 360.0)
	
	# Update scan progress
	if is_scanning:
		scan_progress += delta / scan_duration
		if scan_progress >= 1.0:
			scan_progress = 1.0
			is_scanning = false
			_complete_scan()
		if scan_progress_bar:
			scan_progress_bar.value = scan_progress * 100
	
	# Update contact count from sensor manager
	if sensor_manager:
		detected_contacts_count = sensor_manager.detected_contacts.size()
		contacts_count_label.text = "CONTACTS: %d" % detected_contacts_count
	
	# Alert pulse for active radar
	if is_radar_active:
		alert_pulse += delta * 2.0
		var pulse_val = (sin(alert_pulse) + 1.0) / 2.0
		emission_warning.add_theme_color_override("font_color", 
			CRT_AMBER.lerp(CRT_RED, pulse_val * 0.5))
	
	# Update display states
	_update_button_states()


func _update_display() -> void:
	# Mode label
	match current_mode:
		SensorMode.PASSIVE:
			mode_label.text = "[ PASSIVE ]"
			mode_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
			thermal_status_label.text = "STATUS: ACTIVE"
			thermal_status_label.add_theme_color_override("font_color", CRT_GREEN)
			radar_status_label.text = "STATUS: OFF"
			radar_status_label.add_theme_color_override("font_color", CRT_GREEN_DIM)
			emission_warning.text = "EMISSIONS: NONE"
			emission_warning.add_theme_color_override("font_color", CRT_GREEN)
			thermal_range_label.text = "RANGE: PASSIVE"
		SensorMode.RADAR:
			mode_label.text = "[ ACTIVE RADAR ]"
			mode_label.add_theme_color_override("font_color", CRT_AMBER)
			thermal_status_label.text = "STATUS: ACTIVE"
			thermal_status_label.add_theme_color_override("font_color", CRT_GREEN)
			radar_status_label.text = "STATUS: ACTIVE"
			radar_status_label.add_theme_color_override("font_color", CRT_AMBER)
			emission_warning.text = "EMISSIONS: HIGH"
			emission_warning.add_theme_color_override("font_color", CRT_RED)
			thermal_range_label.text = "RANGE: 1.0 Mm"
	
	# Range display
	if sensor_manager:
		thermal_range_label.text = "THERMAL: %.0f km" % (sensor_manager.thermal_range / 1000.0)
		radar_range_label.text = "RADAR: %.0f km" % (sensor_manager.radar_range / 1000.0)
	else:
		thermal_range_label.text = "THERMAL: 500 km"
		radar_range_label.text = "RADAR: 1000 km"
	
	# Update button states
	_update_button_states()


func _update_button_states() -> void:
	# Highlight active mode button
	if current_mode == SensorMode.PASSIVE:
		passive_btn.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
		passive_btn.add_theme_color_override("bg_color", Color(0.15, 0.35, 0.15))
		radar_btn.remove_theme_color_override("font_color")
		radar_btn.remove_theme_color_override("bg_color")
	else:
		radar_btn.add_theme_color_override("font_color", CRT_AMBER)
		radar_btn.add_theme_color_override("bg_color", Color(0.35, 0.15, 0.15))
		passive_btn.remove_theme_color_override("font_color")
		passive_btn.remove_theme_color_override("bg_color")
	
	# Contacts count color
	if detected_contacts_count > 0:
		contacts_count_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	else:
		contacts_count_label.add_theme_color_override("font_color", CRT_GREEN_DIM)


func _on_passive_pressed() -> void:
	set_mode(SensorMode.PASSIVE)


func _on_radar_pressed() -> void:
	set_mode(SensorMode.RADAR)


func _on_contact_detected(contact: SensorContact) -> void:
	detected_contacts_count += 1
	_update_display()
	
	# Flash effect on detection
	contacts_count_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	await get_tree().create_timer(0.3).timeout
	_update_display()


func _on_contact_lost(contact: SensorContact) -> void:
	detected_contacts_count = max(0, detected_contacts_count - 1)
	_update_display()


func start_scan() -> void:
	"""Start a radar scan animation"""
	if is_radar_active and not is_scanning:
		is_scanning = true
		scan_progress = 0.0


func _complete_scan() -> void:
	"""Called when scan completes"""
	pass


func get_locked_contact() -> SensorContact:
	"""Get currently locked contact if any"""
	if sensor_manager == null:
		return null
	
	# Check for any identified contacts
	for contact in sensor_manager.detected_contacts.values():
		if contact is SensorContact and contact.contact_status == SensorManager.ContactStatus.IDENTIFIED:
			return contact
	return null


func _update_crt_flicker(delta: float) -> void:
	# Subtle phosphor flicker
	flicker_timer += delta
	if flicker_timer > 0.12:
		flicker_timer = 0.0
		if randf() > 0.97:
			modulate = Color(0.90, 0.90, 0.90, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)