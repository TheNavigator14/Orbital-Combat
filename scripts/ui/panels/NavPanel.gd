class_name NavPanel
extends Control

## Panel displaying orbital navigation readouts: Ap/Pe/Alt/Period
## CRT phosphor-green aesthetic with scanlines and glow effects

signal target_changed(celestial_body)

# === References ===
var ship: Ship = null
var target_body: CelestialBody = null

# === CRT Effects ===
var scanline_offset: float = 0.0
var glow_intensity: float = 1.2
var flicker_timer: float = 0.0
var flicker_active: bool = false

# === CRT Colors ===
const CRT_GREEN = Color(0.2, 1.0, 0.4)
const CRT_GREEN_DIM = Color(0.1, 0.5, 0.2)
const CRT_GREEN_BRIGHT = Color(0.4, 1.0, 0.6)
const CRT_AMBER = Color(1.0, 0.6, 0.2)
const CRT_GLOW = Color(0.1, 0.5, 0.2, 0.3)

# === Node References ===
@onready var orbit_type_label: Label = $VBoxContainer/OrbitTypeLabel
@onready var altitude_label: Label = $VBoxContainer/AltitudeContainer/AltitudeLabel
@onready var periapsis_label: Label = $VBoxContainer/PeContainer/PeLabel
@onready var apoapsis_label: Label = $VBoxContainer/ApContainer/ApLabel
@onready var period_label: Label = $VBoxContainer/PeriodContainer/PeriodLabel
@onready var velocity_label: Label = $VBoxContainer/VelocityContainer/VelocityLabel
@onready var inclination_label: Label = $VBoxContainer/InclinationContainer/InclinationLabel
@onready var target_label: Label = $VBoxContainer/TargetLabel
@onready var distance_to_target_label: Label = $VBoxContainer/DistanceContainer/DistanceLabel

# === Display Settings ===
var orbital_constants = OrbitalConstantsClass

func _ready() -> void:
	custom_minimum_size = Vector2(280, 320)
	_apply_crt_theme()

func _apply_crt_theme() -> void:
	# Apply phosphor-green color scheme to all labels
	var all_labels = [
		orbit_type_label, altitude_label, periapsis_label, apoapsis_label,
		period_label, velocity_label, inclination_label, target_label,
		distance_to_target_label
	]
	
	for label in all_labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_constant_override("shadow_outline_size", 2)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)

func set_ship(s: Ship) -> void:
	ship = s
	if ship and ship.orbit_state:
		target_body = ship.orbit_state.parent_body

func set_target(body: CelestialBody) -> void:
	target_body = body
	if body:
		target_label.text = "Target: %s" % body.body_name
	else:
		target_label.text = "No Target"
	target_changed.emit(body)

func _process(delta: float) -> void:
	# Update CRT flicker effects
	_update_crt_flicker(delta)
	
	if ship == null or ship.orbit_state == null:
		_clear_readouts()
		return
	
	var orbit = ship.orbit_state
	var display_alt = orbit.position.length() - (orbit.parent_body.radius if orbit.parent_body else 0)
	
	# Orbit type
	if orbit.eccentricity < 0.01:
		orbit_type_label.text = "[ CIRCULAR ORBIT ]"
	elif orbit.eccentricity < 0.2:
		orbit_type_label.text = "[ ELLIPTICAL ORBIT ]"
	elif orbit.eccentricity >= 0.95:
		orbit_type_label.text = "[ ESCAPE TRAJECTORY ]"
	else:
		orbit_type_label.text = "[ ECCENTRIC ORBIT ]"
	
	# Distance values
	altitude_label.text = "ALT: %s" % orbital_constants.format_distance(display_alt)
	periapsis_label.text = "Pe: %s" % orbital_constants.format_distance(orbit.periapsis - (orbit.parent_body.radius if orbit.parent_body else 0))
	apoapsis_label.text = "Ap: %s" % orbital_constants.format_distance(max(0, orbit.apoapsis) - (orbit.parent_body.radius if orbit.parent_body else 0))
	
	# Period
	if orbit.orbital_period < 600:
		period_label.text = "T: <10m"
	elif orbit.orbital_period > 86400 * 100:
		period_label.text = "T: >100d"
	else:
		period_label.text = "T: %s" % orbital_constants.format_time(orbit.orbital_period)
	
	# Velocity
	var vel = ship.velocity.length()
	if vel > 10000:
		velocity_label.text = "V: %.2f km/s" % (vel / 1000.0)
	else:
		velocity_label.text = "V: %.1f m/s" % vel
	
	# Inclination (approximation for 2D)
	var pos_normalized = orbit.position.normalized()
	var vel_normalized = orbit.velocity.normalized() if orbit.velocity.length() > 0 else Vector2.ZERO
	var cross = pos_normalized.x * vel_normalized.y - pos_normalized.y * vel_normalized.x
	var inclination_deg = rad_to_deg(asin(clamp(cross, -1.0, 1.0)))
	inclination_label.text = "Inc: %.1f°" % inclination_deg
	
	# Distance to target
	if target_body != null:
		var dist = (ship.world_position - target_body.world_position).length()
		distance_to_target_label.text = "Rng: %s" % orbital_constants.format_distance(dist)
	else:
		distance_to_target_label.text = "Rng: ---"

func _clear_readouts() -> void:
	orbit_type_label.text = "[ NO ORBIT ]"
	altitude_label.text = "ALT: ---"
	periapsis_label.text = "Pe: ---"
	apoapsis_label.text = "Ap: ---"
	period_label.text = "T: ---"
	velocity_label.text = "V: ---"
	inclination_label.text = "Inc: ---"
	distance_to_target_label.text = "Rng: ---"

func _update_crt_flicker(delta: float) -> void:
	# Subtle phosphor flicker effect
	flicker_timer += delta
	if flicker_timer > 0.1:
		flicker_timer = 0.0
		# Random micro-flicker
		if randf() > 0.98:
			modulate = Color(0.92, 0.92, 0.92, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)

func apply_crt_highlight(label: Label, is_warning: bool = false) -> void:
	if label == null:
		return
	if is_warning:
		label.add_theme_color_override("font_color", CRT_AMBER)
		label.add_theme_color_override("font_shadow_color", Color(0.5, 0.3, 0.1, 0.4))
	else:
		label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
		label.add_theme_color_override("font_shadow_color", CRT_GLOW)