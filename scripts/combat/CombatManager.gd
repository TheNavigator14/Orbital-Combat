class_name CombatManager
extends Node
## Manages combat interactions: missiles, damage, hit detection
## Autoload singleton

signal missile_launched(missile: Missile)
signal missile_exploded(missile: Missile, hit: bool)
signal ship_damaged(ship: Ship, damage: float)
signal ship_destroyed(ship: Ship)
signal combat_started()
signal combat_ended()

# === Combat State ===
enum CombatState {
	PEACE = 0,     # No hostile contacts
	ALERT = 1,     # Hostile detected
	COMBAT = 2,    # Active combat
	ENGAGED = 3    # Deep in combat
}

var combat_state: CombatState = CombatState.PEACE
var hostile_contacts: Array = []  # Current hostile contacts
var active_missiles: Array = []    # All active missiles
var missiles_in_flight: int = 0     # Count for quick access

# === Damage Configuration ===
@export var collision_damage_multiplier: float = 1.0
@export var warhead_base_damage: float = 100.0
@export var friendly_fire_enabled: bool = false

# === Hit Detection ===
var _pending_hits: Array = []  # Missiles waiting to process hits

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect to TimeManager for pause handling
	var time_manager = get_node("/root/TimeManager") if has_node("/root/TimeManager") else null
	if time_manager:
		print("CombatManager: Connected to TimeManager")


func _process(delta: float) -> void:
	# Update combat state
	_update_combat_state()
	
	# Track active missiles
	_update_missile_tracking()


func _update_combat_state() -> void:
	## Update overall combat state based on hostile contacts and missiles
	
	var previous_state = combat_state
	
	# Count threats
	var hostile_count = hostile_contacts.size()
	var incoming_missiles = _count_incoming_missiles()
	
	# Determine state
	if hostile_count == 0 and incoming_missiles == 0:
		combat_state = CombatState.PEACE
	elif hostile_count > 0 and incoming_missiles == 0:
		combat_state = CombatState.ALERT
	elif hostile_count > 0 and incoming_missiles > 0:
		combat_state = CombatState.COMBAT
	else:  # Incoming missiles but no visible hostiles
		combat_state = CombatState.COMBAT
	
	# Emit signal on state change
	if previous_state != combat_state:
		combat_started.emit() if combat_state > CombatState.ALERT else combat_ended.emit()


func _update_missile_tracking() -> void:
	## Update active missile list and count
	var valid_missiles: Array = []
	
	for missile in active_missiles:
		if is_instance_valid(missile) and missile.flight_state != Missile.FlightState.EXPLODED:
			valid_missiles.append(missile)
		elif is_instance_valid(missile):
			# Missile just exploded
			var was_hit = _check_if_hit_target(missile)
			missile_exploded.emit(missile, was_hit)
	
	active_missiles = valid_missiles
	missiles_in_flight = valid_missiles.size()


func _count_incoming_missiles() -> int:
	## Count missiles targeting the player
	var count = 0
	var player_ship = _get_player_ship()
	
	if player_ship == null:
		return active_missiles.size()
	
	for missile in active_missiles:
		if missile.target == player_ship:
			count += 1
	
	return count


func _check_if_hit_target(missile: Missile) -> bool:
	## Check if missile hit its intended target
	if missile.target == null:
		return false
	
	var distance = missile.position.distance_to(missile._get_target_position())
	return distance < missile.detection_radius


# === Missile Management ===

func register_missile(missile: Missile) -> void:
	## Register a missile with combat manager
	if not active_missiles.has(missile):
		active_missiles.append(missile)
		missile_launched.emit(missile)
		print("CombatManager: Registered missile")


func unregister_missile(missile: Missile) -> void:
	## Unregister a missile
	active_missiles.erase(missile)


func launch_missile(target: Node2D, missile_type: int = Missile.MissileType.SHORT_RANGE,
		profile: int = Missile.LaunchProfile.IMMEDIATE_BURN, launcher: MissileLauncher = null) -> Missile:
	## Launch a missile at target
	var missile = Missile.new()
	missile.missile_type = missile_type
	
	# Get player position/velocity
	var player = _get_player_ship()
	if player:
		missile.position = player.world_position
		if player.has_method("get_velocity"):
			missile.velocity = player.get_velocity()
	
	# Add to scene
	var main = get_node("/root/Main") if has_node("/root/Main") else null
	if main:
		main.add_child(missile)
	else:
		get_parent().add_child(missile)
	
	# Launch
	if missile.launch(target, profile):
		register_missile(missile)
		return missile
	else:
		missile.queue_free()
		return null


# === Hostile Contact Management ===

func add_hostile_contact(contact) -> void:
	## Add a hostile contact
	if not hostile_contacts.has(contact):
		hostile_contacts.append(contact)
		print("CombatManager: Added hostile contact")


func remove_hostile_contact(contact) -> void:
	## Remove a hostile contact
	hostile_contacts.erase(contact)


func clear_hostiles() -> void:
	## Clear all hostile contacts
	hostile_contacts.clear()


func get_nearest_hostile() -> Node2D:
	## Get nearest hostile contact
	var player = _get_player_ship()
	if player == null:
		return null
	
	var nearest = null
	var nearest_dist = INF
	
	for contact in hostile_contacts:
		if contact == null:
			continue
		
		var pos = contact.get("position") if contact.has("position") else Vector2.ZERO
		var dist = player.world_position.distance_to(pos) if player.has("world_position") else INF
		
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = contact
	
	return nearest


func get_hostiles_in_range(range_m: float) -> Array:
	## Get hostiles within range
	var in_range: Array = []
	var player = _get_player_ship()
	
	if player == null:
		return in_range
	
	for contact in hostile_contacts:
		if contact == null:
			continue
		
		var pos = contact.get("position") if contact.has("position") else Vector2.ZERO
		var dist = player.world_position.distance_to(pos) if player.has("world_position") else INF
		
		if dist <= range_m:
			in_range.append(contact)
	
	return in_range


# === Damage System ===

func calculate_missile_damage(missile: Missile, hit: bool) -> float:
	## Calculate damage from missile explosion
	if not hit:
		return 0.0
	
	return warhead_base_damage * missile.warhead_yield


func apply_damage_to_ship(ship: Ship, damage: float) -> void:
	## Apply damage to a ship
	if ship == null:
		return
	
	ship_damaged.emit(ship, damage)
	
	# Check for ship destruction
	if ship.has_method("take_damage"):
		ship.take_damage(damage)
	elif ship.has("health"):
		var new_health = ship.get("health") - damage
		ship.set("health", new_health)
		
		if new_health <= 0:
			_destroy_ship(ship)


func _destroy_ship(ship: Ship) -> void:
	## Handle ship destruction
	print("CombatManager: Ship destroyed - ", ship.ship_name if "ship_name" in ship else "Unknown")
	ship_destroyed.emit(ship)
	
	# Remove from hostile list if present
	hostile_contacts.erase(ship)


# === Intercept Calculation ===

func calculate_intercept_time(launcher_pos: Vector2, launcher_vel: Vector2,
		target_pos: Vector2, target_vel: Vector2) -> float:
	## Calculate time for projectile from launcher to intercept target
	## Simplified - assumes target continues on current trajectory
	
	var rel_pos = target_pos - launcher_pos
	var rel_vel = target_vel - launcher_vel
	
	# Solve for time when distance = 0
	# |rel_pos + rel_vel * t| = 0
	# This is a quadratic: (rel_vel·rel_vel)t² + 2(rel_pos·rel_vel)t + (rel_pos·rel_pos) = 0
	
	var a = rel_vel.dot(rel_vel)
	var b = 2.0 * rel_pos.dot(rel_vel)
	var c = rel_pos.dot(rel_pos)
	
	if abs(a) < 1e-10:
		# Linear or no relative motion
		if abs(b) > 1e-10:
			return -c / b
		return INF
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return INF  # No intercept possible
	
	var t1 = (-b + sqrt(discriminant)) / (2.0 * a)
	var t2 = (-b - sqrt(discriminant)) / (2.0 * a)
	
	# Return smallest positive time
	if t1 >= 0 and t2 >= 0:
		return min(t1, t2)
	elif t1 >= 0:
		return t1
	elif t2 >= 0:
		return t2
	else:
		return INF  # Both in past


func predict_intercept_point(launcher_pos: Vector2, launcher_vel: Vector2,
		target_pos: Vector2, target_vel: Vector2, max_time: float = 3600.0) -> Vector2:
	## Predict where intercept will occur
	var intercept_time = calculate_intercept_time(launcher_pos, launcher_vel, target_pos, target_vel)
	
	if intercept_time == INF or intercept_time > max_time:
		return Vector2.INF  # No intercept within time limit
	
	# Return predicted position
	return target_pos + target_vel * intercept_time


# === Utility Methods ===

func _get_player_ship() -> Ship:
	## Get player ship reference
	var main = get_node("/root/Main") if has_node("/root/Main") else null
	if main and main.has("player_ship"):
		return main.get("player_ship")
	
	# Search for player ship
	var ships = get_tree().get_nodes_in_group("player")
	if ships.size() > 0:
		return ships[0]
	
	return null


func get_combat_summary() -> Dictionary:
	## Get current combat status
	return {
		"state": combat_state,
		"state_name": _get_state_name(),
		"hostile_count": hostile_contacts.size(),
		"missiles_in_flight": missiles_in_flight,
		"incoming_count": _count_incoming_missiles()
	}


func _get_state_name() -> String:
	match combat_state:
		CombatState.PEACE:
			return "Peace"
		CombatState.ALERT:
			return "Alert"
		CombatState.COMBAT:
			return "Combat"
		CombatState.ENGAGED:
			return "Engaged"
		_:
			return "Unknown"