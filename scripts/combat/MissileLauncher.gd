class_name MissileLauncher
extends Node
## Missile launcher component for ships
## Manages missile inventory, loading, and firing

signal missile_fired(missile: Missile)
signal missile_reloaded(missile_type: int)
signal launcher_empty()

# === Launcher Configuration ===
@export var max_missiles: int = 4  # Total missile capacity
@export var reload_time: float = 5.0  # Seconds to reload after firing
@export var salvo_size: int = 1  # Number of missiles per launch
@export var spread_angle: float = 5.0  # Degrees - spread between salvo missiles
@export var default_missile_type: int = Missile.MissileType.SHORT_RANGE

# === State ===
var missiles: Array = []  # Currently loaded missiles
var is_reloading: bool = false
var reload_timer: float = 0.0
var ammo_by_type: Dictionary = {
	Missile.MissileType.SHORT_RANGE: 4,
	Missile.MissileType.LONG_RANGE: 2,
	Missile.MissileType.BALLISTIC: 2,
	Missile.MissileType.SHIP_TO_SHIP: 1,
	Missile.MissileType.ANTI_MISSILE: 2
}

# === Reference to parent ship ===
var parent_ship: Ship = null

# === Active missiles in flight ===
var active_missiles: Array = []

func _ready() -> void:
	# Load missile scene resource
	_missile_scene = preload("res://scenes/bodies/Missile.tscn")
	# Find parent ship
	_setup_parent_ship()


func _setup_parent_ship() -> void:
	## Find the parent ship
	var parent = get_parent()
	if parent is Ship:
		parent_ship = parent
	elif parent != null:
		# Search up the tree
		var current = parent.get_parent()
		while current != null:
			if current is Ship:
				parent_ship = current
				break
			current = current.get_parent()


# === Missile Loading ===

func load_missiles() -> void:
	## Load missiles into launcher from inventory
	missiles.clear()
	
	var ammo_to_load = min(max_missiles, _get_available_ammo())
	for i in range(ammo_to_load):
		missiles.append(default_missile_type)
	
	print("MissileLauncher: Loaded ", missiles.size(), " missiles")


func _get_available_ammo() -> int:
	## Get total available ammo from inventory
	var total = 0
	for type_key in ammo_by_type.keys():
		total += ammo_by_type.get(type_key, 0)
	return total


func add_ammo(type: int, count: int) -> void:
	## Add ammo of specific type
	ammo_by_type[type] = ammo_by_type.get(type, 0) + count
	print("MissileLauncher: Added ", count, " missiles of type ", type)


func remove_ammo(type: int, count: int) -> bool:
	## Remove ammo of specific type
	var current = ammo_by_type.get(type, 0)
	if current < count:
		return false
	ammo_by_type[type] = current - count
	return true


# === Firing ===

func fire(target: Node2D, profile: int = Missile.LaunchProfile.IMMEDIATE_BURN) -> Array:
	## Fire missiles at target
	## Returns array of fired Missile instances
	
	if missiles.size() < salvo_size:
		launcher_empty.emit()
		return []
	
	var fired_missiles: Array = []
	
	for i in range(salvo_size):
		# Get missile type for this slot
		var missile_type = missiles[i] if i < missiles.size() else default_missile_type
		
		# Create missile
		var missile = _create_missile(missile_type)
		
		# Calculate launch position with spread
		var launch_pos = _calculate_launch_position(launch_spread_index(i))
		var launch_vel = _calculate_launch_velocity()
		
		# Launch
		if missile.launch(target, profile, launch_pos, launch_vel):
			fired_missiles.append(missile)
			active_missiles.append(missile)
			missile_fired.emit(missile)
	
	# Remove fired missiles from ready rack
	_fire_from_rack(salvo_size)
	
	# Start reload timer if not full
	if missiles.size() < max_missiles:
		is_reloading = true
		reload_timer = reload_time
	
	return fired_missiles


func _create_missile(type: int) -> Missile:
	## Create a new missile instance of given type
	var missile: Missile
	
	if _missile_scene:
		missile = _missile_scene.instantiate() as Missile
	else:
		# Fallback: instantiate from script directly
		missile = preload("res://scripts/combat/Missile.gd").new()
	
	missile.missile_type = type
	
	# Add to scene tree
	var world = get_tree().root if get_tree() else null
	if world != null:
		var main = get_node("/root/Main") if has_node("/root/Main") else null
		if main:
			main.add_child(missile)
		else:
			get_parent().add_sibling(missile)
	else:
		get_parent().add_child(missile)
	
	# Set initial position at ship
	if parent_ship:
		missile.position = parent_ship.world_position
		if parent_ship.has_method("get_velocity"):
			missile.velocity = parent_ship.velocity
		else:
			missile.velocity = Vector2.ZERO
	
	return missile


func _calculate_launch_position(spread_index: int) -> Vector2:
	## Calculate launch position accounting for spread
	var base_pos: Vector2
	
	if parent_ship:
		base_pos = parent_ship.world_position
	else:
		base_pos = get_global_position()
	
	# Offset slightly for multiple missiles
	var offset = Vector2.ZERO
	if spread_index != 0:
		var angle = deg_to_rad(spread_angle * spread_index)
		var perpendicular = Vector2.RIGHT.rotated(angle)
		offset = perpendicular * 10.0  # 10 meter offset
	
	return base_pos + offset


func _calculate_launch_velocity() -> Vector2:
	## Calculate launch velocity (ship velocity + launcher velocity)
	var ship_vel = Vector2.ZERO
	
	if parent_ship:
		if parent_ship.has_method("get_velocity"):
			ship_vel = parent_ship.velocity
		elif parent_ship.has("velocity"):
			ship_vel = parent_ship.get("velocity")
	
	# Missiles don't add launcher velocity - they launch at ship's velocity
	
	return ship_vel


func _fire_from_rack(count: int) -> void:
	## Remove fired missiles from ready rack
	for i in range(count):
		if missiles.size() > 0:
			missiles.pop_front()


# === Reloading ===

func _process(delta: float) -> void:
	if not is_reloading:
		return
	
	reload_timer -= delta
	if reload_timer <= 0:
		_complete_reload()


func _complete_reload() -> void:
	## Complete reload and add new missiles
	is_reloading = false
	reload_timer = 0.0
	
	# Calculate how many to reload
	var slots_to_fill = min(salvo_size, max_missiles - missiles.size())
	
	# Reload from inventory
	for i in range(slots_to_fill):
		var type = _get_best_available_type()
		if type >= 0:
			missiles.append(type)
			remove_ammo(type, 1)
			missile_reloaded.emit(type)


func _get_best_available_type() -> int:
	## Get the best available missile type for reloading
	# Priority: SHORT_RANGE > ANTI_MISSILE > LONG_RANGE > BALLISTIC > SHIP_TO_SHIP
	var priority_order = [
		Missile.MissileType.SHORT_RANGE,
		Missile.MissileType.ANTI_MISSILE,
		Missile.MissileType.LONG_RANGE,
		Missile.MissileType.BALLISTIC,
		Missile.MissileType.SHIP_TO_SHIP
	]
	
	for type in priority_order:
		if ammo_by_type.get(type, 0) > 0:
			return type
	
	return -1  # No ammo available


# === Spread Calculation ===

func launch_spread_index(missile_index: int) -> int:
	## Get spread offset for missile in salvo (centered around 0)
	# Even count: symmetric around center
	# Odd count: includes center
	if salvo_size <= 1:
		return 0
	
	var half = salvo_size / 2.0
	if salvo_size % 2 == 0:
		return missile_index - half + 0.5
	else:
		return missile_index - floor(half)


# === Missile Management ===

func get_active_missile_count() -> int:
	## Get number of missiles currently in flight
	# Clean up any that have been destroyed
	active_missiles = active_missiles.filter(func(m): return is_instance_valid(m))
	return active_missiles.size()


func get_missiles_in_rack() -> int:
	## Get number of missiles ready to fire
	return missiles.size()


func get_total_ammo_count() -> int:
	## Get total ammo (in rack + inventory)
	var total = missiles.size()
	for type_key in ammo_by_type.keys():
		total += ammo_by_type.get(type_key, 0)
	return total


func get_ammo_summary() -> Dictionary:
	## Get detailed ammo counts
	return {
		"in_rack": missiles.size(),
		"total": get_total_ammo_count(),
		"by_type": ammo_by_type.duplicate(true),
		"max_capacity": max_missiles
	}


# === AI Helper Methods ===

func get_optimal_missile_type(target_distance: float, target_velocity: Vector2) -> int:
	## Get the optimal missile type for given target
	var closure_rate = 0.0
	if target_velocity.length_squared() > 0:
		var to_target_dir = (_calculate_launch_position(0) - (parent_ship.world_position if parent_ship else Vector2.ZERO)).normalized()
		closure_rate = target_velocity.dot(-to_target_dir)
	
	var distance_factor = target_distance / 500000.0  # Normalize to 500km
	var velocity_factor = closure_rate / 100.0  # Normalize to 100 m/s closure
	
	# High closure = can use shorter range missiles
	# Long distance = need longer range missiles
	
	if distance_factor > 2.0 and closure_rate > 50.0:
		return Missile.MissileType.LONG_RANGE
	elif distance_factor > 3.0:
		return Missile.MissileType.BALLISTIC
	elif closure_rate < -50.0:  # Target approaching fast
		return Missile.MissileType.ANTI_MISSILE
	elif distance_factor < 0.5:
		return Missile.MissileType.SHORT_RANGE
	else:
		return Missile.MissileType.SHIP_TO_SHIP