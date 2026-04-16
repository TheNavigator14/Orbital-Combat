class_name HeatManager
extends Node
## Manages ship heat output and stealth detectability
## Heat state transitions: COLD → WARM → HOT → CRITICAL
## Higher heat = larger detection range for enemy sensors

signal heat_state_changed(state: int)
signal detectability_changed(range: float)

enum HeatState {
	COLD = 0,
	WARM = 1,
	HOT = 2,
	CRITICAL = 3
}

## Detection range at each heat state (in meters)
const DETECTION_RANGES := {
	HeatState.COLD: 50000.0,      # 50 km - very hard to detect when cold
	HeatState.WARM: 150000.0,     # 150 km - standard passive detection
	HeatState.HOT: 350000.0,      # 350 km - significant thermal signature
	HeatState.CRITICAL: 600000.0  # 600 km - glowing hot, easy to spot
}

## Heat thresholds (0.0 to 1.0)
const WARM_THRESHOLD := 0.2
const HOT_THRESHOLD := 0.6
const CRITICAL_THRESHOLD := 0.9

## Heat decay rate per second when not thrusting
const HEAT_DECAY_RATE := 0.1

## Heat buildup rate per second when thrusting
const THRUST_HEAT_RATE := 0.3

@export var current_heat: float = 0.0
@export var max_heat: float = 1.0

var current_state: HeatState = HeatState.COLD
var is_thrusting: bool = false
var _previous_state: HeatState = HeatState.COLD
var current_detection_range: float = DETECTION_RANGES[HeatState.COLD]


func _ready() -> void:
	_update_detection_range()


func _process(delta: float) -> void:
	_update_heat(delta)


## Set heat level directly (0.0 to 1.0)
func set_heat(value: float) -> void:
	current_heat = clamp(value, 0.0, max_heat)
	_check_and_update_state()


## Called when thrust starts
func start_thrust() -> void:
	is_thrusting = true


## Called when thrust ends
func end_thrust() -> void:
	is_thrusting = false


## Add heat from a burn
func add_heat_from_burn(duration: float, intensity: float = 1.0) -> void:
	var heat_to_add: float = THRUST_HEAT_RATE * duration * intensity
	current_heat = clamp(current_heat + heat_to_add, 0.0, max_heat)
	_check_and_update_state()


## Main heat update - decay when cold, build when thrusting
func _update_heat(delta: float) -> void:
	if is_thrusting:
		# Build up heat during thrust
		current_heat = clamp(current_heat + THRUST_HEAT_RATE * delta, 0.0, max_heat)
	else:
		# Decay heat when coasting
		current_heat = max(0.0, current_heat - HEAT_DECAY_RATE * delta)
	
	_check_and_update_state()


## Check for state transition and emit signal if changed
func _check_and_update_state() -> void:
	var new_state: HeatState = _calculate_state()
	
	if new_state != _previous_state:
		_previous_state = current_state
		current_state = new_state
		heat_state_changed.emit(current_state)
	
	_update_detection_range()


## Determine heat state from current heat level
func _calculate_state() -> HeatState:
	if current_heat >= CRITICAL_THRESHOLD:
		return HeatState.CRITICAL
	elif current_heat >= HOT_THRESHOLD:
		return HeatState.HOT
	elif current_heat >= WARM_THRESHOLD:
		return HeatState.WARM
	else:
		return HeatState.COLD


## Update detection range based on current heat (smooth interpolation)
func _update_detection_range() -> void:
	var interpolated_range: float
	
	# Smooth interpolation between state ranges
	if current_heat < WARM_THRESHOLD:
		var t: float = current_heat / WARM_THRESHOLD
		interpolated_range = lerp(DETECTION_RANGES[HeatState.COLD], DETECTION_RANGES[HeatState.WARM], t)
	elif current_heat < HOT_THRESHOLD:
		var t: float = (current_heat - WARM_THRESHOLD) / (HOT_THRESHOLD - WARM_THRESHOLD)
		interpolated_range = lerp(DETECTION_RANGES[HeatState.WARM], DETECTION_RANGES[HeatState.HOT], t)
	elif current_heat < CRITICAL_THRESHOLD:
		var t: float = (current_heat - HOT_THRESHOLD) / (CRITICAL_THRESHOLD - HOT_THRESHOLD)
		interpolated_range = lerp(DETECTION_RANGES[HeatState.HOT], DETECTION_RANGES[HeatState.CRITICAL], t)
	else:
		# At critical - add slight variance for realism
		interpolated_range = DETECTION_RANGES[HeatState.CRITICAL] * (1.0 + randf() * 0.05)
	
	if abs(interpolated_range - current_detection_range) > 100.0:
		current_detection_range = interpolated_range
		detectability_changed.emit(current_detection_range)


## Get detection range for sensor system queries
func get_detection_range() -> float:
	return current_detection_range


## Get normalized heat level (0.0 to 1.0)
func get_heat_level() -> float:
	return current_heat / max_heat


## Get current heat state
func get_state() -> HeatState:
	return current_state


## Get heat state as readable string
func get_state_string() -> String:
	match current_state:
		HeatState.COLD:
			return "COLD"
		HeatState.WARM:
			return "WARM"
		HeatState.HOT:
			return "HOT"
		HeatState.CRITICAL:
			return "CRITICAL"
		_:
			return "UNKNOWN"


## Calculate if this ship is detectable by a sensor at given distance
func calculate_detection_at_distance(distance: float, sensor_sensitivity: float = 1.0) -> bool:
	var effective_range: float = current_detection_range * sensor_sensitivity
	return distance <= effective_range


## Get detection chance (0.0 to 1.0) at given distance
func get_detection_chance(distance: float, sensor_sensitivity: float = 1.0) -> float:
	if distance <= 0:
		return 1.0
	
	var effective_range: float = current_detection_range * sensor_sensitivity
	if distance > effective_range:
		return 0.0
	
	# Inverse relationship: closer = higher chance
	return 1.0 - (distance / effective_range)


## Reset to cold state (e.g., after cold soak in shadow)
func reset() -> void:
	current_heat = 0.0
	current_state = HeatState.COLD
	is_thrusting = false
	_update_detection_range()
	heat_state_changed.emit(current_state)


## Get debug/diagnostic info
func get_debug_info() -> Dictionary:
	return {
		"state": get_state_string(),
		"state_enum": current_state,
		"heat": current_heat,
		"heat_percent": "%.0f%%" % (get_heat_level() * 100.0),
		"detection_range_km": "%.1f km" % (current_detection_range / 1000.0),
		"is_thrusting": is_thrusting
	}