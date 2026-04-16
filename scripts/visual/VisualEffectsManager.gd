class_name VisualEffectsManager
extends Node
## Central manager for visual effects - creates and tracks all particle effects

# === Effect Pools ===
var thrust_effects: Array = []  # Pool of thrust effects
var explosion_effects: Array = []  # Pool of active explosions
var flare_effects: Array = []  # Pool of active flares
var chaff_effects: Array = []  # Pool of active chaff clouds

# === Configuration ===
var max_thrust_effects: int = 10
var max_explosions: int = 20
var max_flares: int = 30
var max_chaff: int = 20

func _ready() -> void:
	# Initialize effect pools
	_create_thrust_pool()


func _create_thrust_pool() -> void:
	## Pre-create thrust effect pool
	for _i in range(max_thrust_effects):
		var effect = ThrustParticleEffect.new()
		effect.visible = false
		add_child(effect)
		thrust_effects.append(effect)


func _create_explosion_pool() -> void:
	## Pre-create explosion effect pool
	for _i in range(max_explosions):
		var effect = ExplosionEffect.new()
		effect.visible = false
		add_child(effect)
		explosion_effects.append(effect)


func _create_flare_pool() -> void:
	## Pre-create flare effect pool
	for _i in range(max_flares):
		var effect = FlareEffect.new()
		effect.visible = false
		add_child(effect)
		flare_effects.append(effect)


func _create_chaff_pool() -> void:
	## Pre-create chaff effect pool
	for _i in range(max_chaff):
		var effect = ChaffEffect.new()
		effect.visible = false
		add_child(effect)
		chaff_effects.append(effect)


# === Thrust Effects ===

func spawn_thrust_effect(ship: Ship, direction: Vector2) -> ThrustParticleEffect:
	## Spawn a thrust effect at ship position
	var available = _get_available_effect(thrust_effects)
	if available == null:
		# Create new if pool exhausted
		available = ThrustParticleEffect.new()
		add_child(available)
		thrust_effects.append(available)
	
	available.global_position = ship.global_position
	available.set_direction(direction)
	available.start_emission(direction)
	available.visible = true
	
	return available


func update_thrust_position(effect: ThrustParticleEffect, ship: Ship) -> void:
	## Update thrust effect position to follow ship
	if is_instance_valid(effect):
		effect.global_position = ship.global_position


func stop_thrust_effect(effect: ThrustParticleEffect) -> void:
	## Stop thrust effect (particles will fade)
	if is_instance_valid(effect):
		effect.stop_emission()


func release_thrust_effect(effect: ThrustParticleEffect) -> void:
	## Return effect to pool
	if is_instance_valid(effect):
		effect.clear_particles()
		effect.visible = false


# === Explosion Effects ===

func spawn_explosion(position: Vector2, size_scale: float = 1.0) -> ExplosionEffect:
	## Spawn explosion at position
	if explosion_effects.is_empty():
		_create_explosion_pool()
	
	var available = _get_available_effect(explosion_effects)
	if available == null:
		available = ExplosionEffect.new()
		add_child(available)
		explosion_effects.append(available)
	
	available.global_position = position
	available.set_explosion_size(size_scale)
	available.visible = true
	
	return available


# === Flare Effects ===

func spawn_flare(position: Vector2, direction: Vector2 = Vector2.UP) -> FlareEffect:
	## Spawn flare at position
	if flare_effects.is_empty():
		_create_flare_pool()
	
	var available = _get_available_effect(flare_effects)
	if available == null:
		available = FlareEffect.new()
		add_child(available)
		flare_effects.append(available)
	
	available.global_position = position
	available.launch(direction)
	available.visible = true
	
	return available


# === Chaff Effects ===

func spawn_chaff(position: Vector2, cluster_size: int = 20) -> ChaffEffect:
	## Spawn chaff cloud at position
	if chaff_effects.is_empty():
		_create_chaff_pool()
	
	var available = _get_available_effect(chaff_effects)
	if available == null:
		available = ChaffEffect.new()
		add_child(available)
		chaff_effects.append(available)
	
	available.global_position = position
	available.spawn_cloud(cluster_size)
	available.visible = true
	
	return available


# === Utility ===

func _get_available_effect(pool: Array) -> Object:
	## Find first available (inactive) effect in pool
	for effect in pool:
		if is_instance_valid(effect) and not effect.visible:
			return effect
	return null


func cleanup_completed_effects() -> void:
	## Hide effects that have completed their animation
	for effect in explosion_effects:
		if is_instance_valid(effect) and effect.is_complete():
			effect.visible = false
	
	for effect in flare_effects:
		if is_instance_valid(effect) and not effect.is_active():
			effect.visible = false
	
	for effect in chaff_effects:
		if is_instance_valid(effect) and not effect.is_active():
			effect.visible = false


func _process(delta: float) -> void:
	cleanup_completed_effects()