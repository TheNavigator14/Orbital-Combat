class_name MissionManager
extends Node
## Manages mission objectives, progression, and campaign structure
## Autoload singleton

signal mission_started(mission_id: int)
signal mission_completed(mission_id: int, success: bool)
signal objective_completed(objective_id: int)
signal objective_failed(objective_id: int)
signal mission_updated()

# === Mission States ===
enum MissionState {
	INACTIVE = 0,
	ACTIVE = 1,
	COMPLETED = 2,
	FAILED = 3
}

enum ObjectiveType {
	DESTROY_TARGETS = 0,
	SURVIVE = 1,
	PATROL_AREA = 2,
	REACH_LOCATION = 3,
	ESCORT = 4,
	INTERCEPT = 5,
	DETECT_TARGETS = 6,
	ANALYZE_SIGNATURES = 7,
	REMAIN_STEALTHY = 8,
	ESCAPE_AREA = 9,
	DEPLOY_COUNTERMEASURES = 10
}

# === Campaign State ===
var current_mission_id: int = -1
var current_objectives: Array = []
var mission_states: Dictionary = {}
var mission_data: Dictionary = {}
var objective_timers: Dictionary = {}
var target_tracking: Dictionary = {}

# === Configuration ===
var save_path: String = "user://campaign_save.dat"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_initialize_missions()
	
	# Connect to combat events
	_setup_combat_signals()
	
	print("MissionManager: Initialized with ", mission_data.size(), " missions")

func _initialize_missions() -> void:
	## Initialize campaign mission definitions
	mission_data = {
		0: {
			"name": "First Contact",
			"description": "Detect and identify unknown contacts in the sector. Report to command.",
			"objectives": [
				{
					"id": 0,
					"type": ObjectiveType.DETECT_TARGETS,
					"description": "Detect thermal signatures in the patrol zone",
					"count": 2,
					"targets_detected": 0,
					"optional": false,
					"time_limit": 0.0
				},
				{
					"id": 1,
					"type": ObjectiveType.ANALYZE_SIGNATURES,
					"description": "Analyze detected signatures using passive sensors",
					"count": 2,
					"signatures_analyzed": 0,
					"optional": true,
					"bonus_points": 50
				}
			],
			"success_conditions": ["objectives_completed"],
			"fail_conditions": [],
			"time_limit": 0.0
		},
		1: {
			"name": "Shadow Patrol",
			"description": "Maintain stealth while observing enemy patrol patterns.",
			"objectives": [
				{
					"id": 0,
					"type": ObjectiveType.PATROL_AREA,
					"description": "Complete patrol circuit without detection",
					"patrol_points": 3,
					"points_visited": 0,
					"optional": false,
					"detection_threshold": 0.0
				},
				{
					"id": 1,
					"type": ObjectiveType.SURVIVE,
					"description": "Survive without taking damage",
					"optional": false,
					"damage_limit": 0.0
				}
			],
			"success_conditions": ["objectives_completed"],
			"fail_conditions": ["player_destroyed"],
			"time_limit": 600.0
		},
		2: {
			"name": "Precision Strike",
			"description": "Eliminate enemy vessel using missiles. Maintain covert approach.",
			"objectives": [
				{
					"id": 0,
					"type": ObjectiveType.DESTROY_TARGETS,
					"description": "Destroy enemy patrol ship",
					"count": 1,
					"targets_destroyed": 0,
					"optional": false
				},
				{
					"id": 1,
					"type": ObjectiveType.REMAIN_STEALTHY,
					"description": "Complete mission without enemy awareness reaching 100%",
					"optional": true,
					"bonus_points": 100
				}
			],
			"success_conditions": ["objectives_completed"],
			"fail_conditions": ["player_destroyed"],
			"time_limit": 900.0
		},
		3: {
			"name": "Close Pursuit",
			"description": "Intercept and engage fleeing enemy convoy.",
			"objectives": [
				{
					"id": 0,
					"type": ObjectiveType.INTERCEPT,
					"description": "Catch enemy before they escape the system",
					"target_escape_distance": 5e11,
					"optional": false
				},
				{
					"id": 1,
					"type": ObjectiveType.DESTROY_TARGETS,
					"description": "Destroy at least one enemy vessel",
					"count": 1,
					"targets_destroyed": 0,
					"optional": false
				}
			],
			"success_conditions": ["objectives_completed"],
			"fail_conditions": ["targets_escaped"],
			"time_limit": 1800.0
		},
		4: {
			"name": "Gauntlet",
			"description": "Navigate hostile territory and survive the onslaught.",
			"objectives": [
				{
					"id": 0,
					"type": ObjectiveType.SURVIVE,
					"description": "Survive for the duration",
					"duration": 600.0,
					"elapsed_time": 0.0,
					"optional": false
				},
				{
					"id": 1,
					"type": ObjectiveType.DESTROY_TARGETS,
					"description": "Destroy incoming hostile missiles",
					"count": 5,
					"targets_destroyed": 0,
					"optional": true,
					"bonus_points": 200
				}
			],
			"success_conditions": ["objectives_completed"],
			"fail_conditions": ["player_destroyed"],
			"time_limit": 600.0
		}
	}
	
	# Initialize mission states
	for mission_id in mission_data.keys():
		mission_states[mission_id] = MissionState.INACTIVE


func _setup_combat_signals() -> void:
	## Connect to CombatManager signals
	var combat_manager = get_node_or_null("/root/CombatManager")
	if combat_manager:
		combat_manager.combat_ended.connect(_on_combat_ended)
		if combat_manager.has("ship_destroyed"):
			combat_manager.ship_destroyed.connect(_on_ship_destroyed)
	else:
		# Poll for CombatManager
		await get_tree().create_timer(1.0).timeout
		_setup_combat_signals()


# === Mission Control ===

func start_mission(mission_id: int) -> bool:
	## Start a specific mission
	if not mission_data.has(mission_id):
		push_error("MissionManager: Mission %d not found" % mission_id)
		return false
	
	if mission_states[mission_id] == MissionState.COMPLETED:
		push_warning("MissionManager: Mission %d already completed" % mission_id)
		return false
	
	current_mission_id = mission_id
	current_objectives = []
	
	# Deep copy objectives
	var mission_def = mission_data[mission_id]
	for obj in mission_def.get("objectives", []):
		current_objectives.append(obj.duplicate(true))
	
	mission_states[mission_id] = MissionState.ACTIVE
	_reset_objective_tracking()
	
	mission_started.emit(mission_id)
	mission_updated.emit()
	
	print("MissionManager: Started mission %d - %s" % [mission_id, mission_def.get("name", "Unknown")])
	return true


func _reset_objective_tracking() -> void:
	## Reset tracking variables for objectives
	target_tracking = {}
	objective_timers = {}
	
	for obj in current_objectives:
		match obj.get("type"):
			ObjectiveType.DESTROY_TARGETS:
				target_tracking[obj.id] = {"destroyed": 0, "required": obj.get("count", 1)}
			ObjectiveType.PATROL_AREA:
				target_tracking[obj.id] = {"visited": [], "required": obj.get("patrol_points", 1)}
			ObjectiveType.SURVIVE:
				objective_timers[obj.id] = 0.0


func complete_mission(success: bool) -> void:
	## Complete the current mission
	if current_mission_id < 0:
		return
	
	var mission_id = current_mission_id
	mission_states[mission_id] = MissionState.COMPLETED if success else MissionState.FAILED
	
	mission_completed.emit(mission_id, success)
	mission_updated.emit()
	
	print("MissionManager: Mission %d %s" % [mission_id, "completed" if success else "failed"])
	
	current_mission_id = -1
	current_objectives = []


func _process(delta: float) -> void:
	## Update mission timers and objective tracking
	if current_mission_id < 0:
		return
	
	var time_manager = get_node_or_null("/root/TimeManager")
	var sim_time = time_manager.simulation_time if time_manager else 0.0
	
	# Update survival timers
	for obj in current_objectives:
		if obj.type == ObjectiveType.SURVIVE and obj.get("duration", 0.0) > 0:
			objective_timers[obj.id] = objective_timers.get(obj.id, 0.0) + delta
			if objective_timers[obj.id] >= obj.duration:
				_complete_objective(obj.id)
		
		# Check time limits
		if obj.get("time_limit", 0.0) > 0:
			if not objective_timers.has("start_time"):
				objective_timers["start_time"] = sim_time
			elif sim_time - objective_timers["start_time"] > obj.time_limit:
				_fail_objective(obj.id)
	
	# Check mission time limit
	var mission_def = mission_data.get(current_mission_id, {})
	if mission_def.get("time_limit", 0.0) > 0:
		if not objective_timers.has("mission_start"):
			objective_timers["mission_start"] = sim_time
		elif sim_time - objective_timers["mission_start"] > mission_def.time_limit:
			_fail_mission()


# === Objective Tracking ===

func track_target_destroyed(target: Node) -> void:
	## Track when a target is destroyed
	for obj in current_objectives:
		if obj.type == ObjectiveType.DESTROY_TARGETS:
			var tracking = target_tracking.get(obj.id, {})
			tracking.destroyed = tracking.get("destroyed", 0) + 1
			target_tracking[obj.id] = tracking
			
			if tracking.destroyed >= obj.get("count", 1):
				_complete_objective(obj.id)
	
	mission_updated.emit()


func track_detection(ship: Node) -> void:
	## Track when a target is detected (for detection objectives)
	for obj in current_objectives:
		if obj.type == ObjectiveType.DETECT_TARGETS:
			if not target_tracking.has(obj.id):
				target_tracking[obj.id] = {"detected": [], "required": obj.get("count", 1)}
			
			var tracking = target_tracking[obj.id]
			if not tracking.detected.has(ship):
				tracking.detected.append(ship)
				
				if tracking.detected.size() >= tracking.required:
					_complete_objective(obj.id)
	
	mission_updated.emit()


func track_patrol_point_reached(point_id: int) -> void:
	## Track when a patrol waypoint is reached
	for obj in current_objectives:
		if obj.type == ObjectiveType.PATROL_AREA:
			var tracking = target_tracking.get(obj.id, {"visited": [], "required": 1})
			if not tracking.visited.has(point_id):
				tracking.visited.append(point_id)
				target_tracking[obj.id] = tracking
				
				if tracking.visited.size() >= tracking.required:
					_complete_objective(obj.id)
	
	mission_updated.emit()


func track_stealth_status(detection_level: float) -> void:
	## Track player stealth for stealth objectives
	for obj in current_objectives:
		if obj.type == ObjectiveType.REMAIN_STEALTHY:
			if detection_level >= 1.0:
				_fail_objective(obj.id)


func _complete_objective(objective_id: int) -> void:
	## Mark an objective as completed
	for obj in current_objectives:
		if obj.id == objective_id:
			obj.completed = true
			objective_completed.emit(objective_id)
			
			# Check if all objectives done
			_check_mission_completion()
			break


func _fail_objective(objective_id: int) -> void:
	## Mark an objective as failed
	for obj in current_objectives:
		if obj.id == objective_id:
			obj.failed = true
			objective_failed.emit(objective_id)
			
			# Check if mission should fail
			if not obj.get("optional", false):
				_fail_mission()
			break


func _check_mission_completion() -> void:
	## Check if all mandatory objectives are complete
	var all_complete = true
	var any_failed = false
	
	for obj in current_objectives:
		if obj.get("optional", false):
			continue
		if obj.get("completed", false):
			continue
		if obj.get("failed", false):
			any_failed = true
			all_complete = false
			break
		all_complete = false
	
	if all_complete:
		complete_mission(true)
	elif any_failed:
		complete_mission(false)


func _fail_mission() -> void:
	## Fail the current mission
	complete_mission(false)


func _on_combat_ended() -> void:
	## Handle combat ending
	pass


func _on_ship_destroyed(ship: Node) -> void:
	## Handle ship destruction for tracking
	if ship.has("is_player") and ship.is_player:
		for obj in current_objectives:
			if not obj.get("optional", false):
				if obj.type == ObjectiveType.SURVIVE:
					_fail_objective(obj.id)


# === Mission Info ===

func get_current_mission() -> Dictionary:
	## Get current mission data
	if current_mission_id < 0:
		return {}
	return mission_data.get(current_mission_id, {}).duplicate(true)


func get_current_objectives() -> Array:
	## Get current objectives with tracking data
	var result = []
	for obj in current_objectives:
		var obj_data = obj.duplicate(true)
		obj_data.tracking = target_tracking.get(obj.id, {})
		result.append(obj_data)
	return result


func get_mission_status(mission_id: int) -> int:
	## Get the state of a mission
	return mission_states.get(mission_id, MissionState.INACTIVE)


func get_mission_summary() -> Dictionary:
	## Get a summary of all missions
	var summary = {
		"current_mission": current_mission_id,
		"total_missions": mission_data.size(),
		"completed": 0,
		"failed": 0,
		"available": 0
	}
	
	for mission_id in mission_states.keys():
		match mission_states[mission_id]:
			MissionState.COMPLETED:
				summary.completed += 1
			MissionState.FAILED:
				summary.failed += 1
			MissionState.ACTIVE:
				summary.current_mission = mission_id
			MissionState.INACTIVE:
				# Check if previous missions are complete
				var prev_complete = true
				for prev_id in range(mission_id):
					if mission_states.get(prev_id, MissionState.INACTIVE) != MissionState.COMPLETED:
						prev_complete = false
						break
				if prev_complete:
					summary.available += 1
	
	return summary


func get_next_available_mission() -> int:
	## Get the first available mission to play
	for mission_id in mission_data.keys():
		if mission_states[mission_id] == MissionState.INACTIVE:
			# Check prerequisites (previous mission complete)
			if mission_id == 0 or mission_states.get(mission_id - 1, MissionState.INACTIVE) == MissionState.COMPLETED:
				return mission_id
	return -1


# === Save/Load ===

func save_campaign() -> bool:
	## Save campaign progress
	var save_data = {
		"mission_states": mission_states,
		"version": 1
	}
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("MissionManager: Could not open %s for writing" % save_path)
		return false
	
	var json_string = JSON.stringify(save_data)
	file.store_line(json_string)
	file.close()
	
	print("MissionManager: Campaign saved")
	return true


func load_campaign() -> bool:
	## Load campaign progress
	if not FileAccess.file_exists(save_path):
		print("MissionManager: No save file found")
		return false
	
	var file = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("MissionManager: Could not open %s for reading" % save_path)
		return false
	
	var json_string = file.get_line()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("MissionManager: Failed to parse save data")
		return false
	
	var save_data = json.get_data()
	if save_data is Dictionary:
		if save_data.has("mission_states"):
			mission_states = save_data.mission_states
	
	print("MissionManager: Campaign loaded")
	return true


func reset_campaign() -> void:
	## Reset all campaign progress
	for mission_id in mission_data.keys():
		mission_states[mission_id] = MissionState.INACTIVE
	
	current_mission_id = -1
	current_objectives = []
	
	print("MissionManager: Campaign reset")