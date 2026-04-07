class_name Sun
extends CelestialBody
## The central star of the solar system
## Stationary at the origin, all other bodies orbit around it

func _init() -> void:
	body_name = "Sun"
	mass = OrbitalConstantsClass.SUN_MASS
	radius = OrbitalConstantsClass.SUN_RADIUS
	display_color = Color(1.0, 0.9, 0.6)  # Warm yellow


func _ready() -> void:
	super._ready()
	# Sun is always at the origin
	world_position = Vector2.ZERO
	position = Vector2.ZERO


func _draw() -> void:
	# Custom sun drawing with glow effect
	var display_radius = clamp(radius * 0.000001, min_display_radius, max_display_radius)

	# Corona glow layers
	for i in range(5, 0, -1):
		var glow_radius = display_radius * (1.0 + i * 0.3)
		var alpha = 0.15 / float(i)
		draw_circle(Vector2.ZERO, glow_radius, Color(1.0, 0.8, 0.3, alpha))

	# Main body
	draw_circle(Vector2.ZERO, display_radius, display_color)

	# Bright core
	draw_circle(Vector2.ZERO, display_radius * 0.7, Color(1.0, 1.0, 0.9))

	# Selection indicator
	if is_selected:
		draw_arc(Vector2.ZERO, display_radius * 1.5, 0, TAU, 32, Color.CYAN, 2.0)
