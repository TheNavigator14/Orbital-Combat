class_name PDCPanel
extends Control

## Panel displaying Point Defense Cannon status
## Shows targeting info, ammunition, and fire status
## CRT phosphor-green aesthetic with scanlines and glow effects

signal pdc_fire_toggled(enabled: bool)
signal pdc_auto_toggled(enabled: bool)

# === References ===
var pdc: PDC = null

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
@onready var pdc_name_label: Label = $VBoxContainer/PDCNameLabel
@onready var status_label: Label = $VBoxContainer/StatusContainer/StatusLabel
@onready var target_label: Label = $VBoxContainer/TargetContainer/TargetLabel
@onready var target_distance_label: Label = $VBoxContainer/TargetDistanceContainer/TargetDistanceLabel
@onready var target_velocity_label: Label = $VBoxContainer/TargetVelocityContainer/TargetVelocityLabel
@onready var tracked_count_label: Label = $VBoxContainer/TrackedCountContainer/TrackedCountLabel
@onready var projectiles_label: Label = $VBoxContainer/ProjectilesContainer/ProjectilesLabel
@onready var accuracy_label: Label = $VBoxContainer/AccuracyContainer/AccuracyLabel
@onready var range_label: Label = $VBoxContainer/RangeContainer/RangeLabel
@onready var rotation_label: Label = $VBoxContainer/RotationContainer/RotationLabel
@onready var auto_toggle: CheckButton = $VBoxContainer/AutoContainer/AutoToggle
@onready var power_toggle: CheckButton = $VBoxContainer/PowerContainer/PowerToggle
@onready var fire_button: Button = $VBoxContainer/FireContainer/FireButton
@onready var status_indicator: ColorRect = $VBoxContainer/StatusIndicator

func _ready() -> void:
	custom_minimum_size = Vector2(220, 360)
	_apply_crt_theme()
	_connect_signals()
	_clear_status()

func _apply_crt_theme() -> void:
	# Apply phosphor-green color scheme to labels
	var all_labels = [
		pdc_name_label, status_label, target_label, target_distance_label,
		target_velocity_label, tracked_count_label, projectiles_label,
		accuracy_label, range_label, rotation_label
	]
	
	for label in all_labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_constant_override("shadow_outline_size", 2)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)
	
	# Style toggle buttons
	if auto_toggle:
		auto_toggle.button_pressed = true
	if power_toggle:
		power_toggle.button_pressed = true
	
	# Style fire button
	if fire_button:
		fire_button.add_theme_color_override("font_color", CRT_GREEN)
		fire_button.add_theme_color_override("bg_color", Color(0.15, 0.25, 0.15))

func _connect_signals() -> void:
	if auto_toggle:
		auto_toggle.toggled.connect(_on_auto_toggled)
	if power_toggle:
		power_toggle.toggled.connect(_on_power_toggled)
	if fire_button:
		fire_button.button_down.connect(_on_fire_pressed)
		fire_button.button_up.connect(_on_fire_released)

func set_pdc(new_pdc: PDC) -> void:
	## Set the PDC to display
	if pdc:
		_disconnect_pdc_signals()
	
	pdc = new_pdc
	
	if pdc:
		_connect_pdc_signals()
		_update_display()

func _connect_pdc_signals() -> void:
	if pdc == null:
		return
	
	if pdc.has_signal("pdc_fired"):
		pdc.pdc_fired.connect(_on_pdc_fired)
	if pdc.has_signal("pdc_hit"):
		pdc.pdc_hit.connect(_on_pdc_hit)
	if pdc.has_signal("pdc_target_locked"):
		pdc.pdc_target_locked.connect(_on_target_locked)
	if pdc.has_signal("pdc_target_lost"):
		pdc.pdc_target_lost.connect(_on_target_lost)
	if pdc.has_signal("pdc_cooldown_ready"):
		pdc.pdc_cooldown_ready.connect(_on_cooldown_ready)

func _disconnect_pdc_signals() -> void:
	if pdc == null:
		return
	
	if pdc.has_signal("pdc_fired"):
		if pdc.pdc_fired.is_connected(_on_pdc_fired):
			pdc.pdc_fired.disconnect(_on_pdc_fired)
	if pdc.has_signal("pdc_hit"):
		if pdc.pdc_hit.is_connected(_on_pdc_hit):
			pdc.pdc_hit.disconnect(_on_pdc_hit)
	if pdc.has_signal("pdc_target_locked"):
		if pdc.pdc_target_locked.is_connected(_on_target_locked):
			pdc.pdc_target_locked.disconnect(_on_target_locked)
	if pdc.has_signal("pdc_target_lost"):
		if pdc.pdc_target_lost.is_connected(_on_target_lost):
			pdc.pdc_target_lost.disconnect(_on_target_lost)
	if pdc.has_signal("pdc_cooldown_ready"):
		if pdc.pdc_cooldown_ready.is_connected(_on_cooldown_ready):
			pdc.pdc_cooldown_ready.disconnect(_on_cooldown_ready)

func _process(delta: float) -> void:
	if pdc:
		_update_display()
	_update_crt_flicker(delta)

func _update_display() -> void:
	## Update all display elements
	if pdc == null:
		_clear_status()
		return
	
	var data = pdc.get_pdc_data()
	
	# Status
	status_label.text = data.state_name
	_set_status_color(data.state_name)
	
	# Target info
	var has_target = data.has_target
	target_label.text = "TARGET: " + ("LOCKED" if has_target else "NONE")
	target_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT if has_target else CRT_GREEN_DIM)
	
	# Update target details if we have one
	if has_target and pdc.current_target:
		var target_pos = pdc.current_target.position
		var shooter_pos = pdc.parent_ship.world_position if pdc.parent_ship else Vector2.ZERO
		var distance = shooter_pos.distance_to(target_pos)
		target_distance_label.text = "DIST: " + _format_distance(distance)
		
		# Show target velocity if it's a missile
		if pdc.current_target is Missile:
			var vel = pdc.current_target.velocity.length()
			target_velocity_label.text = "VEL: " + _format_velocity(vel)
		else:
			target_velocity_label.text = "VEL: ---"
	else:
		target_distance_label.text = "DIST: ---"
		target_velocity_label.text = "VEL: ---"
	
	# Tracking info
	tracked_count_label.text = "TRACKED: %d" % data.tracked_count
	
	# Projectile count
	projectiles_label.text = "ROUNDS: %d" % data.projectiles_active
	
	# Accuracy
	accuracy_label.text = "ACC: %.1f%%" % data.accuracy
	
	# Range bar
	var max_range = pdc.max_range
	var min_range = pdc.min_range
	var range_text = "RANGE: %.0f km" % (max_range / 1000.0)
	range_label.text = range_text
	
	# Rotation
	var barrel_angle = pdc.current_angle
	rotation_label.text = "AZI: %.0f°" % barrel_angle
	
	# Toggle states
	if auto_toggle:
		auto_toggle.set_pressed_no_signal(data.is_auto_fire)
	if power_toggle:
		power_toggle.set_pressed_no_signal(data.is_powered)
	
	# Fire button state
	if fire_button:
		if data.state_name == "FIRING":
			fire_button.add_theme_color_override("font_color", CRT_RED)
			fire_button.add_theme_color_override("bg_color", Color(0.35, 0.15, 0.15))
		else:
			fire_button.add_theme_color_override("font_color", CRT_GREEN)
			fire_button.add_theme_color_override("bg_color", Color(0.15, 0.25, 0.15))

func _set_status_color(status: String) -> void:
	match status:
		"IDLE":
			status_label.add_theme_color_override("font_color", CRT_GREEN_DIM)
			status_indicator.color = CRT_GREEN_DIM
		"TRACKING":
			status_label.add_theme_color_override("font_color", CRT_AMBER)
			status_indicator.color = CRT_AMBER
		"FIRING":
			status_label.add_theme_color_override("font_color", CRT_RED)
			status_indicator.color = CRT_RED
		"COOLDOWN":
			status_label.add_theme_color_override("font_color", CRT_GREEN)
			status_indicator.color = CRT_GREEN
		_:
			status_label.add_theme_color_override("font_color", CRT_GREEN)
			status_indicator.color = CRT_GREEN

func _format_distance(meters: float) -> String:
	## Format distance for display
	if meters < 1000:
		return "%.0f m" % meters
	elif meters < 100000:
		return "%.1f km" % (meters / 1000.0)
	else:
		return "%.0f km" % (meters / 1000.0)

func _format_velocity(meters_per_second: float) -> String:
	## Format velocity for display
	return "%.0f m/s" % meters_per_second

func _clear_status() -> void:
	pdc_name_label.text = "[ PDC ]"
	status_label.text = "OFFLINE"
	target_label.text = "TARGET: NONE"
	target_distance_label.text = "DIST: ---"
	target_velocity_label.text = "VEL: ---"
	tracked_count_label.text = "TRACKED: 0"
	projectiles_label.text = "ROUNDS: 0"
	accuracy_label.text = "ACC: 0.0%"
	range_label.text = "RANGE: ---"
	rotation_label.text = "AZI: ---"
	status_label.add_theme_color_override("font_color", CRT_GREEN_DIM)
	status_indicator.color = CRT_GREEN_DIM

# === Signal Handlers ===

func _on_pdc_fired(target: Node2D) -> void:
	# Visual flash effect on fire
	if fire_button:
		fire_button.modulate = Color(1.5, 1.5, 1.5)
		await get_tree().create_timer(0.05).timeout
		if fire_button:
			fire_button.modulate = Color(1.0, 1.0, 1.0)

func _on_pdc_hit(target: Node2D) -> void:
	# Flash indicator on successful hit
	status_indicator.modulate = Color(2.0, 1.0, 1.0)
	await get_tree().create_timer(0.1).timeout
	status_indicator.modulate = Color(1.0, 1.0, 1.0)

func _on_target_locked(target: Node2D) -> void:
	# Audio cue could go here
	pass

func _on_target_lost() -> void:
	target_distance_label.text = "DIST: ---"
	target_velocity_label.text = "VEL: ---"

func _on_cooldown_ready() -> void:
	# Ready to fire again
	pass

func _on_auto_toggled(enabled: bool) -> void:
	if pdc:
		pdc.set_auto_fire(enabled)
	auto_toggled.emit(enabled)

func _on_power_toggled(enabled: bool) -> void:
	if pdc:
		pdc.set_powered(enabled)
	pdc_fire_toggled.emit(enabled)

func _on_fire_pressed() -> void:
	## Manual fire - engage with manual target
	if pdc and pdc.prioritized_target:
		pdc.set_target(pdc.prioritized_target)
		# Try to fire immediately
		if pdc.fire_cooldown <= 0 and pdc.pdc_state != PDC.PDCState.COOLDOWN:
			pdc._fire()

func _on_fire_released() -> void:
	## Release fire button
	pass

func _update_crt_flicker(delta: float) -> void:
	# Subtle phosphor flicker
	flicker_timer += delta
	if flicker_timer > 0.1:
		flicker_timer = 0.0
		if randf() > 0.97:
			modulate = Color(0.88, 0.88, 0.88, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)