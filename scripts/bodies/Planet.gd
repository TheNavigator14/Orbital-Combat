class_name Planet
extends CelestialBody
## A planet or moon that orbits a parent celestial body
## Uses Kepler propagation for orbital motion

# === Orbital Configuration ===
@export var parent_body: CelestialBody = null
@export var orbital_radius: float = 0.0  # Semi-major axis for circular, meters
@export var orbital_eccentricity: float = 0.0
@export var start_true_anomaly: float = 0.0  # Starting position in orbit (radians)

# === Orbital State ===
var orbit_state: OrbitState = null
var sphere_of_influence: float = 0.0


func _ready() -> void:
	super._ready()
	_initialize_orbit()


func _initialize_orbit() -> void:
	if parent_body == null:
		push_error("Planet %s has no parent body!" % body_name)
		return

	# Create orbit state
	orbit_state = OrbitState.new()
	orbit_state.semi_major_axis = orbital_radius
	orbit_state.eccentricity = orbital_eccentricity
	orbit_state.argument_of_periapsis = 0.0
	orbit_state.parent_mu = parent_body.mu

	# Convert starting true anomaly to mean anomaly
	var E = OrbitalMechanics.true_to_eccentric_anomaly(start_true_anomaly, orbital_eccentricity)
	orbit_state.mean_anomaly_at_epoch = E - orbital_eccentricity * sin(E)
	orbit_state.epoch_time = 0.0

	# Calculate sphere of influence
	sphere_of_influence = get_sphere_of_influence(parent_body.mu, orbital_radius)

	# Initial position update
	orbit_state.update_state_vectors(0.0)
	world_position = orbit_state.position + parent_body.world_position


func _physics_process(_delta: float) -> void:
	if orbit_state == null or parent_body == null:
		return

	# Get current simulation time from TimeManager
	var current_time = TimeManager.simulation_time

	# Update orbital position using Kepler propagation
	orbit_state.update_state_vectors(current_time)

	# World position is relative to parent
	world_position = orbit_state.position + parent_body.world_position


func get_orbital_velocity() -> Vector2:
	## Get current orbital velocity
	if orbit_state:
		return orbit_state.velocity
	return Vector2.ZERO


func get_orbital_period() -> float:
	## Get orbital period in seconds
	if orbit_state:
		return orbit_state.orbital_period
	return 0.0


func get_orbit_points(num_points: int = 100) -> PackedVector2Array:
	## Get points along the orbit for visualization
	if orbit_state:
		return orbit_state.sample_orbit_points(num_points)
	return PackedVector2Array()


func is_point_in_soi(point: Vector2) -> bool:
	## Check if a world position is within this body's sphere of influence
	var distance = (point - world_position).length()
	return distance < sphere_of_influence


func get_info_string() -> String:
	var base = super.get_info_string()
	if orbit_state:
		return base + "\nOrbit: %.2f AU\nPeriod: %.1f days\nSOI: %.0f km" % [
			orbital_radius / OrbitalConstantsClass.AU,
			orbit_state.orbital_period / OrbitalConstantsClass.SECONDS_PER_DAY,
			sphere_of_influence / 1000.0
		]
	return base


func _draw() -> void:
	var display_radius = clamp(radius * 0.00001, min_display_radius, max_display_radius)

	# Atmosphere glow (if applicable)
	draw_circle(Vector2.ZERO, display_radius * 1.1, Color(display_color, 0.2))

	# Main body
	draw_circle(Vector2.ZERO, display_radius, display_color)

	# Selection indicator
	if is_selected:
		draw_arc(Vector2.ZERO, display_radius * 1.4, 0, TAU, 32, Color.YELLOW, 2.0)
