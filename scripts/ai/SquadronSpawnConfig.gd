class_name SquadronSpawnConfig
extends Resource
## Configuration resource for squadron spawning
## Defines squadron composition, behavior, and patrol parameters

# === Identification ===
@export var squadron_name: String = ""
@export var squadron_tag: String = ""  # For mission targeting

# === Size ===
@export var squadron_size: int = 4
@export var min_size: int = 2

# === Formation ===
@export var formation_type: Squadron.FormationType = Squadron.FormationType.ECHELON
@export var formation_spacing: float = 5000.0  # meters between ships
@export var formation_scale: float = 1.0

# === Patrol Behavior ===
@export var patrol_radius: float = 1000000.0  # meters
@export var patrol_area_center: Vector2 = Vector2.ZERO
@export var min_patrol_altitude: float = 200000.0  # meters above body
@export var patrol_spacing: float = 50000.0  # spacing between ships in orbit
@export var orbit_eccentricity: float = 0.1
@export var orbit_inclination: float = 5.0  # degrees

# === Combat Behavior ===
@export var engagement_range: float = 80000.0  # meters
@export var disengage_range: float = 300000.0
@export var retreat_threshold: float = 0.25  # health % to retreat
@export var base_reaction_time: float = 3.0  # seconds
@export var base_firing_range: float = 30000.0  # meters

# === Member Roles ===
@export var aggressive_leader: bool = true
@export var aggressive_wingman: bool = false
@export var evasive_wingman: bool = true
@export var coordinated_attack: bool = true

# === Difficulty Scaling ===
@export var difficulty_modifier: float = 1.0
@export var wave_number: int = 0

# === Special Types ===
@export var squadron_type: int = 0  # 0=standard, 1=heavy, 2=stealth, 3=scout


func _init() -> void:
	# Set sensible defaults
	pass


static func create_standard() -> SquadronSpawnConfig:
	## Create configuration for a standard assault squadron
	var config = SquadronSpawnConfig.new()
	config.squadron_name = "Alpha Squadron"
	config.squadron_size = 4
	config.formation_type = Squadron.FormationType.ECHELON
	config.aggressive_leader = true
	config.aggressive_wingman = true
	config.squadron_type = 0
	return config


static func create_heavy() -> SquadronSpawnConfig:
	## Create configuration for a heavy assault squadron
	var config = SquadronSpawnConfig.new()
	config.squadron_name = "Heavy Squadron"
	config.squadron_size = 6
	config.min_size = 4
	config.formation_type = Squadron.FormationType.DIAMOND
	config.formation_spacing = 8000.0
	config.aggressive_leader = true
	config.base_firing_range = 40000.0
	config.squadron_type = 1
	return config


static func create_stealth() -> SquadronSpawnConfig:
	## Create configuration for a stealth squadron
	var config = SquadronSpawnConfig.new()
	config.squadron_name = "Shadow Squadron"
	config.squadron_size = 3
	config.min_size = 2
	config.formation_type = Squadron.FormationType.LINE
	config.base_reaction_time = 8.0
	config.retreat_threshold = 0.4
	config.squadron_type = 2
	return config


static func create_scout() -> SquadronSpawnConfig:
	## Create configuration for a scout squadron
	var config = SquadronSpawnConfig.new()
	config.squadron_name = "Recon Squadron"
	config.squadron_size = 2
	config.min_size = 1
	config.formation_type = Squadron.FormationType.LINE_ABREAST
	config.engagement_range = 40000.0
	config.disengage_range = 500000.0
	config.squadron_type = 3
	return config


static func create_patrol(count: int = 3) -> SquadronSpawnConfig:
	## Create configuration for a patrol squadron
	var config = SquadronSpawnConfig.new()
	config.squadron_name = "Patrol Squadron"
	config.squadron_size = count
	config.min_size = maxi(count - 1, 1)
	config.formation_type = Squadron.FormationType.LINE
	config.aggressive_leader = false
	config.coordinated_attack = false
	return config


static func create_intercept() -> SquadronSpawnConfig:
	## Create configuration for an intercept squadron
	var config = SquadronSpawnConfig.new()
	config.squadron_name = "Intercept Squadron"
	config.squadron_size = 4
	config.engagement_range = 100000.0  # Long range
	config.disengage_range = 200000.0
	config.aggressive_leader = true
	config.aggressive_wingman = true
	config.coordinated_attack = true
	return config


func apply_difficulty(wave: int) -> void:
	## Scale configuration based on difficulty wave
	wave_number = wave
	difficulty_modifier = 1.0 + (wave - 1) * 0.15
	
	# Scale aggression with wave
	if wave > 3:
		aggressive_leader = true
	if wave > 5:
		aggressive_wingman = true
	
	# Scale engagement parameters
	base_firing_range *= difficulty_modifier
	engagement_range *= difficulty_modifier
	
	# Reduce retreat threshold (ships fight harder)
	retreat_threshold = max(0.1, retreat_threshold - 0.02 * wave)


func get_squadron_class() -> String:
	## Get display name for squadron type
	match squadron_type:
		0: return "Assault"
		1: return "Heavy"
		2: return "Stealth"
		3: return "Scout"
	return "Standard"


func to_dict() -> Dictionary:
	return {
		"name": squadron_name,
		"tag": squadron_tag,
		"size": squadron_size,
		"formation": formation_type,
		"type": get_squadron_class(),
		"difficulty": difficulty_modifier,
		"wave": wave_number
	}