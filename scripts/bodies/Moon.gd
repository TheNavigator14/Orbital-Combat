class_name Moon
extends CelestialBody
## Earth's Moon - orbits Earth with proper SOI

func _ready() -> void:
	# Moon orbits Earth (parent_body should be set via scene hierarchy)
	super._ready()
	_setup_moon_orbit()


func _setup_moon_orbit() -> void:
	## Initialize Moon's orbit around Earth
	if not parent_body:
		push_error("Moon %s has no parent body (Earth)!" % body_name)
		return
	
	# Moon's orbital parameters around Earth
	orbit_state.semi_major_axis = OrbitalConstantsClass.MOON_ORBITAL_RADIUS  # ~384,400 km
	orbit_state.eccentricity = 0.0549  # Slight eccentricity
	orbit_state.argument_of_periapsis = 0.0
	orbit_state.parent_mu = parent_body.mu
	
	# Convert orbital period to starting position
	# Period = 27.3 days, start at some angle
	var start_angle = 0.0  # Starting true anomaly
	
	# Convert to eccentric anomaly then mean anomaly
	var E = OrbitalMechanics.true_to_eccentric_anomaly(start_angle, orbit_state.eccentricity)
	orbit_state.mean_anomaly_at_epoch = E - orbit_state.eccentricity * sin(E)
	orbit_state.epoch_time = 0.0
	
	# Calculate SOI - Moon's SOI around Earth is very small
	calculate_soi()
	
	# Initial position
	orbit_state.update_state_vectors(TimeManager.simulation_time)


func calculate_soi() -> void:
	## Calculate Moon's SOI - for a moon, this is tiny
	## SOI = a * (m_moon / m_earth)^(2/5)
	if not parent_body or not orbit_state:
		sphere_of_influence = 0.0
		return
	
	var a: float = abs(orbit_state.semi_major_axis)
	if a <= 0:
		sphere_of_influence = 0.0
		return
	
	var mass_ratio: float = mass / parent_body.mass
	sphere_of_influence = a * pow(mass_ratio, 2.0 / 5.0)
	
	soi_changed.emit(sphere_of_influence)


func _draw() -> void:
	# Moon surface detail
	draw_circle(Vector2.ZERO, display_radius, display_color)
	
	# Slight crater suggestion for larger display
	if display_radius > 5:
		var crater_color = Color(display_color * 0.8)
		crater_color.a = 0.5
		draw_circle(Vector2(-display_radius * 0.3, -display_radius * 0.2), display_radius * 0.2, crater_color)
		draw_circle(Vector2(display_radius * 0.2, display_radius * 0.3), display_radius * 0.15, crater_color)