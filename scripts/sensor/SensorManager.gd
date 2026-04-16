class_name SensorManager
extends Node
## Manages thermal and radar sensors for ship detection
## Autoload singleton - access via SensorManager

signal contact_detected(contact: SensorContact)
signal contact_updated(contact: SensorContact)
signal contact_lost(contact: SensorContact)
signal thermal_contact_detected(contact: SensorContact)

# === Sensor Configuration ===
@export var thermal_range: float = 500000.0  # meters - passive thermal detection range
@export var radar_range: float = 1000000.0  # meters - active radar detection range
@export var radar_tracking_range: float = 500000.0  # meters - close range tracking
@export var thermal_detection_threshold: float = 0.1  # minimum signal strength
@export var radar_detection_threshold: float = 0.05  # minimum signal strength

# === Thermal Detection Parameters ===
@export var thermal_base_range: float = 100000.0  # Base detection range for 1.0 heat signature
@export var thermal_falloff_exponent: float = 1.5  # Signal falloff with distance (inverse square law ~2, but tuned for gameplay)
@export var min_thermal_signature: float = 0.05  # Minimum detectable heat signature

# === Player Sensor State ===
var active_scan_mode: int = SensorMode.PASSIVE  # Current sensor mode
var thermal_signal_strength: float = 0.0  # 0.0 to 1.0
var radar_signal_strength: float = 0.0  # 0.0 to 1.0

# === Detected Contacts ===
var detected_contacts: Dictionary = {}  # contact_id -> SensorContact
var thermal_contacts: Array = []  # Contacts detected via thermal (passive)

# === Reference to player ship ===
var player_ship: Ship = null

# === Celestial bodies for line-of-sight occlusion ===
var celestial_bodies: Array = []  # Array of {body: Node2D, radius: float}


# === Sensor Modes ===
enum SensorMode {
	PASSIVE = 0,  # Thermal only, no emissions
	RADAR = 1,    # Active radar, high detection but reveals position
	ACTIVE = 2    # Active scan, moderate detection
}

# === Contact Status ===
enum ContactStatus {
	UNKNOWN = 0,      # Detected but not identified
	INVESTIGATING = 1, # Under investigation
	IDENTIFIED = 2,    # Positively identified
	LOST = 3           # Contact lost
}

# === Ship Class Categories (for identification) ===
enum ShipClass {
	UNKNOWN = 0,
	CIVILIAN = 1,
	PROBE = 2,
	FIGHTER = 3,
	FRIGATE = 4,
	DESTROYER = 5,
	CARRIER = 6,
	FREIGHTER = 7
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Get stealth manager reference
	stealth_manager = get_node("/root/StealthManager") if has_node("/root/StealthManager") else null


func initialize(player: Ship) -> void:
	player_ship = player
	if player_ship.has_signal("thrust_started"):
		player_ship.thrust_started.connect(_on_player_thrust_started)
	if player_ship.has_signal("thrust_ended"):
		player_ship.thrust_ended.connect(_on_player_thrust_ended)


# === Ship Tracking for Thermal Detection ===

var tracked_ships: Array = []  # Ships being tracked for thermal detection


func register_ship(ship: Node) -> void:
	## Register a ship to be tracked for thermal detection
	if not tracked_ships.has(ship):
		tracked_ships.append(ship)
		print("SensorManager: Registered ship for tracking: ", ship.name if "name" in ship else "unknown")


func unregister_ship(ship: Node) -> void:
	## Unregister a ship from thermal tracking
	tracked_ships.erase(ship)
	
	# Also remove its contact
	for contact_id in detected_contacts.keys():
		var contact: SensorContact = detected_contacts[contact_id]
		if contact.body == ship:
			detected_contacts.erase(contact_id)
			thermal_contacts.erase(contact)
			contact_lost.emit(contact)
			break


func _process(delta: float) -> void:
	## Update sensor detection (thermal and radar) each frame
	if player_ship == null:
		return
	
	# === Thermal Detection (Passive) ===
	_update_thermal_detection()
	
	# === Radar Detection (Active) ===
	_update_radar_detection(delta)


func _update_thermal_detection() -> void:
	## Update passive thermal detection for all tracked ships
	for ship in tracked_ships:
		if not is_instance_valid(ship):
			continue
		
		# Get ship's heat signature
		var heat_signature: float = _get_ship_heat_signature(ship)
		
		# Get ship position
		var ship_pos: Vector2 = _get_ship_position(ship)
		
		# Calculate distance to player
		var distance: float = (ship_pos - player_ship.world_position).length()
		
		# Check for line of sight
		if not check_line_of_sight(player_ship.world_position, ship_pos):
			continue
		
		# Update or create contact with heat signature
		var contact: SensorContact = get_or_create_contact(ship)
		if contact:
			contact.thermal_signal_strength = heat_signature
			contact.is_thermally_detected = heat_signature >= min_thermal_signature
		
		# Check if ship should be detected based on heat and distance
		# Now uses dynamic detection range from HeatManager
		var should_detect: bool = _should_detect_from_thermal(heat_signature, distance, ship)
		
		if should_detect:
			# Thermal detection threshold check
			var signal_strength: float = _calculate_thermal_signal(heat_signature, distance)
			if signal_strength >= thermal_detection_threshold:
				if not detected_contacts.has(ship.get_instance_id()):
					# New contact detected
					var new_contact: SensorContact = get_or_create_contact(ship)
					if new_contact:
						new_contact.thermal_signal_strength = signal_strength
						new_contact.is_thermally_detected = true
						new_contact.contact_name = ship.name if "name" in ship else "Unknown Ship"
						new_contact.heat_state = _get_ship_heat_state(ship)
						thermal_contact_detected.emit(new_contact)
						contact_detected.emit(new_contact)
						print("SensorManager: Thermal contact detected - ", new_contact.contact_name, 
							" signal=", signal_strength, " heat=", heat_signature)


func _update_radar_detection(delta: float) -> void:
	## Update active radar detection and tracking
	if active_scan_mode != SensorMode.RADAR:
		return
	
	for ship in tracked_ships:
		if not is_instance_valid(ship):
			continue
		
		# Get ship position
		var ship_pos: Vector2 = _get_ship_position(ship)
		var distance: float = (ship_pos - player_ship.world_position).length()
		
		# Check for line of sight
		if not check_line_of_sight(player_ship.world_position, ship_pos):
			# Radar can be blocked by line of sight
			_radar_contact_lost(ship)
			continue
		
		# Check if within radar detection range
		var radar_signal: float = _calculate_radar_signal(distance)
		if radar_signal >= radar_detection_threshold:
			# Get or create contact
			var contact: SensorContact = get_or_create_contact(ship)
			if contact:
				contact.is_radar_detected = true
				contact.radar_signal_strength = radar_signal
				
				# Check for new radar detection
				if not contact.was_previously_detected or not contact.is_radar_detected:
					radar_contact_detected.emit(contact)
					print("SensorManager: Radar contact detected - ", ship.name if "name" in ship else "Unknown")
				
				# Update radar tracking if in tracking range
				if distance <= radar_tracking_range:
					if not contact.is_radar_tracked:
						contact.is_radar_tracked = true
						contact.status = ContactStatus.IDENTIFIED
						radar_lock_acquired.emit(contact)
						print("SensorManager: Radar lock acquired - ", ship.name if "name" in ship else "Unknown")
					else:
						# Update target awareness for tracked contacts
						_update_target_awareness(contact, delta)
				else:
					# Out of tracking range - release lock
					if contact.is_radar_tracked:
						contact.is_radar_tracked = false
						radar_lock_lost.emit(contact)
		else:
			# Below detection threshold - lose contact gradually
			_radar_contact_fading(ship, delta)


func _calculate_radar_signal(distance: float) -> float:
	## Calculate radar signal strength based on distance
	if distance <= 0.0:
		return 1.0
	if distance > radar_range:
		return 0.0
	
	# Inverse square law falloff
	var normalized_distance: float = distance / radar_range
	return pow(1.0 - normalized_distance, 2.0)


func _radar_contact_detected(ship: Node) -> void:
	## Handle new radar contact detection
	var contact: SensorContact = get_or_create_contact(ship)
	if contact:
		contact.is_radar_detected = true
		contact.radar_signal_strength = 0.5  # Initial signal strength
		contact.contact_name = ship.name if "name" in ship else "Unknown Contact"
		if contact.status == ContactStatus.UNKNOWN:
			contact.status = ContactStatus.INVESTIGATING
		contact_detected.emit(contact)


func _radar_contact_lost(ship: Node) -> void:
	## Handle radar contact loss due to occlusion
	var contact: SensorContact = get_contact(ship)
	if contact and contact.is_radar_detected:
		contact.is_radar_detected = false
		contact.is_radar_tracked = false
		if contact.status == ContactStatus.IDENTIFIED:
			contact.status = ContactStatus.LOST
		radar_lock_lost.emit(contact)


func _radar_contact_fading(ship: Node, delta: float) -> void:
	## Handle radar contact fading when out of range
	var contact: SensorContact = get_contact(ship)
	if contact and contact.is_radar_detected:
		contact.radar_signal_strength -= delta * 0.2
		if contact.radar_signal_strength <= 0.0:
			contact.is_radar_detected = false
			if contact.is_radar_tracked:
				contact.is_radar_tracked = false
				radar_lock_lost.emit(contact)


func _update_target_awareness(contact: SensorContact, delta: float) -> void:
	## Update target awareness when being scanned/tracked
	# Awareness increases while being tracked
	contact.target_awareness = min(1.0, contact.target_awareness + delta * 0.5)
	
	# Emit awareness event if crossing threshold
	if contact.target_awareness >= 0.7 and not contact.is_aware_of_player:
		contact.is_aware_of_player = true
		target_aware_of_player.emit(contact)
		print("SensorManager: Target is aware of player!")
	
	# Update status based on awareness
	if contact.target_awareness >= 0.9 and contact.status == ContactStatus.INVESTIGATING:
		contact.status = ContactStatus.IDENTIFIED


func _get_ship_heat_signature(ship: Node) -> float:
	## Get the thermal heat signature of a ship
	# Check if ship has dedicated HeatManager component (priority)
	var heat_manager: Node = _get_ship_heat_manager(ship)
	if heat_manager and heat_manager.has_method("get_heat_level"):
		return heat_manager.get_heat_level()
	
	# Check if ship has thermal signature method (from Ship.gd)
	if ship.has_method("get_thermal_signature"):
		return ship.get_thermal_signature()
	
	# Check if it's a Ship object with heat output property
	if ship.has("current_heat_output"):
		return ship.current_heat_output
	
	# Default cold signature
	return 0.05


func _get_ship_heat_manager(ship: Node) -> Node:
	## Get the HeatManager child node of a ship if it exists
	if ship.has_method("get_heat_manager"):
		return ship.get_heat_manager()
	
	# Check for child node named "HeatManager"
	if ship.has_node("HeatManager"):
		return ship.get_node("HeatManager")
	
	return null


func _get_ship_detection_range(ship: Node) -> float:
	## Get the detection range for a ship based on its heat state
	var heat_manager: Node = _get_ship_heat_manager(ship)
	if heat_manager and heat_manager.has_method("get_detection_range"):
		return heat_manager.get_detection_range()
	
	# Fallback to default range based on heat signature
	var heat_sig: float = _get_ship_heat_signature(ship)
	return thermal_base_range * heat_sig


func _get_ship_heat_state(ship: Node) -> int:
	## Get the heat state of a ship as a string for UI display
	var heat_manager: Node = _get_ship_heat_manager(ship)
	if heat_manager and heat_manager.has_method("get_state_string"):
		var state_str: String = heat_manager.get_state_string()
		match state_str:
			"COLD":
				return 0
			"WARM":
				return 1
			"HOT":
				return 2
			"CRITICAL":
				return 3
		return 0
	
	# Fallback based on heat signature
	var heat_sig: float = _get_ship_heat_signature(ship)
	if heat_sig < 0.2:
		return 0  # COLD
	elif heat_sig < 0.6:
		return 1  # WARM
	elif heat_sig < 0.9:
		return 2  # HOT
	else:
		return 3  # CRITICAL


func _calculate_detection_probability(heat_signature: float, distance: float, ship: Node) -> float:
	## Calculate probability of detection based on heat state and distance
	## Uses HeatManager's detection range when available for realistic probabilities
	var detection_range: float = _get_ship_detection_range(ship)
	
	# Beyond maximum detection range - no chance
	if distance > detection_range * 1.5:
		return 0.0
	
	# Within detection range - high probability
	if distance <= detection_range * 0.3:
		return 1.0
	
	# Between 30% and 150% of range - decreasing probability
	var normalized_distance: float = distance / detection_range
	var probability: float = 1.0 - ((normalized_distance - 0.3) / 1.2)
	
	# Apply noise factor for realism (simulating sensor anomalies)
	probability *= (0.9 + randf() * 0.2)
	
	return clamp(probability, 0.0, 1.0)


func _get_ship_position(ship: Node) -> Vector2:
	## Get world position of a ship
	if ship.has_method("world_position"):
		return ship.world_position
	elif ship.has_method("get_position"):
		return ship.get_position()
	elif ship is Node2D:
		return ship.position
	return Vector2.ZERO


func _should_detect_from_thermal(heat_signature: float, distance: float, ship: Node = null) -> bool:
	## Determine if a ship with given heat signature at given distance should be detectable
	## Uses dynamic detection range from HeatManager when available
	# Too far (use extended range for hot ships)
	var max_range: float = thermal_base_range * 8.0  # Extended for CRITICAL heat state
	if distance > max_range:
		return false
	
	# Too cold - use HeatManager state for better threshold
	if heat_signature < 0.05:  # Minimum detectable heat
		return false
	
	# Use dynamic detection range when ship reference available
	if ship != null:
		var detection_prob: float = _calculate_detection_probability(heat_signature, distance, ship)
		# Add some randomness for realistic sensor behavior
		return randf() < detection_prob
	
	# Fallback to static signal strength check
	var signal: float = _calculate_thermal_signal(heat_signature, distance)
	return signal >= thermal_detection_threshold


func _calculate_thermal_signal(heat_signature: float, distance: float) -> float:
	## Calculate thermal signal strength at given distance
	if distance <= 0.0:
		return heat_signature
	
	var normalized_distance: float = distance / thermal_base_range
	var falloff: float = pow(max(normalized_distance, 0.01), thermal_falloff_exponent)
	
	return heat_signature * falloff


# === Celestial Body Management for Occlusion ===

func set_celestial_bodies(bodies: Array) -> void:
	## Set the list of celestial bodies for occlusion checking
	## bodies: Array of {body: Node2D, radius: float} or Node2D with radius property
	celestial_bodies.clear()
	for body in bodies:
		if body is Dictionary:
			celestial_bodies.append({
				"body": body.get("body"),
				"radius": body.get("radius", 0.0)
			})
		elif body.has_method("get_radius"):
			celestial_bodies.append({
				"body": body,
				"radius": body.get_radius()
			})
		elif body is Node2D and body.has("radius"):
			celestial_bodies.append({
				"body": body,
				"radius": body.radius
			})


func add_celestial_body(body: Node2D, radius: float) -> void:
	## Add a single celestial body for occlusion checking
	celestial_bodies.append({
		"body": body,
		"radius": radius
	})


func sync_celestial_bodies_from_gamemanager() -> void:
	## Sync celestial bodies from GameManager (called on scene load)
	if Engine.has_singleton("GameManager"):
		GameManager.sync_solar_system_to_sensor_manager()


func _ensure_celestial_bodies_loaded() -> void:
	## Ensure celestial bodies are loaded for LOS checking
	if celestial_bodies.size() == 0 and Engine.has_singleton("GameManager"):
		sync_celestial_bodies_from_gamemanager()


func remove_celestial_body(body: Node2D) -> void:
	## Remove a celestial body from occlusion checking
	for i in range(celestial_bodies.size() - 1, -1, -1):
		if celestial_bodies[i].body == body:
			celestial_bodies.remove_at(i)
			break


func check_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
	## Check if there's a clear line of sight between two positions
	## Returns true if no celestial body blocks the view
	if celestial_bodies.size() == 0:
		return true
	
	for body_data in celestial_bodies:
		var body: Node2D = body_data.body
		var radius: float = body_data.radius
		
		if not is_instance_valid(body):
			continue
		
		# Get body position
		var body_pos: Vector2
		if body.has_method("get_position"):
			body_pos = body.get_position()
		else:
			body_pos = body.position
		
		# Check if the line segment from_pos to to_pos intersects the body's sphere
		if _line_intersects_circle(from_pos, to_pos, body_pos, radius):
			return false
	
	return true


func _line_intersects_circle(p1: Vector2, p2: Vector2, center: Vector2, radius: float) -> bool:
	## Check if line segment p1-p2 intersects a circle centered at center with given radius
	## Uses geometric test for line-circle intersection
	
	var d: Vector2 = p2 - p1
	var f: Vector2 = p1 - center
	
	var a: float = d.dot(d)
	var b: float = 2.0 * f.dot(d)
	var c: float = f.dot(f) - radius * radius
	
	var discriminant: float = b * b - 4.0 * a * c
	
	if discriminant < 0.0:
		return false
	
	discriminant = sqrt(discriminant)
	
	var t1: float = (-b - discriminant) / (2.0 * a)
	var t2: float = (-b + discriminant) / (2.0 * a)
	
	# Check if intersection point is within the line segment
	if (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0):
		return true
	
	# Also check if endpoints are inside the circle
	var d1: float = (p1 - center).length_squared()
	var d2: float = (p2 - center).length_squared()
	
	if d1 <= radius * radius or d2 <= radius * radius:
		return true
	
	return false


func check_occlusion_to_contact(contact: SensorContact) -> bool:
	## Check if a contact is occluded by any celestial body
	## Returns true if blocked (not visible), false if visible
	if player_ship == null or not is_instance_valid(contact) or not is_instance_valid(contact.body):
		return false
	
	var player_pos: Vector2
	var contact_pos: Vector2
	
	if player_ship.has_method("get_position"):
		player_pos = player_ship.get_position()
	else:
		player_pos = player_ship.position
	
	if contact.body.has_method("get_position"):
		contact_pos = contact.body.get_position()
	elif contact.body is Node2D:
		contact_pos = contact.body.position
	else:
		return false
	
	return not check_line_of_sight(player_pos, contact_pos)


func get_occluding_body(from_pos: Vector2, to_pos: Vector2) -> Node2D:
	## Get the first celestial body that blocks line of sight, or null if clear
	for body_data in celestial_bodies:
		var body: Node2D = body_data.body
		var radius: float = body_data.radius
		
		if not is_instance_valid(body):
			continue
		
		var body_pos: Vector2
		if body.has_method("get_position"):
			body_pos = body.get_position()
		else:
			body_pos = body.position
		
		if _line_intersects_circle(from_pos, to_pos, body_pos, radius):
			return body
	
	return null


# === Contact Management ===

func get_or_create_contact(body: Node) -> SensorContact:
	## Get or create a sensor contact for a celestial body or ship
	if not body.has_method("get_detection_signature"):
		return null
	
	var contact_id = body.get_instance_id()
	
	if detected_contacts.has(contact_id):
		return detected_contacts[contact_id]
	
	var contact = SensorContact.new()
	contact.body = body
	contact.contact_id = contact_id
	contact.sensor_manager = self
	
	detected_contacts[contact_id] = contact
	contact_detected.emit(contact)
	
	return contact


func remove_contact(body: Node) -> void:
	var contact_id = body.get_instance_id()
	if detected_contacts.has(contact_id):
		var contact = detected_contacts[contact_id]
		detected_contacts.erase(contact_id)
		contact_lost.emit(contact)
		
		if contact in thermal_contacts:
			thermal_contacts.erase(contact)


# === Distance Detection ===

func _process(delta: float) -> void:
	## Check for contacts within sensor range
	if player_ship == null:
		return
	
	var player_pos = player_ship.world_position
	var check_range = thermal_range if active_scan_mode == SensorMode.PASSIVE else max(thermal_range, radar_range)
	
	# Check all bodies in the solar system
	_check_world_bodies(player_pos, check_range)
	
	# Check enemy ships if they exist
	_check_enemy_ships()
	
	# Update contact states for contacts that moved out of range
	_update_contact_states(player_pos, check_range)


func _check_world_bodies(player_pos: Vector2, check_range: float) -> void:
	## Check all bodies in the world for potential contacts
	var world = get_tree().root
	if world == null:
		return
	
	# Find all bodies with get_detection_signature method
	var bodies = _find_detection_bodies(world)
	
	for body in bodies:
		# Skip the player ship
		if body == player_ship:
			continue
		
		# Calculate distance
		var body_pos: Vector2
		if body.has_method("world_position"):
			body_pos = body.world_position
		elif body is Node2D:
			body_pos = body.position
		else:
			continue
		
		var distance = player_pos.distance_to(body_pos)
		
		# Check if in range (accounting for occlusion)
		var occluded = not check_line_of_sight(player_pos, body_pos)
		
		# Create contact for any body in extended range (even occluded)
		# Detection will be blocked by occlusion in _update_contact
		var extended_range = check_range * 2.0  # Extended range for awareness
		if distance < extended_range:
			var contact = get_or_create_contact(body)
			if contact and occluded:
				contact.is_occluded = true
		else:
			# Out of extended range - remove contact
			remove_contact(body)


func _find_detection_bodies(world: Node) -> Array:
	## Find all nodes with detection signature method
	var bodies: Array = []
	var search_nodes: Array = [world]
	
	while search_nodes.size() > 0:
		var node = search_nodes.pop_front()
		if node.has_method("get_detection_signature") and node != self:
			bodies.append(node)
		
		for child in node.get_children():
			if not bodies.has(child):
				search_nodes.append(child)
	
	return bodies


func _check_enemy_ships() -> void:
	## Check for AI/enemy ships in the world
	# This will be implemented when enemy ships are added
	pass


func _update_contact_states(player_pos: Vector2, check_range: float) -> void:
	## Update detection state for all contacts
	for contact in detected_contacts.values():
		if not is_instance_valid(contact.body):
			remove_contact(contact.body)
			continue
		
		# Get contact position
		var contact_pos: Vector2
		if contact.body.has_method("world_position"):
			contact_pos = contact.body.world_position
		elif contact.body is Node2D:
			contact_pos = contact.body.position
		else:
			continue
		
		var distance = player_pos.distance_to(contact_pos)
		_update_contact(contact, distance)


func _update_contact(contact: SensorContact, distance: float) -> void:
	## Update contact information based on current sensor state and occlusion
	if not is_instance_valid(contact.body):
		return
	
	# Calculate detection signal
	var signature = contact.body.get_detection_signature()
	
	# Check line of sight - occluded contacts are harder to detect
	var is_occluded: bool = false
	if player_ship:
		is_occluded = check_occlusion_to_contact(contact)
		contact.is_occluded = is_occluded
		
		# Track occluding body for UI feedback
		if is_occluded:
			var player_pos: Vector2
			var contact_pos: Vector2
			
			if player_ship.has_method("get_position"):
				player_pos = player_ship.get_position()
			else:
				player_pos = player_ship.position
			
			if contact.body.has_method("get_position"):
				contact_pos = contact.body.get_position()
			else:
				contact_pos = contact.body.position
			
			contact.occluding_body = get_occluding_body(player_pos, contact_pos)
		else:
			contact.occluding_body = null
	
	match active_scan_mode:
		SensorMode.PASSIVE:
			# Thermal detection only - passive sensors CANNOT see through planets
			# This is a core game mechanic: hiding behind bodies provides true stealth
			var thermal_detected = signature.thermal > thermal_detection_threshold and not is_occluded
			var attenuation = _calculate_thermal_attenuation(distance)
			thermal_signal_strength = signature.thermal * attenuation if thermal_detected else 0.0
			
			contact.is_thermally_detected = thermal_detected and thermal_signal_strength > thermal_detection_threshold
			contact.thermal_signal_strength = thermal_signal_strength
			
			# Emit detection event
			if contact.is_thermally_detected and not contact.was_previously_detected:
				thermal_contact_detected.emit(contact)
			
			contact.was_previously_detected = contact.is_thermally_detected
			
		SensorMode.RADAR, SensorMode.ACTIVE:
			# Combined thermal and radar
			var radar_detected = signature.radar > radar_detection_threshold
			var thermal_attenuation = _calculate_thermal_attenuation(distance)
			var radar_attenuation = _calculate_radar_attenuation(distance)
			
			thermal_signal_strength = signature.thermal * thermal_attenuation
			radar_signal_strength = signature.radar * radar_attenuation
			
			# Thermal cannot see through occluding bodies (passive stealth)
			# Radar can detect through occlusion but with significantly reduced signal
			contact.is_thermally_detected = signature.thermal > thermal_detection_threshold and thermal_signal_strength > thermal_detection_threshold and not is_occluded
			contact.is_radar_detected = radar_detected and radar_signal_strength > radar_detection_threshold
			
			# Apply occlusion penalty to radar detection
			if is_occluded:
				var occlusion_penalty = 0.2  # 80% reduction when occluded
				contact.radar_signal_strength *= occlusion_penalty
				contact.is_radar_detected = contact.radar_signal_strength > radar_detection_threshold
			
			contact.thermal_signal_strength = thermal_signal_strength
			contact.radar_signal_strength = radar_signal_strength
	
	contact.distance = distance
	contact.bearing = _calculate_bearing(contact.body.world_position)
	contact_updated.emit(contact)


func _calculate_thermal_attenuation(distance: float) -> float:
	## Calculate thermal signal attenuation over distance (inverse square law)
	if distance < 1.0:
		return 1.0
	return thermal_range / (distance * distance) * 1000.0


func _calculate_radar_attenuation(distance: float) -> float:
	## Calculate radar signal attenuation over distance
	if distance < 1.0:
		return 1.0
	return radar_range / (distance * distance) * 1000.0


func _calculate_bearing(target_position: Vector2) -> float:
	## Calculate bearing to target from player position
	var offset = target_position - player_ship.world_position
	return offset.angle()


# === Sensor Mode Control ===

func set_sensor_mode(mode: int) -> void:
	## Set the current sensor mode
	if active_scan_mode != mode:
		active_scan_mode = mode
		# Clear old contacts when switching modes
		detected_contacts.clear()


func toggle_radar() -> void:
	## Toggle between passive and active radar
	if active_scan_mode == SensorMode.PASSIVE:
		set_sensor_mode(SensorMode.RADAR)
	else:
		set_sensor_mode(SensorMode.PASSIVE)


# === Radar Tracking System ===

## Lock state tracking
var radar_locked_contact: SensorContact = null
var is_locking_in_progress: bool = false
var lock_progress: float = 0.0
var lock_duration: float = 3.0  # seconds to acquire lock
var lock_range: float = 200000.0  # 200km lock acquisition range

signal radar_lock_acquired(contact: SensorContact)
signal radar_lock_lost(contact: SensorContact)
signal radar_lock_progress_changed(progress: float)


func set_sensor_mode(mode: int) -> void:
	## Set the active sensor mode
	# Lose lock when switching to passive
	if mode == SensorMode.PASSIVE and radar_locked_contact != null:
		_lose_radar_lock()
	
	active_scan_mode = mode
	# Clear old contacts when switching modes
	detected_contacts.clear()


func start_radar_lock(target: SensorContact) -> bool:
	## Attempt to start locking onto a radar contact
	if active_scan_mode != SensorMode.RADAR:
		return false
	
	if target == null or not is_instance_valid(target.body):
		return false
	
	# Check if within lock range
	var distance = _get_distance_to_contact(target)
	if distance > lock_range:
		return false
	
	# Start lock acquisition
	is_locking_in_progress = true
	lock_progress = 0.0
	radar_locked_contact = target
	target.status = ContactStatus.INVESTIGATING
	radar_lock_progress_changed.emit(0.0)
	return true


func cancel_radar_lock() -> void:
	## Cancel lock acquisition
	is_locking_in_progress = false
	lock_progress = 0.0
	if radar_locked_contact != null and radar_locked_contact.status == ContactStatus.INVESTIGATING:
		radar_locked_contact.status = ContactStatus.UNKNOWN
	radar_locked_contact = null
	radar_lock_progress_changed.emit(0.0)


func _update_radar_lock(delta: float) -> void:
	## Update radar lock progress each frame
	if not is_locking_in_progress or radar_locked_contact == null:
		return
	
	# Update progress
	lock_progress += delta / lock_duration
	
	# Check if contact is still trackable
	var distance = _get_distance_to_contact(radar_locked_contact)
	if distance > lock_range:
		# Lock broken - contact out of range
		_lose_radar_lock()
		return
	
	radar_lock_progress_changed.emit(lock_progress)
	
	if lock_progress >= 1.0:
		# Lock acquired
		_acquire_radar_lock()


func _acquire_radar_lock() -> void:
	## Complete lock acquisition
	is_locking_in_progress = false
	if radar_locked_contact != null:
		radar_locked_contact.status = ContactStatus.IDENTIFIED
		radar_locked_contact.is_radar_tracked = true
		radar_lock_acquired.emit(radar_locked_contact)
		print("SensorManager: Radar lock acquired on contact")


func _lose_radar_lock() -> void:
	## Lose the current radar lock
	var lost_contact = radar_locked_contact
	is_locking_in_progress = false
	lock_progress = 0.0
	radar_locked_contact = null
	
	if lost_contact != null:
		lost_contact.status = ContactStatus.UNKNOWN
		lost_contact.is_radar_tracked = false
		radar_lock_lost.emit(lost_contact)
		print("SensorManager: Radar lock lost")


func get_locked_contact() -> SensorContact:
	## Get the currently radar-locked contact
	return radar_locked_contact


func is_lock_active() -> bool:
	## Check if a radar lock is currently active
	return radar_locked_contact != null


func _get_distance_to_contact(contact: SensorContact) -> float:
	## Calculate distance to a contact
	if contact == null or not is_instance_valid(contact.body):
		return INF
	
	var contact_pos: Vector2
	if contact.body.has_method("world_position"):
		contact_pos = contact.body.world_position
	elif contact.body is Node2D:
		contact_pos = contact.body.position
	else:
		return INF
	
	if player_ship != null and player_ship.has_method("get_world_position"):
		return contact_pos.distance_to(player_ship.get_world_position())
	elif player_ship is Node2D:
		return contact_pos.distance_to(player_ship.position)
	
	return contact_pos.length()


func track_radar_contact(contact: SensorContact) -> void:
	## Start radar tracking on a contact (immediate tracking when in range)
	if active_scan_mode != SensorMode.RADAR:
		return
	
	var distance = _get_distance_to_contact(contact)
	if distance <= radar_tracking_range:
		contact.is_radar_tracked = true
		contact.status = ContactStatus.IDENTIFIED
		radar_lock_acquired.emit(contact)


# === Detection Helpers ===

func is_target_detected(body: Node) -> bool:
	## Check if a specific body is currently detected
	var contact_id = body.get_instance_id()
	if detected_contacts.has(contact_id):
		var contact = detected_contacts[contact_id]
		return contact.is_thermally_detected or contact.is_radar_detected
	return false


func get_contact(body: Node) -> SensorContact:
	## Get sensor contact for a body
	var contact_id = body.get_instance_id()
	return detected_contacts.get(contact_id)


# === Event Handlers ===

func _on_player_thrust_started() -> void:
	## Player started thrusting - increases thermal signature
	# This is handled by Ship.gd updating its own signature
	pass


func _on_player_thrust_ended() -> void:
	## Player stopped thrusting
	pass


# === External Interface ===

func get_all_detected_contacts() -> Array:
	## Get list of all currently detected contacts
	return detected_contacts.values()


func get_visible_contacts() -> Array:
	## Get list of contacts that are visible (not occluded)
	var visible: Array = []
	for contact in detected_contacts.values():
		if not contact.is_occluded:
			visible.append(contact)
	return visible


func get_occluded_contacts() -> Array:
	## Get list of contacts that are occluded by celestial bodies
	var occluded: Array = []
	for contact in detected_contacts.values():
		if contact.is_occluded:
			occluded.append(contact)
	return occluded


func get_best_contact() -> SensorContact:
	## Get the contact with the strongest signal
	var best: SensorContact = null
	var best_strength = 0.0
	
	for contact in detected_contacts.values():
		# Prefer visible contacts
		var visibility_bonus = 2.0 if not contact.is_occluded else 0.5
		var strength = contact.get_total_signal_strength() * visibility_bonus
		if strength > best_strength:
			best_strength = strength
			best = contact
	
	return best


# ============================================
# SensorContact - Individual detected contact
# ============================================

class SensorContact:
	## Represents a single detected contact on sensors
	
	var body: Node = null
	var contact_id: int = 0
	var sensor_manager: SensorManager = null
	
	# Detection state
	var is_thermally_detected: bool = false
	var is_radar_detected: bool = false
	var is_target_locked: bool = false
	var is_occluded: bool = false  # True if blocked by celestial body
	var occluding_body: Node = null  # Reference to body blocking line of sight
	var was_previously_detected: bool = false
	var status: int = SensorManager.ContactStatus.UNKNOWN
	
	# Signal strengths (0.0 to 1.0)
	var thermal_signal_strength: float = 0.0
	var radar_signal_strength: float = 0.0
	
	# Heat signature data (for analysis)
	var estimated_heat_output: float = 0.0  # Estimated thermal signature (0.0 to 1.0)
	var heat_signature_history: Array = []  # Recent heat readings for trend analysis
	
	# Ship class identification (based on heat signature analysis)
	var estimated_ship_class: int = SensorManager.ShipClass.UNKNOWN
	var ship_class_confidence: float = 0.0  # 0.0 to 1.0
	
	# Tracking data
	var distance: float = INF  # meters
	var bearing: float = 0.0  # radians
	var bearing_rate: float = 0.0  # radians per second (for intercept calculation)
	var relative_velocity: Vector2 = Vector2.ZERO
	var closure_rate: float = 0.0  # meters per second
	
	var last_update_time: float = 0.0
	var first_detected_time: float = 0.0
	var contact_age: float = 0.0  # seconds since first detection
	
	# Intercept calculation
	var time_to_intercept: float = INF  # Estimated time to intercept at current velocities
	var intercept_delta_v: float = INF  # Delta-v required for intercept maneuver
	
	func _init():
		if Engine.has_global_node("TimeManager"):
			var tm = Engine.get_global_node("TimeManager")
			if tm:
				first_detected_time = tm.simulation_time
	
	func get_display_name() -> String:
		if body and body.has_method("get_display_name"):
			return body.get_display_name()
		return "Unknown Contact"
	
	func get_total_signal_strength() -> float:
		return thermal_signal_strength + radar_signal_strength
	
	func get_detection_type_string() -> String:
		var types = []
		if is_thermally_detected:
			types.append("THERMAL")
		if is_radar_detected:
			types.append("RADAR")
		if types.is_empty():
			return "NONE"
		return " ".join(types)
	
	func get_visibility_status() -> String:
		if is_occluded and occluding_body:
			var body_name = "BODY"
			if occluding_body.has_method("get_display_name"):
				body_name = occluding_body.get_display_name()
			elif occluding_body.has("name"):
				body_name = str(occluding_body.name)
			return "BLOCKED BY %s" % body_name
		return "VISIBLE"
	
	func get_ship_class_string() -> String:
		match estimated_ship_class:
			SensorManager.ShipClass.UNKNOWN:
				return "???"
			SensorManager.ShipClass.CIVILIAN:
				return "CIVILIAN"
			SensorManager.ShipClass.PROBE:
				return "PROBE"
			SensorManager.ShipClass.FIGHTER:
				return "FIGHTER"
			SensorManager.ShipClass.FRIGATE:
				return "FRIGATE"
			SensorManager.ShipClass.DESTROYER:
				return "DESTROYER"
			SensorManager.ShipClass.CARRIER:
				return "CARRIER"
			SensorManager.ShipClass.FREIGHTER:
				return "FREIGHTER"
			_:
				return "UNKNOWN"
	
	func update_contact_age() -> void:
		contact_age = TimeManager.get_time_delta(first_detected_time)
	
	func analyze_heat_signature() -> void:
		## Analyze heat signature to estimate ship class
		# Record current reading
		heat_signature_history.append({
			"time": TimeManager.simulation_time if Engine.has_global_node("TimeManager") else 0.0,
			"heat": thermal_signal_strength
		})
		
		# Keep only last 60 readings
		while heat_signature_history.size() > 60:
			heat_signature_history.pop_front()
		
		# Calculate estimated heat output
		var distance = max(self.distance, 1.0)
		var base_range = sensor_manager.thermal_base_range if sensor_manager else 100000.0
		var falloff = sensor_manager.thermal_falloff_exponent if sensor_manager else 1.5
		var normalized_distance = distance / base_range
		estimated_heat_output = thermal_signal_strength * pow(max(normalized_distance, 0.1), falloff)
		
		# Classify based on heat output
		if estimated_heat_output < 0.1:
			estimated_ship_class = SensorManager.ShipClass.PROBE
			ship_class_confidence = 0.3
		elif estimated_heat_output < 0.3:
			estimated_ship_class = SensorManager.ShipClass.FIGHTER
			ship_class_confidence = 0.4
		elif estimated_heat_output < 0.5:
			estimated_ship_class = SensorManager.ShipClass.FRIGATE
			ship_class_confidence = 0.5
		elif estimated_heat_output < 0.7:
			estimated_ship_class = SensorManager.ShipClass.DESTROYER
			ship_class_confidence = 0.4
		elif estimated_heat_output < 0.9:
			estimated_ship_class = SensorManager.ShipClass.FREIGHTER
			ship_class_confidence = 0.3
		else:
			estimated_ship_class = SensorManager.ShipClass.CARRIER
			ship_class_confidence = 0.3
	
	func get_thermal_report() -> String:
		## Get a detailed thermal analysis report
		var report = "THERMAL ANALYSIS\n"
		report += "Signal: %.0f%%\n" % (thermal_signal_strength * 100.0)
		report += "Est. Heat: %.0f%%\n" % (estimated_heat_output * 100.0)
		report += "Class: %s (%.0f%%)\n" % [get_ship_class_string(), ship_class_confidence * 100.0]
		report += "Status: %s\n" % get_visibility_status()
		
		# Heat trend analysis
		if heat_signature_history.size() >= 2:
			var trend = get_heat_trend()
			match trend:
				1:
					report += "Trend: RISING"
				-1:
					report += "Trend: FALLING"
				_:
					report += "Trend: STABLE"
		
		return report
	
	func get_heat_trend() -> int:
		## Get heat signature trend (-1 falling, 0 stable, 1 rising)
		if heat_signature_history.size() < 2:
			return 0
		
		var recent = heat_signature_history[heat_signature_history.size() - 1].heat
		var older = heat_signature_history[0].heat
		
		if recent > older * 1.1:
			return 1
		elif recent < older * 0.9:
			return -1
		return 0
	
	func update_intercept_data() -> void:
		## Update intercept calculation data
		if distance <= 0 or relative_velocity.length_squared() < 0.1:
			time_to_intercept = INF
			return
		
		# Calculate closure rate along bearing
		var range_rate = relative_velocity.dot(bearing.normalized())
		closure_rate = -range_rate  # Negative = approaching
		
		# Estimate time to intercept
		if abs(closure_rate) > 1.0:
			time_to_intercept = distance / abs(closure_rate)
		else:
			time_to_intercept = INF
	
	func get_distance_string() -> String:
		## Get formatted distance string
		return OrbitalConstantsClass.format_distance(distance)
	
	func get_bearing_string() -> String:
		## Get formatted bearing string
		var degrees = rad_to_deg(bearing)
		if degrees < 0:
			degrees += 360.0
		return "%.1f°" % degrees
	
	func get_intercept_string() -> String:
		## Get intercept estimate string
		if time_to_intercept == INF or time_to_intercept < 0:
			return "---"
		
		# Format based on time scale
		if time_to_intercept < 60:
			return "%.0fs" % time_to_intercept
		elif time_to_intercept < 3600:
			return "%.1fm" % (time_to_intercept / 60.0)
		elif time_to_intercept < 86400:
			return "%.1fh" % (time_to_intercept / 3600.0)
		else:
			return "%.1fd" % (time_to_intercept / 86400.0)