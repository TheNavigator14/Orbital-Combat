class_name PDC
extends Node2D
## Point Defense Cannon - Close range defense against missiles
## Fires rapid projectiles to intercept incoming threats
## Supports both player control and AI auto-fire

signal pdc_fired(target: Node2D)
signal pdc_hit(target: Node2D)
signal pdc_cooldown_ready()
signal pdc_target_locked(target: Node2D)
signal pdc_target_lost()

# === PDC Configuration ===
@export var max_range: float = 20000.0  # meters - effective range
@export var min_range: float = 500.0  # meters - minimum engagement range
@export var rotation_speed: float = 180.0  # degrees per second
@export var fire_rate: float = 30.0  # rounds per second
@export var projectile_speed: float = 2000.0  # m/s
@export var damage_per_round: float = 50.0  # damage per hit
@export var accuracy_spread: float = 2.0  # degrees - random spread
@export var projectile_lifespan: float = 3.0  # seconds
@export var power_consumption: float = 10.0  # power units per second
@export var cooldown_duration: float = 0.5  # seconds between volleys

# === State ===
enum PDCState {
	IDLE = 0,       # Not engaged
	TRACKING = 1,   # Tracking a target
	FIRING = 2,     # Actively firing
	COOLDOWN = 3,   # Brief cooldown after firing
}

var pdc_state: PDCState = PDCState.IDLE
var current_target: Node2D = null
var current_angle: float = 0.0  # Current barrel rotation in degrees
var target_angle: float = 0.0  # Desired barrel rotation
var fire_cooldown: float = 0.0
var cooldown_timer: float = 0.0
var is_auto_fire_enabled: bool = true  # For AI/auto targeting
var is_powered: bool = true

# === Hit Detection ===
var active_projectiles: Array = []
var projectiles_per_volley: int = 5  # Rounds per burst
var rounds_fired: int = 0
var rounds_hit: int = 0

# === Threat Tracking ===
var tracked_missiles: Array = []  # All missiles in range
var prioritized_target: Node2D = null  # Current priority target

# === Parent Reference ===
var parent_ship: Ship = null


func _ready() -> void:
	# Find parent ship
	_setup_parent_ship()
	
	# Initialize rotation
	current_angle = rotation
	fire_cooldown = 1.0 / fire_rate


func _setup_parent_ship() -> void:
	## Find the parent ship
	var parent = get_parent()
	if parent is Ship:
		parent_ship = parent
	elif parent != null:
		var current = parent.get_parent()
		while current != null:
			if current is Ship:
				parent_ship = current
				break
			current = current.get_parent()


func _process(delta: float) -> void:
	# Update cooldown
	if pdc_state == PDCState.COOLDOWN:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			pdc_state = PDCState.IDLE
			pdc_cooldown_ready.emit()
	
	# Update cooldown between rounds
	if fire_cooldown > 0:
		fire_cooldown -= delta
	
	# Scan for threats
	if is_auto_fire_enabled and is_powered:
		_scan_for_threats(delta)
	
	# Track and aim at target
	if current_target and is_instance_valid(current_target):
		_update_tracking(delta)
	else:
		_clear_target()
		_scan_for_new_target()


func _scan_for_threats(delta: float) -> void:
	## Continuously scan for missiles in range
	var new_threats: Array = []
	
	# Get all active missiles from CombatManager
	var combat_manager = get_node("/root/CombatManager") if has_node("/root/CombatManager") else null
	var missiles: Array = []
	
	if combat_manager:
		missiles = combat_manager.active_missiles
	else:
		# Fallback: find missiles in tree
		missiles = get_tree().get_nodes_in_group("missiles")
	
	# Check each missile
	var shooter_pos = parent_ship.world_position if parent_ship else global_position
	
	for missile in missiles:
		if not is_instance_valid(missile):
			continue
		
		# Check if missile is a threat (targeting parent ship or friendly)
		var is_threatening = _is_missile_threatening(missile)
		if not is_threatening:
			continue
		
		# Check range
		var missile_pos = missile.position
		var distance = shooter_pos.distance_to(missile_pos)
		
		if distance <= max_range and distance >= min_range:
			# Check line of sight (simplified - could add occlusion)
			if _has_line_of_sight(missile_pos):
				new_threats.append(missile)
	
	tracked_missiles = new_threats
	
	# Auto-acquire new target if none
	if current_target == null or not is_instance_valid(current_target):
		_select_priority_target()


func _is_missile_threatening(missile: Missile) -> bool:
	## Check if a missile is targeting this ship
	if missile.target == parent_ship:
		return true
	
	# Check if it's targeting any friendly
	var allies = get_tree().get_nodes_in_group("player")
	for ally in allies:
		if missile.target == ally:
			return true
	
	# For now, treat all enemy missiles as threatening
	return missile.flight_state != Missile.FlightState.EXPLODED


func _has_line_of_sight(target_pos: Vector2) -> bool:
	## Simple line of sight check - could be enhanced with planet occlusion
	return true  # Simplified for now


func _select_priority_target() -> void:
	## Select the highest priority target from tracked missiles
	if tracked_missiles.size() == 0:
		prioritized_target = null
		return
	
	var best_target = null
	var highest_priority = -INF
	
	for missile in tracked_missiles:
		var priority = _calculate_threat_priority(missile)
		if priority > highest_priority:
			highest_priority = priority
			best_target = missile
	
	if best_target != prioritized_target:
		if prioritized_target:
			pdc_target_lost.emit()
		prioritized_target = best_target
		if prioritized_target:
			pdc_target_locked.emit(prioritized_target)


func _calculate_threat_priority(missile: Missile) -> float:
	## Calculate priority for targeting (higher = more urgent)
	var priority: float = 0.0
	
	if not parent_ship:
		return priority
	
	var missile_pos = missile.position
	var ship_pos = parent_ship.world_position
	var distance = ship_pos.distance_to(missile_pos)
	
	# Closer missiles are higher priority
	priority += (max_range - distance) / max_range * 50.0
	
	# Boosting missiles are more dangerous
	if missile.flight_state == Missile.FlightState.BOOST:
		priority += 30.0
	elif missile.flight_state == Missile.FlightState.TERMINAL:
		priority += 40.0  # Most dangerous - terminal guidance active
	
	# Time to intercept (rough estimate)
	if missile.velocity.length() > 0:
		var time_to_intercept = distance / missile.velocity.length()
		priority += max(0, (60.0 - time_to_intercept) / 60.0) * 20.0
	
	return priority


func _scan_for_new_target() -> void:
	## Called when current target is lost - look for new one
	_select_priority_target()


func _update_tracking(delta: float) -> void:
	## Update barrel rotation to track target
	if current_target == null or not is_instance_valid(current_target):
		return
	
	# Get target position
	var target_pos = _get_target_world_position(current_target)
	
	# Calculate desired angle to target
	var to_target = target_pos - (parent_ship.world_position if parent_ship else global_position)
	target_angle = rad_to_deg(to_target.angle())
	
	# Smooth rotation toward target
	var angle_diff = _angle_diff(current_angle, target_angle)
	var rotation_step = rotation_speed * delta
	
	if abs(angle_diff) <= rotation_step:
		current_angle = target_angle
		# Ready to fire if target is close enough
		if pdc_state == PDCState.TRACKING:
			_try_fire()
	else:
		current_angle = _normalize_angle(current_angle + sign(angle_diff) * rotation_step)
		pdc_state = PDCState.TRACKING
	
	# Update visual rotation
	rotation = deg_to_rad(current_angle)


func _try_fire() -> void:
	## Attempt to fire at current target
	if pdc_state == PDCState.COOLDOWN:
		return
	
	if fire_cooldown > 0:
		return
	
	if not is_powered:
		return
	
	_fire()


func _fire() -> void:
	## Fire a burst at current target
	pdc_state = PDCState.FIRING
	pdc_fired.emit(current_target)
	
	# Create projectiles
	for i in range(projectiles_per_volley):
		var projectile = _create_projectile()
		active_projectiles.append(projectile)
	
	rounds_fired += projectiles_per_volley
	
	# Reset cooldown
	fire_cooldown = 1.0 / fire_rate
	cooldown_timer = cooldown_duration
	pdc_state = PDCState.COOLDOWN


func _create_projectile() -> Node2D:
	## Create a single PDC projectile
	var projectile = Node2D.new()
	projectile.name = "PDC_Projectile"
	
	# Set position and velocity
	var base_angle = deg_to_rad(current_angle)
	var spread = randf_range(-accuracy_spread, accuracy_spread)
	var angle = base_angle + deg_to_rad(spread)
	
	var spawn_pos = global_position if parent_ship == null else parent_ship.world_position
	projectile.position = spawn_pos
	
	var velocity_vec = Vector2.from_angle(angle) * projectile_speed
	projectile.set("velocity", velocity_vec)
	projectile.set("damage", damage_per_round)
	projectile.set("lifespan", projectile_lifespan)
	projectile.set("max_age", projectile_lifespan)
	projectile.set("age", 0.0)
	projectile.set("parent_pdc", self)
	
	# Add collision area
	var area = Area2D.new()
	area.name = "HitArea"
	area.add_to_group("pdc_projectiles")
	
	var collision = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 5.0  # Small hitbox
	collision.shape = circle
	
	area.add_child(collision)
	projectile.add_child(area)
	
	# Connect area for hit detection
	area.area_entered.connect(_on_projectile_hit.bind(projectile))
	
	get_tree().root.add_child(projectile)
	
	# Start tracking timer
	var timer = Timer.new()
	timer.wait_time = projectile_lifespan
	timer.one_shot = true
	timer.timeout.connect(_on_projectile_expired.bind(projectile))
	timer.name = "LifespanTimer"
	projectile.add_child(timer)
	timer.start()
	
	return projectile


func _on_projectile_hit(area: Area2D, projectile: Node2D) -> void:
	## Handle projectile hitting something
	if not is_instance_valid(projectile):
		return
	
	var hit_target = area.get_parent()
	
	# Check if we hit a missile
	if hit_target is Missile:
		# Register hit
		rounds_hit += 1
		
		# Apply damage to missile
		var damage = projectile.get("damage") if projectile.has("damage") else damage_per_round
		hit_target.take_pdc_hit(damage)
		
		pdc_hit.emit(hit_target)
		print("PDC: Hit missile at distance ", (parent_ship.world_position if parent_ship else global_position).distance_to(hit_target.position))
	
	# Remove projectile
	_remove_projectile(projectile)


func _on_projectile_expired(projectile: Node2D) -> void:
	## Handle projectile expiring
	_remove_projectile(projectile)


func _remove_projectile(projectile: Node2D) -> void:
	## Remove projectile from scene
	active_projectiles.erase(projectile)
	if is_instance_valid(projectile):
		projectile.queue_free()


func _clear_target() -> void:
	## Clear current target
	if current_target:
		pdc_target_lost.emit()
	current_target = prioritized_target


func set_target(target: Node2D) -> void:
	## Manually set target
	current_target = target
	if target:
		pdc_target_locked.emit(target)


func cancel_target() -> void:
	## Cancel current target
	current_target = null
	prioritized_target = null
	pdc_state = PDCState.IDLE
	pdc_target_lost.emit()


func set_auto_fire(enabled: bool) -> void:
	## Enable/disable auto targeting
	is_auto_fire_enabled = enabled


func set_powered(powered: bool) -> void:
	## Toggle PDC power
	is_powered = powered
	if not powered:
		pdc_state = PDCState.IDLE
		current_target = null


func _get_target_world_position(target: Node2D) -> Vector2:
	## Get world position of target
	if target is Ship:
		return target.world_position
	elif target.has("position"):
		return target.position
	return Vector2.ZERO


func _angle_diff(from: float, to: float) -> float:
	## Calculate shortest angular difference
	var diff = fmod(to - from + 180.0, 360.0) - 180.0
	return diff


func _normalize_angle(angle: float) -> float:
	## Normalize angle to -180 to 180
	while angle > 180:
		angle -= 360
	while angle < -180:
		angle += 360
	return angle


# === Utility Methods ===

func get_tracked_count() -> int:
	## Get number of tracked missiles
	return tracked_missiles.size()


func get_accuracy() -> float:
	## Get current accuracy percentage
	if rounds_fired == 0:
		return 0.0
	return float(rounds_hit) / float(rounds_fired) * 100.0


func get_status_text() -> String:
	## Get status string for UI
	match pdc_state:
		PDCState.IDLE:
			return "IDLE"
		PDCState.TRACKING:
			return "TRACKING"
		PDCState.FIRING:
			return "FIRING"
		PDCState.COOLDOWN:
			return "COOLDOWN"
	return "UNKNOWN"


func get_pdc_data() -> Dictionary:
	## Get full PDC status data
	return {
		"state": pdc_state,
		"state_name": get_status_text(),
		"has_target": current_target != null and is_instance_valid(current_target),
		"tracked_count": tracked_missiles.size(),
		"projectiles_active": active_projectiles.size(),
		"rounds_fired": rounds_fired,
		"rounds_hit": rounds_hit,
		"accuracy": get_accuracy(),
		"is_auto_fire": is_auto_fire_enabled,
		"is_powered": is_powered
	}