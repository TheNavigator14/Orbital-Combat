class_name ShipSignature
extends RefCounted

## Manages a ship's detectability profile across different sensor types.
## Lower values = harder to detect. Ships can actively manage signatures.

# Thermal signature (IR) - heat output visible to thermal sensors
# Range: 0.0 (cold/stealth) to 1.0+ (nuclear reactor hot)
var thermal_output: float = 0.5

# Radar signature (RCS) - radar cross section in m²
# Range: ~0.01 (stealth) to 100+ (large ship with reflectors)
var radar_cross_section: float = 10.0

# Electromagnetic signature - active emissions (radio, active sonar, etc.)
# Range: 0.0 (silent) to 1.0+ (loud active emissions)
var electromagnetic_output: float = 0.0

# Active countermeasures
var countermeasures_active: bool = false
var jamming_active: bool = false

# Signature modifiers from ship state
var shield_active: bool = false
var engines_thrusting: bool = false

# Heat management system
# Hull temperature affects detectability - hot ship = easier to detect
var hull_temperature: float = 293.0  # Kelvin (room temperature ~20°C)
var reactor_temperature: float = 800.0  # Kelvin (operating reactor)
var heat_capacity: float = 5000.0  # Thermal mass of hull
var base_heat_output: float = 50.0  # Base heat from reactor/radiation
var thrust_heat_output: float = 500.0  # Additional heat when thrusting
var cooling_rate: float = 20.0  # K/s when not thrusting
var max_hull_temp: float = 2000.0  # Temperature limit (damage threshold)

# Heat states for UI feedback
enum HeatState {
	COLD = 0,      # < 250K - minimal signature
	COOL = 1,      # 250-350K - low signature  
	WARM = 2,      # 350-500K - moderate signature
	HOT = 3,       # 500-800K - high signature
	CRITICAL = 4   # > 800K - very high signature
}

# Current heat state
var current_heat_state: HeatState = HeatState.COOL

func _init() -> void:
	hull_temperature = 293.0
	reactor_temperature = 800.0

## Update heat based on engine state and delta time
## Call this in physics process
func update_heat(delta: float, is_thrusting: bool = false) -> void:
	engines_thrusting = is_thrusting
	
	# Calculate heat generation
	var heat_input: float = base_heat_output
	if is_thrusting:
		heat_input += thrust_heat_output
	
	# Update hull temperature using simple thermal model
	# Q = mc*T, dT/dt = Q/c
	var net_heat: float = heat_input - cooling_rate
	hull_temperature += (net_heat / heat_capacity) * delta
	
	# Clamp to valid range
	hull_temperature = clamp(hull_temperature, 100.0, max_hull_temp)
	
	# Update heat state
	_update_heat_state()
	
	# Update thermal output based on hull temperature
	_update_thermal_from_heat()


## Update thrust signature (called from Ship.gd when thrust state changes)
func update_thrust_signature(is_now_thrusting: bool, thrust_level: float = 0.0) -> void:
	engines_thrusting = is_now_thrusting
	thermal_output = 0.3 + (0.7 * thrust_level) if is_now_thrusting else 0.1

## Determine heat state from current temperature
## Optional temp parameter allows external control of temperature setting
func _update_heat_state(temp: float = -1.0) -> void:
	if temp >= 0.0:
		hull_temperature = temp
	if hull_temperature < 250.0:
		current_heat_state = HeatState.COLD
	elif hull_temperature < 350.0:
		current_heat_state = HeatState.COOL
	elif hull_temperature < 500.0:
		current_heat_state = HeatState.WARM
	elif hull_temperature < 800.0:
		current_heat_state = HeatState.HOT
	else:
		current_heat_state = HeatState.CRITICAL

## Update thermal output based on hull temperature
func _update_thermal_from_heat() -> void:
	# Base thermal signature from hull temperature
	# Cold hull = low IR, hot hull = high IR
	match current_heat_state:
		HeatState.COLD:
			thermal_output = 0.05  # Nearly invisible
		HeatState.COOL:
			thermal_output = 0.2 + (hull_temperature - 250.0) / 500.0
		HeatState.WARM:
			thermal_output = 0.4 + (hull_temperature - 350.0) / 375.0
		HeatState.HOT:
			thermal_output = 0.8 + (hull_temperature - 500.0) / 600.0
		HeatState.CRITICAL:
			thermal_output = 1.5 + (hull_temperature - 800.0) / 400.0
	
	# Clamp thermal output
	thermal_output = clamp(thermal_output, 0.0, 3.0)

## Get current heat state as string for UI
func get_heat_state_string() -> String:
	match current_heat_state:
		HeatState.COLD: return "COLD"
		HeatState.COOL: return "COOL"
		HeatState.WARM: return "WARM"
		HeatState.HOT: return "HOT"
		HeatState.CRITICAL: return "CRITICAL"
	return "UNKNOWN"

## Get hull temperature in Kelvin
func get_hull_temperature() -> float:
	return hull_temperature

## Get hull temperature in Celsius
func get_hull_temperature_celsius() -> float:
	return hull_temperature - 273.15

## Start emergency cooling - vents heat faster
func start_emergency_cooling() -> void:
	cooling_rate = 100.0

## Stop emergency cooling
func stop_emergency_cooling() -> void:
	cooling_rate = 20.0

## Boost reactor output (increases heat, more power)
func boost_reactor() -> void:
	reactor_temperature = 1200.0
	base_heat_output = 150.0

## Throttle down reactor (reduces heat, less power)
func throttle_down_reactor() -> void:
	reactor_temperature = 500.0
	base_heat_output = 20.0

## Get effective thermal signature considering ship state
func get_effective_thermal() -> float:
	var sig = thermal_output
	
	# Engine thrust multiplies signature
	if engines_thrusting:
		sig *= 3.0
	
	if shield_active:
		sig *= 0.8
	
	return sig

## Get effective radar signature considering ship state
func get_effective_radar() -> float:
	var sig = radar_cross_section
	
	if engines_thrusting:
		sig *= 2.0
	
	if jamming_active:
		sig *= 10.0
	
	if shield_active:
		sig *= 0.5
	
	return sig

## Get effective EM signature
func get_effective_electromagnetic() -> float:
	return electromagnetic_output

## Set thermal output (e.g., afterburner, reactor setting)
func set_thermal_output(value: float) -> void:
	thermal_output = clamp(value, 0.0, 2.0)

## Set radar cross section (e.g., defensive posture, radar-absorbent materials)
func set_radar_cross_section(value: float) -> void:
	radar_cross_section = max(0.01, value)

## Engage silent running - minimize all signatures
func engage_stealth_mode() -> void:
	thermal_output = 0.1
	electromagnetic_output = 0.0
	engines_thrusting = false
	# Throttle down reactor for cold running
	throttle_down_reactor()

## Normal running configuration
func disengage_stealth_mode() -> void:
	thermal_output = 0.5
	electromagnetic_output = 0.0
	engines_thrusting = false
	reactor_temperature = 800.0
	base_heat_output = 50.0

## Active EM emissions (radio, active radar, etc.)
func start_active_emissions(power: float = 0.5) -> void:
	electromagnetic_output = clamp(power, 0.0, 1.0)
	jamming_active = false

## Start jamming (increases radar signature but may confuse enemy sensors)
func start_jamming() -> void:
	jamming_active = true
	electromagnetic_output = 1.0

## Stop jamming
func stop_jamming() -> void:
	jamming_active = false
	electromagnetic_output = 0.0

## Thermal flare - dump heat for evasion
func thermal_flare() -> void:
	thermal_output = 2.0
	hull_temperature = 1500.0

## Get detectability factor based on heat (0.0 = invisible, 1.0 = fully visible)
## This combines temperature, engine state, and distance
func get_detectability_factor(distance_meters: float, sensor_range: float) -> float:
	# Distance falloff (inverse square law approximation)
	var distance_factor: float = 1.0 - clamp(distance_meters / sensor_range, 0.0, 1.0)
	distance_factor = pow(distance_factor, 0.5)  # Softer falloff
	
	# Temperature factor
	var temp_factor: float = hull_temperature / 293.0  # Normalized to room temp
	
	# Engine factor
	var engine_factor: float = 1.0 if engines_thrusting else 0.3
	
	# Combine factors
	var detectability: float = distance_factor * temp_factor * engine_factor
	
	return clamp(detectability, 0.0, 1.0)