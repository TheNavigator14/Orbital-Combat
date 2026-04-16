class_name CountermeasureSystem
extends Node
## Ship countermeasure system for evasion and defense
## Implements chaff, flares, and radar jammers
## Integrates with VisualEffectsManager for particle effects

signal countermeasure_deployed(type: CountermeasureType)
signal countermeasure_expired(type: CountermeasureType)
signal jamming_started(target: Node2D)
signal jamming_ended(target: Node2D)

# === Countermeasure Types ===
enum CountermeasureType {
	CHAFF = 0,      # Radar confusion - releases reflective particles
	FLARE = 1,      # IR decoy - thermal signature to distract missiles
	JAMMER = 2,     # Radar degradation - active interference
}

# === Configuration ===
@export var max_chaff_count: int = 10
@export var max_flare_count: int = 8
@export var chaff_cooldown: float = 5.0  # seconds between chaff deployments
@export var flare_cooldown: float = 3.0
@export var jammer_duration: float = 30.0  # seconds of jamming
@export var jammer_cooldown: float = 60.0  # recharge time

# === State ===
var chaff_available: int = 10
var flare_available: int = 8
var jammer_charges: int = 3
var max_jammer_charges: int = 3

var chaff_active: bool = false
var flare_active: bool = false
var jammer_active: bool = false

var _chaff_timer: float = 0.0
var _flare_timer: float = 0.0
var _jammer_timer: float = 0.0
var _jammer_cooldown_timer: float = 0.0

var _owner_ship: Ship = null

# === Visual Effects ===
var _visual_manager: Node = null  # VisualEffectsManager reference
var _active_flare_effect: Node = null
var _active_chaff_effect: Node = null

func _ready() -> void:
	# Get parent ship reference
	_owner_ship = get_parent() as Ship
	if _owner_ship == null:
		push_warning("CountermeasureSystem: Parent is not a Ship!")


func _process(delta: float) -> void:
	# Update active countermeasures
	_update_chaff(delta)
	_update_flare(delta)
	_update_jammer(delta)


func _update_chaff(delta: float) -> void:
	## Chaff dissipates over time
	if chaff_active:
		_chaff_timer -= delta
		if _chaff_timer <= 0:
			chaff_active = false
			_chaff_timer = 0
			countermeasure_expired.emit(CountermeasureType.CHAFF)


func _update_flare(delta: float) -> void:
	## Flares burn out over time
	if flare_active:
		_flare_timer -= delta
		if _flare_timer <= 0:
			flare_active = false
			_flare_timer = 0
			countermeasure_expired.emit(CountermeasureType.FLARE)


func _update_jammer(delta: float) -> void:
	## Jammer has duration and cooldown
	if jammer_active:
		_jammer_timer -= delta
		if _jammer_timer <= 0:
			jammer_active = false
			_jammer_timer = 0
			jammer_active = false
			countermeasure_expired.emit(CountermeasureType.JAMMER)
			# Start cooldown
			_jammer_cooldown_timer = jammer_cooldown
	else:
		# Recharge jammer when on cooldown
		if _jammer_cooldown_timer > 0:
			_jammer_cooldown_timer -= delta


# === Deployment Functions ===

func deploy_chaff() -> bool:
	## Deploy chaff cloud for radar confusion
	## Returns true if successfully deployed
	if chaff_available <= 0:
		print("CountermeasureSystem: No chaff available")
		return false
	
	if chaff_active:
		print("CountermeasureSystem: Chaff already active")
		return false
	
	chaff_available -= 1
	chaff_active = true
	_chaff_timer = 15.0  # Chaff cloud lasts 15 seconds
	
	countermeasure_deployed.emit(CountermeasureType.CHAFF)
	print("CountermeasureSystem: Chaff deployed - %d remaining" % chaff_available)
	return true


func deploy_flare() -> bool:
	## Deploy IR flare for heat-seeking missiles
	## Returns true if successfully deployed
	if flare_available <= 0:
		print("CountermeasureSystem: No flares available")
		return false
	
	if flare_active:
		# Allow stacking flares
		_flare_timer = max(_flare_timer, 5.0)  # Extend existing flare
	
	flare_available -= 1
	flare_active = true
	_flare_timer = 5.0  # Individual flare lasts 5 seconds
	
	countermeasure_deployed.emit(CountermeasureType.FLARE)
	print("CountermeasureSystem: Flare deployed - %d remaining" % flare_available)
	return true


func activate_jammer() -> bool:
	## Activate radar jammer to degrade enemy tracking
	## Returns true if successfully activated
	if jammer_charges <= 0:
		print("CountermeasureSystem: No jammer charges available")
		return false
	
	if jammer_active:
		print("CountermeasureSystem: Jammer already active")
		return false
	
	if _jammer_cooldown_timer > 0:
		print("CountermeasureSystem: Jammer on cooldown (%.1fs remaining)" % _jammer_cooldown_timer)
		return false
	
	jammer_charges -= 1
	jammer_active = true
	_jammer_timer = jammer_duration
	
	countermeasure_deployed.emit(CountermeasureType.JAMMER)
	jamming_started.emit(null)  # null = jamming everything in range
	print("CountermeasureSystem: Jammer activated - %d charges remaining" % jammer_charges)
	return true


# === Replenishment ===

func replenish_chaff(count: int) -> void:
	## Add chaff to inventory
	chaff_available = mini(chaff_available + count, max_chaff_count)
	print("CountermeasureSystem: +%d chaff (total: %d)" % [count, chaff_available])


func replenish_flares(count: int) -> void:
	## Add flares to inventory
	flare_available = mini(flare_available + count, max_flare_count)
	print("CountermeasureSystem: +%d flares (total: %d)" % [count, flare_available])


func restore_jammer_charge() -> void:
	## Restore one jammer charge
	if jammer_charges < max_jammer_charges:
		jammer_charges += 1
		print("CountermeasureSystem: Jammer charge restored (%d/%d)" % [jammer_charges, max_jammer_charges])


# === Query Functions ===

func is_chaff_active() -> bool:
	return chaff_active


func is_flare_active() -> bool:
	return flare_active


func is_jammer_active() -> bool:
	return jammer_active


func get_jammer_ready_percent() -> float:
	## Get jammer readiness as percentage (1.0 = ready)
	if jammer_active:
		return 1.0
	if jammer_charges >= max_jammer_charges:
		return 1.0
	if _jammer_cooldown_timer <= 0:
		return float(jammer_charges) / float(max_jammer_charges)
	# Cooldown still active
	return 0.0


func get_status_text() -> String:
	## Get human-readable status for UI
	var status = "CM: "
	status += "Chaff=%d/%d" % [chaff_available, max_chaff_count]
	status += " Flare=%d/%d" % [flare_available, max_flare_count]
	status += " Jam=%d/%d" % [jammer_charges, max_jammer_charges]
	if chaff_active:
		status += " [CHAFF]"
	if flare_active:
		status += " [FLARE]"
	if jammer_active:
		status += " [JAM]"
	return status


# === Countermeasure Effectiveness ===

func get_radar_confusion_factor() -> float:
	## Returns multiplier for enemy radar tracking error
	## 1.0 = no effect, higher = more confusion
	if chaff_active:
		return 5.0  # 5x position error
	return 1.0


func get_infrared_decoy_factor() -> float:
	## Returns decoy priority for heat-seeking missiles
	## Higher = more likely to target decoy vs real ship
	if flare_active:
		return 10.0
	return 0.0


func get_radar_jamming_factor() -> float:
	## Returns range reduction for enemy radar
	## 1.0 = no effect, lower = shorter effective range
	if jammer_active:
		return 0.3  # 30% of normal range
	return 1.0