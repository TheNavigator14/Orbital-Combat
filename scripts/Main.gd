extends Node2D
## Main game scene - initializes solar system and player ship

@onready var solar_system: Node2D = $SolarSystem
@onready var tactical_display: TacticalDisplay = $CanvasLayer/TacticalDisplay
@onready var camera: OrbitalCamera = $OrbitalCamera

var player_ship: Ship = null


func _ready() -> void:
	# Register solar system with GameManager
	GameManager.register_solar_system(solar_system)

	# Set up parent reference for all planets (they all orbit the Sun)
	# Must set parent_body before initializing orbit, since Planet._ready() runs
	# before Main._ready() and can't initialize without a parent
	var sun = solar_system.get_node("Sun")
	var planets = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]
	for planet_name in planets:
		var planet = solar_system.get_node_or_null(planet_name)
		if planet:
			planet.parent_body = sun
			planet._initialize_orbit()

	# Spawn player ship in low Earth orbit
	_spawn_player_ship()

	# Set up tactical display
	tactical_display.setup(solar_system, camera)

	print("Orbital Combat initialized!")
	print("Controls:")
	print("  W/S - Prograde/Retrograde thrust")
	print("  A/D - Radial In/Out thrust")
	print("  ,/. - Decrease/Increase time warp")
	print("  Mouse wheel - Zoom")
	print("  Middle mouse - Pan")


func _spawn_player_ship() -> void:
	var earth = solar_system.get_node("Earth") as Planet

	# Create ship
	player_ship = Ship.new()
	player_ship.ship_name = "Player Ship"
	player_ship.max_thrust = 100000.0  # 100 kN
	player_ship.exhaust_velocity = 3500.0  # ~350s Isp
	player_ship.dry_mass = 10000.0  # 10 tons
	player_ship.fuel_capacity = 20000.0  # 20 tons

	add_child(player_ship)

	# Initialize in 400km circular orbit around Earth
	var altitude = 400000.0  # 400 km
	player_ship.initialize_orbit(earth, altitude, 0.0)

	# Register ship with GameManager so TacticalDisplay can find it
	GameManager.register_player_ship(player_ship)
	GameManager.set_focus(player_ship)

	print("Ship spawned in %s orbit around %s" % [
		OrbitalConstantsClass.format_distance(altitude),
		earth.body_name
	])
	print("Orbital period: %s" % OrbitalConstantsClass.format_time(player_ship.orbit_state.orbital_period))


func _unhandled_input(event: InputEvent) -> void:
	# Toggle map focus between ship and Earth
	if event.is_action_pressed("toggle_map"):
		if GameManager.focused_body == player_ship:
			var earth = solar_system.get_node("Earth")
			GameManager.set_focus(earth)
		else:
			GameManager.set_focus(player_ship)
