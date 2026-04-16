class_name CelestialBody
extends Node2D
## Base class for all celestial bodies (Sun, planets, moons)
## Handles gravitational parameters and basic visualization

signal body_selected(body: CelestialBody)

# === Physical Properties ===
@export var body_name: String = "Unknown Body"
@export var mass: float = 0.0  # kg
@export var radius: float = 0.0  # meters (surface radius)
@export var display_color: Color = Color.WHITE

# === Computed Properties ===
var mu: float:  # Standard gravitational parameter (G * M)
	get:
		return OrbitalConstants.G * mass

# === Visual Settings ===
@export var min_display_radius: float = 5.0  # Minimum pixels to draw
@export var max_display_radius: float = 100.0  # Maximum pixels to draw

# === State ===
var world_position: Vector2 = Vector2.ZERO  # Position in simulation space (meters)
var is_selected: bool = false


func _ready() -> void:
	# Bodies are drawn via _draw()
	pass


func _draw() -> void:
	# Draw a simple circle representation
	# The actual display size will be controlled by the camera/scale system
	var display_radius = clamp(radius * 0.00001, min_display_radius, max_display_radius)

	# Outer glow
	draw_circle(Vector2.ZERO, display_radius * 1.2, Color(display_color, 0.3))

	# Main body
	draw_circle(Vector2.ZERO, display_radius, display_color)

	# Selection indicator
	if is_selected:
		draw_arc(Vector2.ZERO, display_radius * 1.4, 0, TAU, 32, Color.YELLOW, 2.0)


func get_sphere_of_influence(parent_mu: float, orbital_radius: float) -> float:
	## Calculate sphere of influence radius (Hill sphere approximation)
	## r_SOI = a * (m / M)^(2/5)
	if parent_mu <= 0 or orbital_radius <= 0:
		return INF  # Primary body, infinite SOI

	var mass_ratio = mu / parent_mu
	return orbital_radius * pow(mass_ratio, 0.4)


func get_escape_velocity(altitude: float = 0.0) -> float:
	## Get escape velocity at given altitude above surface
	var r = radius + altitude
	return OrbitalMechanics.calculate_escape_velocity(r, mu)


func get_circular_velocity(altitude: float) -> float:
	## Get circular orbital velocity at given altitude above surface
	var r = radius + altitude
	return OrbitalMechanics.calculate_circular_velocity(r, mu)


func get_surface_gravity() -> float:
	## Get surface gravity (m/s^2)
	return mu / (radius * radius)


func select() -> void:
	is_selected = true
	queue_redraw()
	body_selected.emit(self)


func deselect() -> void:
	is_selected = false
	queue_redraw()


func get_info_string() -> String:
	return "%s\nMass: %.2e kg\nRadius: %.0f km\ng: %.2f m/s^2" % [
		body_name,
		mass,
		radius / 1000.0,
		get_surface_gravity()
	]
