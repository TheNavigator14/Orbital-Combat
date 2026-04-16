extends Node
## Global game state manager
## Autoload singleton - access via GameManager

signal scene_changed(scene_name: String)
signal player_ship_changed(ship: Node)
signal focus_body_changed(body: Node)

# === References ===
var player_ship: Node = null
var solar_system: Node = null
var focused_body: Node = null  # Currently focused celestial body or ship

# === Game State ===
var is_in_map_view: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func register_player_ship(ship: Node) -> void:
	## Called when player ship is spawned
	player_ship = ship
	player_ship_changed.emit(ship)


func register_solar_system(system: Node) -> void:
	## Called when solar system is loaded
	solar_system = system


func set_focus(body: Node) -> void:
	## Set the currently focused body (for camera tracking)
	if focused_body != body:
		if focused_body and focused_body.has_method("deselect"):
			focused_body.deselect()

		focused_body = body

		if focused_body and focused_body.has_method("select"):
			focused_body.select()

		focus_body_changed.emit(body)


func get_sun() -> CelestialBody:
	## Get reference to the Sun
	if solar_system and solar_system.has_node("Sun"):
		return solar_system.get_node("Sun")
	return null


func get_planet(planet_name: String) -> Planet:
	## Get a planet by name
	if solar_system and solar_system.has_node(planet_name):
		return solar_system.get_node(planet_name)
	return null


func get_all_celestial_bodies() -> Array:
	## Get all celestial bodies in the solar system
	var bodies = []
	if solar_system:
		for child in solar_system.get_children():
			if child is CelestialBody:
				bodies.append(child)
	return bodies


func find_dominant_body(position: Vector2) -> CelestialBody:
	## Find which celestial body's SOI the position is within
	## Returns the most specific (smallest) SOI that contains the position

	var dominant: CelestialBody = null
	var smallest_soi = INF

	for body in get_all_celestial_bodies():
		if body is Planet:
			var distance = (position - body.world_position).length()
			if distance < body.sphere_of_influence and body.sphere_of_influence < smallest_soi:
				dominant = body
				smallest_soi = body.sphere_of_influence

	# not (If in any) planet's SOI, return the Sun
	if dominant == null:
		dominant = get_sun()

	return dominant


func sync_solar_system_to_sensor_manager() -> void:
	## Sync celestial bodies to SensorManager for line-of-sight occlusion
	## Called by SensorManager when it needs to check occlusion
	var sensor_manager = Engine.get_singleton("SensorManager") if Engine.has_singleton("SensorManager") else null
	if not sensor_manager:
		# Try to get via node path instead
		sensor_manager = get_node_or_null("/root/SensorManager")
	
	if not sensor_manager or not has_method("get_all_celestial_bodies"):
		return
	
	var bodies = get_all_celestial_bodies()
	var body_data = []
	
	for body in bodies:
		if body is CelestialBody:
			var radius = body.get("radius") if body.has("radius") else 0.0
			body_data.append({
				"body": body,
				"radius": radius
			})
	
	if sensor_manager.has_method("set_celestial_bodies"):
		sensor_manager.set_celestial_bodies(body_data)


func toggle_map_view() -> void:
	## Toggle between cockpit and map view
	is_in_map_view = not is_in_map_view
