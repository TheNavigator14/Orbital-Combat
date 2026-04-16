class_name StealthManager
extends Node

## Manages stealth state and signature management for all ships.
## Autoload singleton for global stealth state.

# Reference to all ships with signature data
var tracked_ships: Dictionary = {}

# Stealth states
enum StealthState {
	NORMAL,
	LOW,
	SILENT,
	GHOST
}

# Current stealth state
var current_state: StealthState = StealthState.NORMAL

# Stealth modifiers per state
const STEALTH_MODIFIERS: Dictionary = {
	StealthState.NORMAL: 1.0,
	StealthState.LOW: 0.5,
	StealthState.SILENT: 0.2,
	StealthState.GHOST: 0.05
}

# Active stealth equipment effects
var stealth_suite_active: bool = false
var radar_absorbent_coating: bool = false
var infrared_suppression: bool = false

# Heat management settings
var passive_cooling_enabled: bool = true
var stealth_heat_target: float = 250.0  # Target temp for silent running

# Celestial bodies for line-of-sight occlusion
var celestial_bodies: Array = []

# Singleton instance
static var instance: StealthManager = null

func _ready() -> void:
	instance = self
	add_to_group("stealth")

## Get singleton instance
static func get_instance() -> StealthManager:
	return instance

## Register a ship for signature tracking
func register_ship(ship_id: String, ship_node: Node) -> void:
	if not tracked_ships.has(ship_id):
		var sig = ShipSignature.new()
		tracked_ships[ship_id] = {
			"node": ship_node,
			"signature": sig,
			"last_update": Time.get_ticks_msec()
		}

## Unregister a ship
func unregister_ship(ship_id: String) -> void:
	if tracked_ships.has(ship_id):
		var sig: ShipSignature = tracked_ships[ship_id].signature
		if sig:
			sig.free()
		tracked_ships.erase(ship_id)

## Get a ship's signature by ID
func get_ship_signature(ship_id: String) -> ShipSignature:
	if tracked_ships.has(ship_id):
		return tracked_ships[ship_id].signature
	return null

## Get a ship's signature by node
func get_signature_for_node(ship_node: Node) -> ShipSignature:
	if ship_node and tracked_ships.has(ship_node.name):
		return tracked_ships[ship_node.name].signature
	return null

## Set stealth state globally
func set_stealth_state(state: StealthState) -> void:
	current_state = state
	
	for ship_data in tracked_ships.values():
		var sig: ShipSignature = ship_data.signature
		if sig:
			match state:
				StealthState.SILENT, StealthState.GHOST:
					sig.engage_stealth_mode()
				_:
					sig.disengage_stealth_mode()

## Engage maximum stealth
func engage_ghost_mode() -> void:
	set_stealth_state(StealthState.GHOST)
	stealth_suite_active = true

## Disengage stealth
func disengage_ghost_mode() -> void:
	set_stealth_state(StealthState.NORMAL)
	stealth_suite_active = false

## Register a celestial body for line-of-sight blocking
func register_celestial_body(body: Node2D, radius: float) -> void:
	celestial_bodies.append({"body": body, "radius": radius})

## Unregister a celestial body
func unregister_celestial_body(body: Node2D) -> void:
	for i in range(celestial_bodies.size() - 1, -1, -1):
		if celestial_bodies[i].body == body:
			celestial_bodies.remove_at(i)
			break

## Clear all registered bodies
func clear_celestial_bodies() -> void:
	celestial_bodies.clear()

## Check line of sight between two positions
## Returns true if line-of-sight is clear, false if blocked by a body
func check_line_of_sight(from_pos: Vector2, to_pos: Vector2) -> bool:
	for body_data in celestial_bodies:
		var body: Node2D = body_data.body
		var radius: float = body_data.radius
		
		if not is_instance_valid(body) or radius <= 0:
			continue
		
		# Get body world position
		var body_pos: Vector2
		if body is Node2D:
			body_pos = body.global_position
		else:
			continue
		
		# Check if line segment from_pos-to_pos intersects the body circle
		if line_intersects_circle(from_pos, to_pos, body_pos, radius):
			return false  # Line of sight blocked
	
	return true  # Clear line of sight

## Check if a line segment intersects a circle
func line_intersects_circle(p1: Vector2, p2: Vector2, center: Vector2, radius: float) -> bool:
	var d: Vector2 = p2 - p1
	var f: Vector2 = p1 - center
	
	var a: float = d.dot(d)
	if a < 0.0001:
		return p1.distance_to(center) <= radius
	
	var b: float = 2.0 * f.dot(d)
	var c: float = f.dot(f) - radius * radius
	
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0.0:
		return false
	
	var sqrt_disc: float = sqrt(discriminant)
	var t1: float = (-b - sqrt_disc) / (2.0 * a)
	var t2: float = (-b + sqrt_disc) / (2.0 * a)
	
	if (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0):
		return true
	
	var t: float = clamp(f.dot(-d) / d.dot(d), 0.0, 1.0)
	var closest_point: Vector2 = p1 + d * t
	return closest_point.distance_to(center) <= radius

## Check if target is hidden behind a celestial body from observer position
func is_target_hidden(target_pos: Vector2, observer_pos: Vector2) -> bool:
	return not check_line_of_sight(observer_pos, target_pos)

## Get visibility percentage (1.0 = fully visible, 0.0 = fully blocked)
func get_visibility_factor(target_pos: Vector2, observer_pos: Vector2) -> float:
	if check_line_of_sight(target_pos, observer_pos):
		return 1.0
	return 0.0

## Check detection viability combining distance and line-of-sight
func can_detect_target(target_pos: Vector2, observer_pos: Vector2, max_range: float) -> bool:
	var dist: float = observer_pos.distance_to(target_pos)
	if dist > max_range:
		return false
	
	return check_line_of_sight(observer_pos, target_pos)

## Calculate detection chance based on heat, distance, and stealth state
## Returns 0.0 to 1.0 probability of detection
func calculate_detection_chance(target_pos: Vector2, observer_pos: Vector2, max_range: float) -> float:
	# First check basic detectability
	if not can_detect_target(target_pos, observer_pos, max_range):
		return 0.0
	
	var sig: ShipSignature = null
	# Find target's signature
	for ship_data in tracked_ships.values():
		var ship_node: Node = ship_data.node
		if ship_node and ship_node is Node2D:
			if (ship_node.global_position - target_pos).length() < 1000:
				sig = ship_data.signature
				break
	
	var base_detection: float = 1.0
	
	if sig:
		# Factor in thermal signature from heat
		var thermal: float = sig.get_effective_thermal()
		base_detection *= thermal
		
		# Factor in hull temperature directly
		var hull_temp: float = sig.get_hull_temperature()
		var temp_factor: float = (hull_temp - 200.0) / 800.0  # 200K = cold, 1000K = hot
		base_detection *= clamp(temp_factor, 0.1, 2.0)
	
	# Distance falloff
	var dist: float = observer_pos.distance_to(target_pos)
	var dist_factor: float = 1.0 - (dist / max_range)
	base_detection *= dist_factor
	
	# Apply stealth state modifier
	var stealth_mod: float = STEALTH_MODIFIERS.get(current_state, 1.0)
	base_detection *= stealth_mod
	
	# Apply equipment modifiers
	if infrared_suppression:
		base_detection *= 0.5
	if stealth_suite_active:
		base_detection *= 0.3
	
	return clamp(base_detection, 0.0, 1.0)

## Update signatures based on ship state
func _process(delta: float) -> void:
	for ship_data in tracked_ships.values():
		var ship_node: Node = ship_data.node
		var sig: ShipSignature = ship_data.signature
		
		if is_instance_valid(ship_node) and sig:
			# Update heat management
			var is_thrusting: bool = false
			if ship_node.has_method("is_thrusting"):
				is_thrusting = ship_node.is_thrusting()
			sig.update_heat(delta, is_thrusting)
			
			if ship_node.has_method("is_shield_active"):
				sig.shield_active = ship_node.is_shield_active()
			
			ship_data.last_update = Time.get_ticks_msec()

## Get heat state description for display
func get_heat_state_for_ship(ship_id: String) -> String:
	var sig: ShipSignature = get_ship_signature(ship_id)
	if sig:
		return sig.get_heat_state_string()
	return "UNKNOWN"

## Get hull temperature for a ship
func get_ship_temperature(ship_id: String) -> float:
	var sig: ShipSignature = get_ship_signature(ship_id)
	if sig:
		return sig.get_hull_temperature()
	return 293.0

## Start passive cooling for all tracked ships
func enable_passive_cooling() -> void:
	passive_cooling_enabled = true

## Disable passive cooling (hull retains heat)
func disable_passive_cooling() -> void:
	passive_cooling_enabled = false

## Set stealth heat target temperature
func set_stealth_heat_target(temp_kelvin: float) -> void:
	stealth_heat_target = clamp(temp_kelvin, 100.0, 500.0)

## Get the current player's signature (first tracked ship or named "Player")
func get_signature() -> ShipSignature:
	# Try to find player ship first
	if tracked_ships.has("Player"):
		return tracked_ships["Player"].signature
	
	# Fall back to first tracked ship
	for ship_data in tracked_ships.values():
		return ship_data.signature
	return null

## Get stealth rating (0.0 to 1.0) based on current state and equipment
func get_stealth_rating() -> float:
	var base_rating: float = STEALTH_MODIFIERS.get(current_state, 1.0)
	
	# Apply equipment bonuses (lower is better for detection)
	var equipment_mod: float = 1.0
	if stealth_suite_active:
		equipment_mod *= 0.5
	if radar_absorbent_coating:
		equipment_mod *= 0.7
	if infrared_suppression:
		equipment_mod *= 0.6
	
	# Convert to stealth rating (invert the detection modifier)
	return base_rating * (2.0 - equipment_mod)

## Check if currently in an effective stealth mode
func is_stealthy() -> bool:
	return current_state in [StealthState.LOW, StealthState.SILENT, StealthState.GHOST]

## Get the ID of the currently tracked player ship
func get_player_ship_id() -> String:
	if tracked_ships.has("Player"):
		return "Player"
	
	# Find first ship that's not tagged as enemy
	for ship_id in tracked_ships.keys():
		if "enemy" in ship_id.to_lower() or "ai" in ship_id.to_lower():
			continue
		return ship_id
	
	# Fall back to first tracked ship
	if tracked_ships.size() > 0:
		return tracked_ships.keys()[0]
	return ""

## Update stealth state based on heat management
func update_heat_management(delta: float, is_thrusting: bool) -> void:
	if not passive_cooling_enabled:
		return
	
	# Adjust hull temperature toward ambient when not thrusting
	var sig: ShipSignature = get_signature()
	if sig and not is_thrusting:
		var ambient_temp: float = 293.0  # ~20°C space ambient
		var heat_rate: float = 5.0  # K/s cooling rate
		var current_temp: float = sig.get_hull_temperature()
		var new_temp: float = current_temp
		
		if current_temp > stealth_heat_target:
			new_temp = max(stealth_heat_target, current_temp - heat_rate * delta)
		elif current_temp < stealth_heat_target:
			new_temp = min(stealth_heat_target, current_temp + heat_rate * delta * 0.5)
		
		sig._update_heat_state(new_temp)