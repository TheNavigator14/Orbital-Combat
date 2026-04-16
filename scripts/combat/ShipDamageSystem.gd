class_name ShipDamageSystem
extends Node
## Handles ship health, damage, and destruction effects
## Manages shields, hull integrity, and death sequences

signal damage_taken(amount: float, source: String)
signal shield_hit(amount: float)
signal hull_breach()
signal ship_destroyed()
signal critical_damage()
signal health_changed(current: float, maximum: float)

# === Health Configuration ===
@export var max_health: float = 100.0
@export var initial_health: float = 100.0
@export var critical_threshold: float = 25.0  # Below this triggers critical state

# === Shield Configuration ===
@export var max_shields: float = 0.0  # 0 = no shields
@export var shield_recharge_rate: float = 5.0  # HP per second
@export var shield_recharge_delay: float = 3.0  # Seconds before recharge starts
@export var shield_efficiency: float = 1.0  # 0.0-1.0, damage reduction

# === Damage Types ===
enum DamageType {
	GENERIC = 0,
	MISSILES = 1,
	PDC = 2,
	COLLISION = 3,
	RADIATION = 4,
	THERMAL = 5
}

# === State ===
var current_health: float = 100.0
var current_shields: float = 0.0
var is_destroyed: bool = false
var is_critical: bool = false

# === Shield State ===
var shield_timer: float = 0.0
var shields_active: bool = false

# === Visual Effects ===
var _explosion_scene: PackedScene = null
var _screen_shake_enabled: bool = true
var _damage_flash_duration: float = 0.0

# === Damage Tracking ===
var total_damage_taken: float = 0.0
var last_damage_time: float = 0.0


func _ready() -> void:
	current_health = initial_health
	current_shields = max_shields
	shields_active = max_shields > 0.0


func _process(delta: float) -> void:
	if is_destroyed:
		return
	
	# Shield recharge
	if max_shields > 0.0 and current_shields < max_shields:
		if shield_timer >= shield_recharge_delay:
			current_shields = min(current_shields + shield_recharge_rate * delta, max_shields)
			health_changed.emit(current_health, max_health)
		else:
			shield_timer += delta
	
	# Damage flash decay
	if _damage_flash_duration > 0:
		_damage_flash_duration -= delta


func take_damage(amount: float, source: String = "unknown") -> void:
	"""Apply damage to the ship, respecting shields"""
	if is_destroyed:
		return
	
	last_damage_time = TimeManager.simulation_time
	total_damage_taken += amount
	
	# Apply shield damage first
	if shields_active and current_shields > 0 and max_shields > 0:
		var shield_damage = min(amount * (1.0 - shield_efficiency), current_shields)
		if shield_damage > 0:
			current_shields -= shield_damage
			shield_hit.emit(shield_damage)
			amount -= shield_damage
			# Reset shield recharge timer
			shield_timer = 0.0
		
		# Hull takes remaining damage
		if amount > 0:
			current_health -= amount
	else:
		current_health -= amount
	
	damage_taken.emit(amount, source)
	health_changed.emit(current_health, max_health)
	
	# Flash effect
	_damage_flash_duration = 0.1
	
	# Check critical state
	if not is_critical and current_health <= critical_threshold:
		is_critical = true
		critical_damage.emit()
	
	# Check for destruction
	if current_health <= 0:
		current_health = 0
		destroy_ship()


func take_missile_damage(amount: float) -> void:
	"""Specialized damage from missile impact"""
	take_damage(amount, "missile")


func take_pdc_damage(amount: float) -> void:
	"""Specialized damage from PDC rounds (typically lower)"""
	take_damage(amount * 0.5, "pdc")  # PDC does reduced hull damage


func take_collision_damage(velocity_delta: float) -> void:
	"""Damage from collision based on relative velocity"""
	# Kinetic damage: 0.5 * m * v^2, simplified to proportional
	var damage = clamp(velocity_delta * 0.1, 0, 100)
	take_damage(damage, "collision")


func heal(amount: float) -> void:
	"""Restore health (not exceeding max)"""
	if is_destroyed:
		return
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


func repair(amount: float) -> void:
	"""Alias for heal()"""
	heal(amount)


func recharge_shields(amount: float = -1.0) -> void:
	"""Manually recharge shields. -1 = full recharge"""
	if max_shields <= 0:
		return
	if amount < 0:
		current_shields = max_shields
	else:
		current_shields = min(current_shields + amount, max_shields)
	health_changed.emit(current_health, max_health)


func destroy_ship() -> void:
	"""Trigger ship destruction sequence"""
	if is_destroyed:
		return
	
	is_destroyed = true
	current_health = 0
	
	# Find parent ship
	var ship = _find_ship_owner()
	if ship != null:
		_trigger_explosion(ship)
	
	ship_destroyed.emit()
	
	# Remove the ship after a delay
	var parent = get_parent()
	if parent != null:
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(parent):
			parent.queue_free()


func _find_ship_owner() -> Node2D:
	"""Find the ship this damage system is attached to"""
	var parent = get_parent()
	if parent is Node2D:
		return parent
	return null


func _trigger_explosion(ship: Node2D) -> void:
	"""Create and display explosion effects"""
	var explosion = preload("res://scenes/effects/ExplosionVFX.tscn")
	if explosion:
		var effect = explosion.instantiate()
		effect.position = ship.position
		effect.rotation = ship.rotation
		
		# Add to same parent
		var parent = ship.get_parent()
		if parent:
			parent.add_child(effect)
		
		# Screen shake if player ship
		if ship is Ship and ship.ship_name == "Player":
			_trigger_screen_shake()


func _trigger_screen_shake() -> void:
	"""Add screen shake for player damage"""
	# This will be handled by Camera2D or a shake controller
	# For now, emit a signal that can be caught
	if Engine.has_singleton("GameManager"):
		var camera = get_viewport().get_camera_2d()
		if camera and camera.has_method("add_screen_shake"):
			camera.add_screen_shake(10.0, 0.5)


func get_health_percent() -> float:
	"""Return current health as percentage (0.0-1.0)"""
	if max_health <= 0:
		return 0.0
	return current_health / max_health


func get_shield_percent() -> float:
	"""Return current shields as percentage (0.0-1.0)"""
	if max_shields <= 0:
		return 0.0
	return current_shields / max_shields


func get_damage_state() -> String:
	"""Return human-readable damage state"""
	if is_destroyed:
		return "DESTROYED"
	if is_critical:
		return "CRITICAL"
	if current_health < max_health * 0.5:
		return "DAMAGED"
	if current_health < max_health * 0.9:
		return "LIGHT DAMAGE"
	return "NOMINAL"


func get_status_data() -> Dictionary:
	"""Return full status data for UI display"""
	return {
		"health": current_health,
		"max_health": max_health,
		"health_percent": get_health_percent(),
		"shields": current_shields,
		"max_shields": max_shields,
		"shield_percent": get_shield_percent(),
		"is_destroyed": is_destroyed,
		"is_critical": is_critical,
		"damage_state": get_damage_state(),
		"total_damage": total_damage_taken
	}


func is_alive() -> bool:
	"""Quick check if ship is still alive"""
	return not is_destroyed and current_health > 0


func can_take_damage() -> bool:
	"""Check if ship can currently receive damage"""
	return not is_destroyed