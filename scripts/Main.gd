class_name Main
extends Node2D
## Main entry point for Orbital Combat game
## Sets up solar system, ship, time management, and UI panels

# === Scene References ===
@onready var solar_system: Node2D = null
@onready var player_ship: Ship = null
@onready var orbital_camera: Camera2D = null
@onready var tactical_display: Control = null
@onready var time_panel: Control = null
@onready var maneuver_panel: Control = null
@onready var ship_panel: Control = null
@onready var nav_panel: Control = null

# === Autoload References ===
var time_manager: Node = null
var game_manager: Node = null
var sensor_manager: Node = null  # Will be SensorManager
var orbital_constants: Node = null  # Will be OrbitalConstantsClass
var contact_display_panel: Control = null  # Sensor contacts panel

# === State ===
var is_paused: bool = false
var is_initialized: bool = false
var demo_contact_timer: float = 0.0
var demo_contact_added: bool = false

# === Panel References ===
var _maneuver_planning_panel: Control = null

# === Visual Effects ===
var visual_effects_manager: VisualEffectsManager = null
var _current_thrust_effect: ThrustParticleEffect = null
var _crt_overlay: CanvasLayer = null

func _ready() -> void:
	# Wait for tree to be ready
	await get_tree().physics_frame
	_setup_autoloads()
	_setup_scenes()
	_setup_time_manager()
	_connect_signals()
	_update_panels()
	is_initialized = true


func _setup_autoloads() -> void:
	## Get references to autoloaded singletons
	time_manager = get_node("/root/TimeManager")
	game_manager = get_node("/root/GameManager")
	sensor_manager = get_node("/root/SensorManager")
	
	# Get OrbitalConstants from project
	orbital_constants = get_node("/root/OrbitalConstants")
	
	if time_manager:
		print("TimeManager loaded: ", time_manager.name)
	if game_manager:
		print("GameManager loaded: ", game_manager.name)
	if sensor_manager:
		print("SensorManager loaded: ", sensor_manager.name)
	if orbital_constants:
		print("OrbitalConstants loaded: ", orbital_constants.name)


func _setup_scenes() -> void:
	## Find and setup scene references
	# Find solar system
	solar_system = find_child("SolarSystem", true, false)
	if solar_system == null:
		solar_system = find_node("SolarSystem", true, false)
	
	# Find player ship
	player_ship = find_child("PlayerShip", true, false)
	if player_ship == null:
		player_ship = find_node("Ship_*", true, false)  # Ships named Ship_*
	if player_ship == null:
		player_ship = find_node("Player*", true, false)
	
	# Find orbital camera
	orbital_camera = find_child("OrbitalCamera", true, false)
	if orbital_camera == null:
		orbital_camera = find_child("Camera*", true, false)
	
	# Find UI elements
	tactical_display = find_child("TacticalDisplay", true, false)
	if tactical_display == null:
		tactical_display = find_node("Tactical*", true, false)
	
	time_panel = find_child("TimePanel", true, false)
	if time_panel == null:
		time_panel = find_node("Time*", true, false)
	
	maneuver_panel = find_child("ManeuverPanel", true, false)
	if maneuver_panel == null:
		maneuver_panel = find_node("Maneuver*", true, false)
	
	ship_panel = find_child("ShipPanel", true, false)
	if ship_panel == null:
		ship_panel = find_node("Ship*", true, false)
	
	nav_panel = find_child("NavPanel", true, false)
	if nav_panel == null:
		nav_panel = find_node("Nav*", true, false)
	
	contact_display_panel = find_child("ContactDisplayPanel", true, false)
	if contact_display_panel == null:
		contact_display_panel = find_node("Contact*", true, false)
	
	_maneuver_planning_panel = find_child("ManeuverPlanningPanel", true, false)
	if _maneuver_planning_panel == null:
		_maneuver_planning_panel = find_node("ManeuverPlanning*", true, false)
	
	# Find sensor mode panel
	sensor_mode_panel = find_child("SensorModePanel", true, false)
	if sensor_mode_panel == null:
		sensor_mode_panel = find_node("SensorMode*", true, false)
	
	if sensor_mode_panel and sensor_mode_panel.has_method("set_sensor_manager"):
		sensor_mode_panel.set_sensor_manager(sensor_manager)
	
	# Find ship status panel
	ship_status_panel = find_child("ShipStatusPanel", true, false)
	if ship_status_panel == null:
		ship_status_panel = find_node("ShipStatus*", true, false)
	
	# Link ship to tactical display
	if player_ship and tactical_display:
		tactical_display.set_player_ship(player_ship)
		_wire_sensor_to_tactical_display()
	
	# Link ship to status panel
	if player_ship and ship_status_panel:
		if ship_status_panel.has_method("set_player_ship"):
			ship_status_panel.set_player_ship(player_ship)
		# Connect ship signals to status panel
		if player_ship.has_signal("fuel_depleted"):
			player_ship.fuel_depleted.connect(ship_status_panel._on_fuel_depleted)
		if player_ship.has_signal("health_changed"):
			player_ship.health_changed.connect(ship_status_panel._on_health_changed)
		if player_ship.has_signal("thrust_changed"):
			player_ship.thrust_changed.connect(ship_status_panel._on_thrust_changed)
		if player_ship.has_signal("system_damaged"):
			player_ship.system_damaged.connect(ship_status_panel._on_system_damaged)
		if player_ship.has_signal("system_destroyed"):
			player_ship.system_destroyed.connect(ship_status_panel._on_system_destroyed)
	
	# Link sensor manager to contact panel
	if sensor_manager and contact_display_panel:
		contact_display_panel.set_sensor_manager(sensor_manager)
	
	# Register player ship with sensor manager for thermal tracking
	if sensor_manager and player_ship and sensor_manager.has_method("register_ship"):
		sensor_manager.register_ship(player_ship)
		print("Main: Registered player ship with SensorManager for thermal tracking")
	
	_print_status()


func _wire_sensor_to_tactical_display() -> void:
	## Connect SensorManager to TacticalDisplay for contact markers
	if sensor_manager == null or tactical_display == null:
		return
	
	# Set sensor manager on tactical display
	if tactical_display.has_method("set_sensor_manager"):
		tactical_display.set_sensor_manager(sensor_manager)
	
	# Connect sensor signals for real-time updates
	if sensor_manager.has_signal("contact_detected"):
		sensor_manager.contact_detected.connect(_on_contact_detected)
	
	if sensor_manager.has_signal("contact_lost"):
		sensor_manager.contact_lost.connect(_on_contact_lost)
	
	if sensor_manager.has_signal("contact_updated"):
		sensor_manager.contact_updated.connect(_on_contact_updated)
	
	print("SensorManager connected to TacticalDisplay")


func _on_contact_detected(contact) -> void:
	## Handle new contact detected
	print("Contact detected on tactical display: ", contact.get_display_name())
	if tactical_display and tactical_display.has_method("refresh_contact_display"):
		tactical_display.refresh_contact_display()


func _on_contact_lost(contact) -> void:
	## Handle contact lost
	print("Contact lost: ", contact.get_display_name())
	if tactical_display and tactical_display.has_method("refresh_contact_display"):
		tactical_display.refresh_contact_display()


func _on_contact_updated(contact) -> void:
	## Handle contact updated
	if tactical_display and tactical_display.has_method("queue_redraw"):
		tactical_display.queue_redraw()


func _setup_time_manager() -> void:
	## Setup time manager if available
	if time_manager == null:
		return
	
	# TimeManager should auto-start
	if time_manager.has_method("set_paused"):
		time_manager.set_paused(false)


func _connect_signals() -> void:
	## Connect UI and game signals
	if player_ship:
		player_ship.thrust_started.connect(_on_player_thrust_started)
		player_ship.thrust_ended.connect(_on_player_thrust_ended)
		player_ship.fuel_depleted.connect(_on_player_fuel_depleted)
		player_ship.maneuver_started.connect(_on_maneuver_started)
		player_ship.maneuver_completed.connect(_on_maneuver_completed)
	
	if time_manager:
		time_manager.time_warped.connect(_on_time_warped)
		time_manager.warp_level_changed.connect(_on_warp_level_changed)
	
	# Connect sensor manager if available
	if sensor_manager and player_ship:
		if sensor_manager.has_method("initialize"):
			sensor_manager.initialize(player_ship)
		
		# Connect ship signals to sensor manager
		if player_ship.has_signal("thrust_started"):
			player_ship.thrust_started.connect(_on_ship_thrust_started)
		if player_ship.has_signal("thrust_ended"):
			player_ship.thrust_ended.connect(_on_ship_thrust_ended)


func _on_player_thrust_started() -> void:
	## Called when player ship starts thrusting
	print("Player started thrusting")
	_update_panels()


func _on_player_thrust_ended() -> void:
	## Called when player ship stops thrusting
	print("Player stopped thrusting")
	_update_panels()


func _on_player_fuel_depleted() -> void:
	## Called when ship runs out of fuel
	print("WARNING: Fuel depleted!")
	_show_notification("FUEL DEPLETED - NO THRUST AVAILABLE")


func _on_maneuver_started(node: ManeuverNode) -> void:
	## Called when a maneuver begins
	print("Maneuver started: ", node.get_description())


func _on_maneuver_completed(node: ManeuverNode) -> void:
	## Called when a maneuver completes
	print("Maneuver completed: ", node.get_description())


func _on_time_warped(seconds: float) -> void:
	## Called after time warping
	_update_panels()


func _on_warp_level_changed(level: int) -> void:
	## Called when warp level changes
	_update_panels()


func _on_ship_thrust_started() -> void:
	## Ship started thrusting - create visible contact on sensors
	if sensor_manager and player_ship and not thrusting_contact_added:
		thrusting_contact_added = true
		_create_thrust_contact()


func _create_thrust_contact() -> void:
	## Create a contact marker when player is thrusting
	if sensor_manager == null or player_ship == null:
		return
	
	var thrust_marker: Node2D = Node2D.new()
	thrust_marker.name = "PlayerThrustMarker"
	thrust_marker.position = player_ship.world_position
	add_child(thrust_marker)
	
	# High heat signature when thrusting
	thrust_marker.set("current_heat_output", 1.0)
	
	if sensor_manager.has_method("register_ship"):
		sensor_manager.register_ship(thrust_marker)
	
	var contact = sensor_manager.get_or_create_contact(thrust_marker)
	if contact:
		contact.thermal_signal_strength = 1.0
		contact.is_thermally_detected = true
		contact.status = SensorManager.ContactStatus.UNKNOWN
		contact.contact_name = "YOUR SHIP"
		sensor_manager.contact_detected.emit(contact)
		print("Main: Player thrust contact created")
	
	player_thrust_marker = thrust_marker


var thrusting_contact_added: bool = false
var player_thrust_marker: Node2D = null


func _on_ship_thrust_ended() -> void:
	## Ship stopped thrusting - remove visible contact
	thrusting_contact_added = false
	if player_thrust_marker and is_instance_valid(player_thrust_marker):
		if sensor_manager and sensor_manager.has_method("unregister_ship"):
			sensor_manager.unregister_ship(player_thrust_marker)
		player_thrust_marker.queue_free()
		player_thrust_marker = null


func _update_panels() -> void:
	## Update all cockpit panels with current data
	if ship_panel and player_ship:
		_update_ship_panel()
	
	if nav_panel and player_ship:
		_update_nav_panel()
	
	if maneuver_panel and player_ship:
		_update_maneuver_panel()
	
	if time_panel and time_manager:
		_update_time_panel()


func _update_ship_panel() -> void:
	## Update ship status panel
	if ship_panel == null:
		return
	
	# Update fuel gauge
	var fuel_label = ship_panel.find_child("FuelLabel", true, false)
	if fuel_label:
		fuel_label.text = "%.1f%%" % player_ship.get_fuel_percent()
	
	# Update delta-v display
	var dv_label = ship_panel.find_child("DeltaVLabel", true, false)
	if dv_label:
		dv_label.text = "%.1f m/s" % player_ship.delta_v_remaining
	
	# Update thrust status
	var thrust_label = ship_panel.find_child("ThrustStatusLabel", true, false)
	if thrust_label:
		thrust_label.text = player_ship.get_thrust_status_string()


func _update_nav_panel() -> void:
	## Update navigation panel
	if nav_panel == null or player_ship == null or player_ship.orbit_state == null:
		return
	
	var orbit = player_ship.orbit_state
	var parent = player_ship.parent_body
	
	# Update altitude
	var alt_label = nav_panel.find_child("AltitudeLabel", true, false)
	if alt_label and parent:
		var altitude = player_ship.altitude_above_parent
		alt_label.text = OrbitalConstants.format_distance(altitude)
	
	# Update orbital velocity
	var vel_label = nav_panel.find_child("VelocityLabel", true, false)
	if vel_label:
		vel_label.text = OrbitalConstants.format_velocity(orbit.current_speed)
	
	# Update apoapsis/periapsis
	var ap_label = nav_panel.find_child("ApoapsisLabel", true, false)
	if ap_label and parent:
		var apoapsis = orbit.apoapsis_altitude(parent)
		ap_label.text = OrbitalConstants.format_distance(apoapsis)
	
	var pe_label = nav_panel.find_child("PeriapsisLabel", true, false)
	if pe_label and parent:
		var periapsis = orbit.periapsis_altitude(parent)
		pe_label.text = OrbitalConstants.format_distance(periapsis)


func _update_maneuver_panel() -> void:
	## Update maneuver panel
	if maneuver_panel == null or player_ship == null:
		return
	
	var next_maneuver = player_ship.current_maneuver
	
	if next_maneuver:
		var dv_label = maneuver_panel.find_child("DeltaVLabel", true, false)
		if dv_label:
			var total_dv = next_maneuver.get_total_delta_v()
			dv_label.text = "%.1f m/s" % total_dv
		
		var time_label = maneuver_panel.find_child("TimeLabel", true, false)
		if time_label and time_manager:
			var time_to_maneuver = next_maneuver.time - time_manager.simulation_time
			if time_to_maneuver > 0:
				time_label.text = OrbitalConstants.format_time(time_to_maneuver)
			else:
				time_label.text = "NOW"
	else:
		var dv_label = maneuver_panel.find_child("DeltaVLabel", true, false)
		if dv_label:
			dv_label.text = "---"
		
		var time_label = maneuver_panel.find_child("TimeLabel", true, false)
		if time_label:
			time_label.text = "---"


func _update_time_panel() -> void:
	## Update time display panel
	if time_panel == null or time_manager == null:
		return
	
	var time_label = time_panel.find_child("TimeLabel", true, false)
	if time_label:
		time_label.text = OrbitalConstants.format_timestamp(time_manager.simulation_time)
	
	var warp_label = time_panel.find_child("WarpLabel", true, false)
	if warp_label:
		if time_manager.current_warp_level > 1:
			warp_label.text = "%dx" % time_manager.current_warp_level
		else:
			warp_label.text = "1x"


func _print_status() -> void:
	## Print current game status
	print("\n=== GAME STATUS ===")
	print("Solar System: ", "OK" if solar_system else "MISSING")
	print("Player Ship: ", "OK" if player_ship else "MISSING")
	print("Orbital Camera: ", "OK" if orbital_camera else "MISSING")
	print("Tactical Display: ", "OK" if tactical_display else "MISSING")
	print("Sensor Manager: ", "OK" if sensor_manager else "MISSING")
	print("Contact Display: ", "OK" if contact_display_panel else "MISSING")
	print("Time Panel: ", "OK" if time_panel else "MISSING")
	print("Maneuver Panel: ", "OK" if maneuver_panel else "MISSING")
	print("Ship Panel: ", "OK" if ship_panel else "MISSING")
	print("Nav Panel: ", "OK" if nav_panel else "MISSING")
	print("====================\n")


func _show_notification(message: String) -> void:
	## Show a notification to the player
	print("NOTIFICATION: ", message)
	# Could show a popup or on-screen message here


func _process(delta: float) -> void:
	## Update loop
	if not is_initialized:
		return
	
	# Add demo contact for testing (after 2 seconds)
	if not demo_contact_added and demo_contact_timer > 2.0:
		_add_demo_contact()
		demo_contact_added = true
	
	demo_contact_timer += delta
	
	# Update panels periodically
	_update_panels()


func _add_demo_contact() -> void:
	## Add a demo contact ship for testing thermal detection visualization
	## Creates a proper ship with heat signature that can be detected
	if sensor_manager == null:
		return
	
	# Create a demo NPC ship at distance from player
	var demo_ship: Node2D = Node2D.new()
	demo_ship.name = "DemoNPCShip"
	add_child(demo_ship)
	
	# Position at a distance from player ship
	if player_ship:
		# Place 300km away - within thermal detection range when hot
		demo_ship.position = player_ship.world_position + Vector2(300000.0, 100000.0)
	
	# Add required properties for heat signature tracking
	demo_ship.set("current_heat_output", 0.5)  # Medium heat - detectable
	
	# Register with sensor manager for thermal tracking
	if sensor_manager.has_method("register_ship"):
		sensor_manager.register_ship(demo_ship)
		print("Main: Created demo NPC ship with heat signature at: ", demo_ship.position)
	
	# Also create a contact for immediate detection
	var contact = sensor_manager.get_or_create_contact(demo_ship)
	if contact:
		contact.thermal_signal_strength = 0.5
		contact.is_thermally_detected = true
		contact.status = SensorManager.ContactStatus.UNKNOWN
		contact.contact_name = "Demo NPC Ship"
		print("Demo NPC ship contact created")
	
	# Store reference to demo ship for future thrust simulation
	demo_npc_ship = demo_ship


# Demo NPC ship reference for thrust simulation
var demo_npc_ship: Node2D = null

# Enemy ships
var enemy_ships: Array = []


func spawn_enemy_ship(orbit_body: CelestialBody = null, ship_type: int = 0) -> EnemyAIShip:
	## Spawn an enemy AI ship
	## orbit_body: The body to orbit (uses Earth by default)
	## ship_type: 0=standard, 1=aggressive, 2=stealth
	var enemy_scene_path = "res://scenes/bodies/EnemyShip.tscn"
	
	var enemy: EnemyAIShip
	if ResourceLoader.exists(enemy_scene_path):
		var enemy_instance = load(enemy_scene_path).instantiate()
		if enemy_instance is EnemyAIShip:
			enemy = enemy_instance
		else:
			enemy = Node2D.new()
			enemy.set_script(load("res://scripts/ship/EnemyAIShip.gd"))
	else:
		enemy = Node2D.new()
		enemy.set_script(load("res://scripts/ship/EnemyAIShip.gd"))
	
	enemy.name = "Enemy_%d" % (enemy_ships.size() + 1)
	
	# Configure based on type
	match ship_type:
		1:  # Aggressive
			enemy.aggressive = true
			enemy.patient = false
			enemy.evasion_timer = 5.0
		2:  # Stealth
			enemy.base_heat_signature = 0.01
			enemy.thrust_heat_output = 0.5
			enemy.detection_reaction_time = 8.0
	
	# Position in orbit
	if orbit_body:
		enemy.parent_body = orbit_body
		var orbit_radius = orbit_body.radius + 300000.0 + randf() * 200000.0
		var angle = randf() * TAU
		
		if enemy.orbit_state == null:
			var mu = orbit_body.mu if orbit_body.has("mu") else OrbitalConstants.SUN_MU
			enemy.orbit_state = OrbitState.new()
			enemy.orbit_state.semi_major_axis = orbit_radius
			enemy.orbit_state.eccentricity = 0.1 + randf() * 0.2
			enemy.orbit_state.true_anomaly = angle
		
		add_child(enemy)
		enemy_ships.append(enemy)
		
		# Register with sensor manager for detection
		if sensor_manager and sensor_manager.has_method("register_ship"):
			sensor_manager.register_ship(enemy)
		
		print("Main: Spawned enemy ship at orbit around ", orbit_body.body_name if "body_name" in orbit_body else "unknown")
	else:
		# Default spawn position
		enemy.position = Vector2(120000000, 40000000)
		add_child(enemy)
		enemy_ships.append(enemy)
		
		if sensor_manager and sensor_manager.has_method("register_ship"):
			sensor_manager.register_ship(enemy)
		
		print("Main: Spawned enemy ship at default position")
	
	return enemy


func spawn_enemy_wave(count: int = 3, orbit_body: CelestialBody = null) -> Array:
	## Spawn a wave of enemy ships
	var enemies: Array = []
	for i in range(count):
		var ship_type = i % 3
		var enemy = spawn_enemy_ship(orbit_body, ship_type)
		enemies.append(enemy)
	return enemies