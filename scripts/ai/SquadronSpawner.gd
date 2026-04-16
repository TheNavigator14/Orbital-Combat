class_name SquadronSpawner
extends Node
## Spawns and manages squadrons of enemy ships
## Handles creation, wave spawning, and squadron lifecycle

signal squadron_spawned(squadron: Squadron)
signal squadron_destroyed(squadron: Squadron)
signal wave_completed(wave_number: int, remaining_squadrons: int)

# === Configuration ===
@export var default_squadron_size: int = 4
@export var max_squadrons: int = 3
@export var respawn_delay: float = 30.0
@export var auto_spawn_waves: bool = false
@export var wave_interval: float = 60.0

# === State ===
var active_squadrons: Array = []
var spawn_queue: Array = []
var wave_number: int = 0
var respawn_timer: float = 0.0
var wave_timer: float = 0.0

# === References ===
var _spawn_parent: Node2D = null
var _enemy_scene: PackedScene = null


func _ready() -> void:
	_setup_enemy_scene()
	print("SquadronSpawner: Initialized")


func _process(delta: float) -> void:
	# Handle respawn timer
	if respawn_timer > 0:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_process_pending_spawns()
	
	# Handle wave spawning
	if auto_spawn_waves:
		wave_timer += delta
		if wave_timer >= wave_interval:
			wave_timer = 0.0
			spawn_next_wave()


func _setup_enemy_scene() -> void:
	# Try to load enemy ship scene, fallback to script
	var enemy_scene_path = "res://scenes/bodies/EnemyShip.tscn"
	if ResourceLoader.exists(enemy_scene_path):
		_enemy_scene = load(enemy_scene_path)
		print("SquadronSpawner: Loaded enemy scene from ", enemy_scene_path)
	else:
		print("SquadronSpawner: No enemy scene found, using script only")


# === Spawning Methods ===

func spawn_squadron(config: SquadronSpawnConfig = null, orbit_body: CelestialBody = null) -> Squadron:
	## Spawn a new squadron with the given configuration
	## Returns the spawned Squadron, or null if max reached
	
	if active_squadrons.size() >= max_squadrons:
		push_warning("SquadronSpawner: Max squadrons reached (%d)" % max_squadrons)
		return null
	
	# Use default config if none provided
	if config == null:
		config = SquadronSpawnConfig.new()
	
	# Create the squadron node
	var squadron = Squadron.new()
	squadron.squad_name = config.squadron_name if config.squadron_name != "" else "Squadron_%d" % (active_squadrons.size() + 1)
	squadron.formation_type = config.formation_type
	squadron.formation_spacing = config.formation_spacing
	squadron.max_members = config.squadron_size
	squadron.min_members = config.min_size
	squadron.patrol_area_radius = config.patrol_radius
	squadron.engagement_range = config.engagement_range
	squadron.disengage_range = config.disengage_range
	squadron.retreat_health_threshold = config.retreat_threshold
	
	# Set parent
	if _spawn_parent == null:
		_spawn_parent = _get_or_create_spawn_parent()
	_spawn_parent.add_child(squadron)
	
	# Spawn and add members
	var spawned_count = _populate_squadron(squadron, config, orbit_body)
	
	if spawned_count < config.min_size:
		# Not enough ships spawned, cancel
		squadron.queue_free()
		push_warning("SquadronSpawner: Could not spawn enough ships (got %d, need %d)" % [spawned_count, config.min_size])
		return null
	
	active_squadrons.append(squadron)
	
	# Connect to squadron signals
	squadron.squad_member_lost.connect(_on_member_lost.bind(squadron))
	squadron.squad_state_changed.connect(_on_squadron_state_changed.bind(squadron))
	
	# Set patrol area if body provided
	if orbit_body != null:
		squadron.set_patrol_area(orbit_body, config.patrol_radius)
	
	squadron_spawned.emit(squadron)
	print("SquadronSpawner: Spawned '%s' with %d members" % [squadron.squad_name, squadron.get_member_count()])
	
	return squadron


func _populate_squadron(squadron: Squadron, config: SquadronSpawnConfig, orbit_body: CelestialBody) -> int:
	## Spawn ships and add them to the squadron
	var count = 0
	
	for i in range(config.squadron_size):
		var member = _spawn_member(config, orbit_body, i)
		if member != null:
			squadron.add_member(member)
			count += 1
	
	return count


func _spawn_member(config: SquadronSpawnConfig, orbit_body: CelestialBody, index: int) -> EnemyAIShip:
	## Spawn a single enemy ship member
	var member: EnemyAIShip
	
	if _enemy_scene != null:
		var instance = _enemy_scene.instantiate()
		if instance is EnemyAIShip:
			member = instance
		else:
			# Wrong type, create manually
			member = _create_enemy_aiship()
	else:
		member = _create_enemy_aiship()
	
	# Name the ship
	member.name = "%s_%d" % [squadron.get_squadron_name(), index + 1]
	
	# Configure based on role
	var role = _get_member_role(index, config.squadron_size)
	_configure_member(member, config, role)
	
	# Position in formation orbit
	_configure_member_orbit(member, orbit_body, index, config)
	
	# Add to scene
	if _spawn_parent != null:
		_spawn_parent.add_child(member)
	
	return member


func _create_enemy_aiship() -> EnemyAIShip:
	## Create an EnemyAIShip instance with script
	var ship = EnemyAIShip.new()
	return ship


func _configure_member(member: EnemyAIShip, config: SquadronSpawnConfig, role: int) -> void:
	## Configure individual member based on role
	match role:
		0:  # Leader
			member.aggressive = config.aggressive_leader
			member.evasive = false
			member.max_thrust *= 1.1  # Slightly faster leader
		1:  # Wingman
			member.aggressive = config.aggressive_wingman
			member.evasive = config.evasive_wingman
		2:  # Rear guard
			member.aggressive = false
			member.evasive = true
			member.patrol_pattern = 2  # Erratic patrol
	
	# Custom detection settings
	member.detection_reaction_time = config.base_reaction_time + randf_range(-1.0, 1.0)
	member.firing_range = config.base_firing_range


func _get_member_role(index: int, total: int) -> int:
	## Assign a role based on position in squadron
	if index == 0:
		return 0  # Leader
	elif index == total - 1 and total > 2:
		return 2  # Rear guard
	else:
		return 1  # Wingman


func _configure_member_orbit(member: EnemyAIShip, orbit_body: CelestialBody, index: int, config: SquadronSpawnConfig) -> void:
	## Set up the member's orbit around the patrol body
	if orbit_body == null:
		# Default position far from origin
		member.position = Vector2(
			100000000 + randf_range(-20000000, 20000000),
			30000000 + randf_range(-10000000, 10000000)
		)
		return
	
	# Set parent body for orbital mechanics
	member.parent_body = orbit_body
	
	# Create orbit state
	var orbit_radius = orbit_body.radius + config.min_patrol_altitude + (config.patrol_spacing * index)
	var mu = orbit_body.mu if orbit_body.has("mu") else OrbitalConstants.SUN_MU
	
	var orbit = OrbitState.new()
	orbit.semi_major_axis = orbit_radius
	orbit.eccentricity = config.orbit_eccentricity
	orbit.inclination = config.orbit_inclination * (1.0 if index % 2 == 0 else -1.0)  # Alternate inclination
	orbit.true_anomaly = (index * TAU) / config.squadron_size  # Distribute around orbit
	
	member.orbit_state = orbit


# === Wave Spawning ===

func spawn_wave(count: int, config: SquadronSpawnConfig = null, orbit_body: CelestialBody = null) -> Array:
	## Spawn multiple squadrons as a wave
	var squadrons: Array = []
	wave_number += 1
	
	# Apply wave scaling to config
	var wave_config = config if config != null else SquadronSpawnConfig.new()
	if count > 1:
		# Scale difficulty with wave number
		wave_config.aggressive_leader = wave_number > 1
		wave_config.base_firing_range *= (1.0 + 0.1 * (wave_number - 1))
	
	for i in range(count):
		var squadron = spawn_squadron(wave_config, orbit_body)
		if squadron != null:
			squadrons.append(squadron)
	
	wave_completed.emit(wave_number, active_squadrons.size())
	print("SquadronSpawner: Wave %d spawned %d squadrons" % [wave_number, squadrons.size()])
	
	return squadrons


func spawn_next_wave() -> Array:
	## Spawn the next wave (scaled by current wave number)
	var wave_size = mini(1 + wave_number / 2, max_squadrons - active_squadrons.size())
	return spawn_wave(wave_size, null, null)


func queue_squadron_spawn(config: SquadronSpawnConfig = null, delay: float = -1.0, orbit_body: CelestialBody = null) -> void:
	## Queue a squadron to spawn after a delay
	if delay < 0:
		delay = respawn_delay
	
	spawn_queue.append({
		"config": config if config != null else SquadronSpawnConfig.new(),
		"delay": delay,
		"remaining": delay,
		"orbit_body": orbit_body
	})
	
	print("SquadronSpawner: Queued squadron spawn in %.1f seconds" % delay)


func _process_pending_spawns() -> void:
	## Process queued spawns with expired timers
	var still_queued = []
	
	for entry in spawn_queue:
		entry["remaining"] -= get_process_delta_time()
		if entry["remaining"] <= 0:
			spawn_squadron(entry["config"], entry["orbit_body"])
		else:
			still_queued.append(entry)
	
	spawn_queue = still_queued


# === Management ===

func get_squadron_at(index: int) -> Squadron:
	if index >= 0 and index < active_squadrons.size():
		return active_squadrons[index]
	return null


func get_squadron_by_name(name: String) -> Squadron:
	for squadron in active_squadrons:
		if squadron.squad_name == name:
			return squadron
	return null


func get_squadron_containing(member: EnemyAIShip) -> Squadron:
	for squadron in active_squadrons:
		if squadron.has_member(member):
			return squadron
	return null


func remove_squadron(squadron: Squadron) -> void:
	if squadron in active_squadrons:
		active_squadrons.erase(squadron)
		squadron.queue_free()
		squadron_destroyed.emit(squadron)


func remove_all_squadrons() -> void:
	for squadron in active_squadrons:
		squadron.queue_free()
	active_squadrons.clear()


# === Utilities ===

func _get_or_create_spawn_parent() -> Node2D:
	## Get or create the parent node for spawned ships
	var main = get_tree().get_root().get_node("Main")
	if main != null and main.has_node("EnemySquadrons"):
		return main.get_node("EnemySquadrons")
	
	var parent = Node2D.new()
	parent.name = "EnemySquadrons"
	main.add_child(parent)
	return parent


func _get_or_create_spawn_parent() -> Node2D:
	## Get or create a node to parent spawned squadrons
	var parent = Node2D.new()
	parent.name = "EnemySquadrons"
	
	# Try to find Main node
	var main = get_node("/root/Main")
	if main != null:
		main.add_child(parent)
	else:
		# Add to self as fallback
		add_child(parent)
	
	return parent


# === Signal Callbacks ===

func _on_member_lost(member: EnemyAIShip) -> void:
	print("SquadronSpawner: Member lost from squadron")
	# Check if squadron needs to reorganize or is below minimum


func _on_squadron_state_changed(from_state: int, to_state: int) -> void:
	# Could trigger UI updates or other game events
	pass


# === Statistics ===

func get_active_count() -> int:
	return active_squadrons.size()


func get_total_member_count() -> int:
	var count = 0
	for squadron in active_squadrons:
		count += squadron.get_member_count()
	return count


func get_wave_number() -> int:
	return wave_number


func get_spawner_status() -> Dictionary:
	return {
		"active_squadrons": active_squadrons.size(),
		"max_squadrons": max_squadrons,
		"queued_spawns": spawn_queue.size(),
		"wave_number": wave_number,
		"auto_spawn": auto_spawn_waves,
		"wave_timer": wave_timer if auto_spawn_waves else -1.0
	}