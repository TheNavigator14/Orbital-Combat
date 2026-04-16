class_name Squadron
extends Node2D
## Manages multiple AI ships operating as a coordinated squadron
## Handles formation flying, shared targeting, and tactical coordination

signal squad_state_changed(from_state: int, to_state: int)
signal leader_changed(new_leader: EnemyAIShip)
signal formation_changed(formation_type: int)
signal target_priority_updated(target: Node2D)
signal squad_member_lost(member: EnemyAIShip)
signal squad_member_added(member: EnemyAIShip)

# === Squadron Formation Types ===
enum FormationType {
	LINE = 0,        # Ships in a line behind leader
	DIAMOND = 1,     # Diamond formation
	ECHELON = 2,     # Angled line
	LINE_ABREAST = 3 # Side-by-side line
}

# === Squadron States ===
enum SquadState {
	FORMING = 0,     # Squadron assembling
	PATROL = 1,      # Coordinated patrol
	TRANSIT = 2,     # Moving to location
	HUNTING = 3,     # Actively searching for targets
	ENGAGING = 4,    # In combat
	RETREATING = 5,  # Withdrawing
	REORGANIZING = 6 # Reforming after member loss
}

# === Configuration ===
@export var squad_name: String = "Squadron"
@export var formation_type: FormationType = FormationType.ECHELON
@export var formation_spacing: float = 5000.0  # meters between ships
@export var max_members: int = 6
@export var min_members: int = 2

@export var shared_sensor_range: float = 500000.0  # Ships share sensor contacts in this range
@export var communication_delay: float = 0.5  # Seconds for target info to spread
@export var coordination_range: float = 200000.0  # Ships coordinate within this range

@export var patrol_area_radius: float = 1000000.0
@export var engagement_range: float = 80000.0
@export var disengage_range: float = 300000.0
@export var retreat_health_threshold: float = 0.25

# === State ===
var squad_state: SquadState = SquadState.PATROL
var previous_state: SquadState = SquadState.PATROL
var members: Array = []  # Array of EnemyAIShip
var leader: EnemyAIShip = null  # Primary ship (usually first or healthiest)
var wingmen: Dictionary = {}  # Slot name -> EnemyAIShip

var shared_targets: Dictionary = {}  # target -> {source_ship, confidence, timestamp}
var target_priority_list: Array = []
var primary_target: Node2D = null

var formation_offset_positions: Dictionary = {}
var is_in_formation: bool = true

var patrol_center: Vector2 = Vector2.ZERO
var patrol_center_body: CelestialBody = null

var state_timer: float = 0.0
var reorganization_timer: float = 0.0
var communication_queue: Array = []


func _ready() -> void:
	print("Squadron: Initialized - ", squad_name)
	_setup_default_formation()


func _process(delta: float) -> void:
	state_timer += delta
	
	match squad_state:
		SquadState.FORMING:
			_process_forming(delta)
		SquadState.PATROL:
			_process_patrol(delta)
		SquadState.TRANSIT:
			_process_transit(delta)
		SquadState.HUNTING:
			_process_hunting(delta)
		SquadState.ENGAGING:
			_process_engaging(delta)
		SquadState.RETREATING:
			_process_retreating(delta)
		SquadState.REORGANIZING:
			_process_reorganizing(delta)
	
	# Always update shared intelligence
	_process_shared_intelligence(delta)
	_update_target_priorities(delta)


func _process_forming(delta: float) -> void:
	if members.size() >= min_members and leader != null:
		set_squad_state(SquadState.PATROL)


func _process_patrol(delta: float) -> void:
	# Check for detected targets
	if shared_targets.size() > 0:
		set_squad_state(SquadState.HUNTING)


func _process_transit(delta: float) -> void:
	# Transit to waypoint - all ships follow leader
	if _is_squadron_at_waypoint():
		set_squad_state(SquadState.PATROL)


func _process_hunting(delta: float) -> void:
	if primary_target != null and _is_target_in_range(primary_target):
		set_squad_state(SquadState.ENGAGING)
	elif shared_targets.size() == 0:
		set_squad_state(SquadState.PATROL)


func _process_engaging(delta: float) -> void:
	if primary_target == null or not _is_target_in_range(primary_target):
		set_squad_state(SquadState.HUNTING)
	elif _should_retreat():
		set_squad_state(SquadState.RETREATING)


func _process_retreating(delta: float) -> void:
	# All ships in squadron retreat together
	if not _should_retreat() and primary_target != null:
		set_squad_state(SquadState.ENGAGING)
	elif not _should_retreat() and primary_target == null:
		set_squad_state(SquadState.PATROL)


func _process_reorganizing(delta: float) -> void:
	reorganization_timer += delta
	if reorganization_timer > 3.0:
		reorganization_timer = 0.0
		_reevaluate_leader()
		if members.size() >= min_members:
			set_squad_state(SquadState.PATROL)


func _process_shared_intelligence(delta: float) -> void:
	## Share target information between squadron members
	for member in members:
		if not is_instance_valid(member):
			continue
		
		# Collect targets detected by each member
		var detected = _get_member_targets(member)
		for target in detected:
			var tpos = _get_target_position(target)
			if tpos != Vector2.ZERO and world_position.distance_to(tpos) < shared_sensor_range:
				_add_shared_target(target, member)


func _get_member_targets(member: EnemyAIShip) -> Array:
	## Get targets detected by a specific member
	var targets = []
	if member.has("detected_targets"):
		targets = member.get("detected_targets")
	return targets


func _get_target_position(target) -> Vector2:
	if target == null:
		return Vector2.ZERO
	if target.has("world_position"):
		return target.world_position
	elif target.has("position"):
		return target.position
	return Vector2.ZERO


func _add_shared_target(target: Node2D, source_member: EnemyAIShip) -> void:
	var target_id = _get_target_id(target)
	
	if target_id in shared_targets:
		# Update existing entry
		shared_targets[target_id]["confidence"] = min(1.0, shared_targets[target_id]["confidence"] + 0.1)
		shared_targets[target_id]["timestamp"] = Time.get_ticks_msec()
	else:
		# New target
		shared_targets[target_id] = {
			"target": target,
			"source_ship": source_member,
			"confidence": 0.5,  # Lower confidence for shared info
			"timestamp": Time.get_ticks_msec()
		}


func _get_target_id(target: Node2D) -> int:
	return target.get_instance_id() if is_instance_valid(target) else 0


func _update_target_priorities(delta: float) -> void:
	## Sort targets by priority
	target_priority_list.clear()
	
	var entries = []
	for target_id in shared_targets.keys():
		var entry = shared_targets[target_id]
		if not is_instance_valid(entry.get("target")):
			continue
		
		var priority = _calculate_target_priority(entry)
		entries.append({"id": target_id, "priority": priority})
	
	# Sort by priority (highest first)
	entries.sort_custom(func(a, b): return a["priority"] > b["priority"])
	
	for entry in entries:
		target_priority_list.append(shared_targets[entry["id"]]["target"])
	
	# Update primary target
	var new_primary = target_priority_list[0] if target_priority_list.size() > 0 else null
	if new_primary != primary_target:
		primary_target = new_primary
		if is_instance_valid(primary_target):
			target_priority_updated.emit(primary_target)


func _calculate_target_priority(entry: Dictionary) -> float:
	var target = entry.get("target")
	var confidence = entry.get("confidence", 0.0)
	var priority = 0.0
	
	# Distance factor (closer = higher priority for engagement)
	var tpos = _get_target_position(target)
	var distance = world_position.distance_to(tpos)
	priority += max(0, 500.0 - distance / 2000.0)
	
	# Threat assessment
	if target.has("is_alive"):
		priority += 100.0 if target.get("is_alive") else -200.0
	
	# Confidence factor
	priority *= confidence
	
	# Is it a player ship?
	if target.has("ship_name"):
		var name = target.get("ship_name").to_lower()
		if "player" in name or "alpha" in name or "bravo" in name:
			priority *= 1.5
	
	return priority


func _is_target_in_range(target: Node2D) -> bool:
	var tpos = _get_target_position(target)
	return world_position.distance_to(tpos) < engagement_range


func _should_retreat() -> bool:
	## Check if squadron should retreat based on collective health
	var total_health = 0.0
	var total_max_health = 0.0
	
	for member in members:
		if is_instance_valid(member) and member.has("current_health"):
			total_health += member.get("current_health")
			total_max_health += member.get("max_health")
	
	if total_max_health <= 0:
		return false
	
	return (total_health / total_max_health) < retreat_health_threshold


func _is_squadron_at_waypoint() -> bool:
	## Check if leader has reached transit waypoint
	if leader == null or not is_instance_valid(leader):
		return true
	
	# If no more maneuvers, we're at waypoint
	return leader.get("planned_maneuvers").size() == 0


# === Squadron Management ===

func add_member(ship: EnemyAIShip) -> bool:
	## Add a ship to the squadron
	if members.size() >= max_members:
		print("Squadron: Cannot add ", ship.ship_name, " - squadron full")
		return false
	
	if ship in members:
		return false
	
	members.append(ship)
	_assign_formation_slot(ship)
	
	# If no leader, assign this ship
	if leader == null:
		_set_leader(ship)
	
	# Subscribe to ship events
	_connect_member_signals(ship)
	
	squad_member_added.emit(ship)
	print("Squadron: Added ", ship.ship_name, " (", members.size(), "/", max_members, ")")
	
	return true


func _connect_member_signals(ship: EnemyAIShip) -> void:
	if not ship.tree_exiting.is_connected(_on_member_leaving):
		ship.tree_exiting.connect(_on_member_leaving)
	if ship.has_signal("ship_destroyed") and not ship.ship_destroyed.is_connected(_on_member_destroyed):
		ship.ship_destroyed.connect(_on_member_destroyed)


func remove_member(ship: EnemyAIShip) -> void:
	if not (ship in members):
		return
	
	# Clean up connections
	_disconnect_member_signals(ship)
	
	_remove_formation_slot(ship)
	members.erase(ship)
	
	# Reevaluate if leader was removed
	if ship == leader:
		_reevaluate_leader()
	
	squad_member_lost.emit(ship)
	print("Squadron: Removed ", ship.ship_name, " (", members.size(), " remaining)")
	
	# Reorganize if too few members
	if members.size() < min_members and squad_state == SquadState.ENGAGING:
		set_squad_state(SquadState.REORGANIZING)


func _disconnect_member_signals(ship: EnemyAIShip) -> void:
	if ship.tree_exiting.is_connected(_on_member_leaving):
		ship.tree_exiting.disconnect(_on_member_leaving)
	if ship.has_signal("ship_destroyed") and ship.ship_destroyed.is_connected(_on_member_destroyed):
		ship.ship_destroyed.disconnect(_on_member_destroyed)


func _on_member_leaving() -> void:
	# Find and remove the ship that left
	for m in members:
		if not is_instance_valid(m):
			members.erase(m)


func _on_member_destroyed() -> void:
	# Ship handles its own removal via tree_exiting
	pass


func _reevaluate_leader() -> void:
	## Select new leader if current one is gone or damaged
	if leader == null or not is_instance_valid(leader):
		# Pick healthiest ship
		var best_ship = null
		var best_health = -1.0
		
		for member in members:
			if is_instance_valid(member) and member.has("current_health"):
				var health = member.get("current_health")
				if health > best_health:
					best_health = health
					best_ship = member
		
		if best_ship != null:
			_set_leader(best_ship)


func _set_leader(new_leader: EnemyAIShip) -> void:
	if new_leader == leader:
		return
	
	leader = new_leader
	
	# Update wingmen to follow new leader
	for member in members:
		if member != leader and is_instance_valid(member):
			_configure_as_wingman(member)
	
	leader_changed.emit(leader)


func _configure_as_wingman(member: EnemyAIShip) -> void:
	## Configure a ship as a wingman following the leader
	if member.has("set_wingman_mode"):
		member.set_wingman_mode(true)
	if member.has("set_formation_target"):
		member.set_formation_target(leader)


# === Formation System ===

func _setup_default_formation() -> void:
	## Calculate formation positions based on type
	formation_offset_positions.clear()
	
	match formation_type:
		FormationType.LINE:
			_setup_line_formation()
		FormationType.DIAMOND:
			_setup_diamond_formation()
		FormationType.ECHELON:
			_setup_echelon_formation()
		FormationType.LINE_ABREAST:
			_setup_line_abreast_formation()


func _setup_line_formation() -> void:
	## Ships in vertical line behind leader
	var positions = [
		Vector2(0, formation_spacing),
		Vector2(0, formation_spacing * 2),
		Vector2(0, -formation_spacing),
		Vector2(0, -formation_spacing * 2),
		Vector2(formation_spacing, 0),
		Vector2(-formation_spacing, 0)
	]
	_assign_formation_positions(positions)


func _setup_diamond_formation() -> void:
	## Diamond shape around leader
	var positions = [
		Vector2(0, formation_spacing),
		Vector2(formation_spacing * 0.866, -formation_spacing * 0.5),
		Vector2(-formation_spacing * 0.866, -formation_spacing * 0.5),
		Vector2(0, -formation_spacing),
		Vector2(formation_spacing, formation_spacing * 0.5),
		Vector2(-formation_spacing, formation_spacing * 0.5)
	]
	_assign_formation_positions(positions)


func _setup_echelon_formation() -> void:
	## Staggered line
	var positions = [
		Vector2(formation_spacing * 0.5, formation_spacing),
		Vector2(formation_spacing, formation_spacing * 2),
		Vector2(-formation_spacing * 0.5, formation_spacing),
		Vector2(-formation_spacing, formation_spacing * 2),
		Vector2(0, -formation_spacing),
		Vector2(formation_spacing * 1.5, formation_spacing * 1.5)
	]
	_assign_formation_positions(positions)


func _setup_line_abreast_formation() -> void:
	## Side-by-side line
	var positions = [
		Vector2(-formation_spacing * 2, 0),
		Vector2(-formation_spacing, 0),
		Vector2(formation_spacing, 0),
		Vector2(formation_spacing * 2, 0),
		Vector2(0, formation_spacing),
		Vector2(0, -formation_spacing)
	]
	_assign_formation_positions(positions)


func _assign_formation_positions(positions: Array) -> void:
	for i in range(positions.size()):
		formation_offset_positions[i] = positions[i]


func _assign_formation_slot(ship: EnemyAIShip) -> void:
	## Assign a formation position to a new ship
	if leader == null:
		return
	
	var slot = members.find(ship)
	if slot < 0 or slot >= formation_offset_positions.size():
		return
	
	# Store formation slot for this member
	wingmen[ship.get_instance_id()] = slot
	
	# Apply formation offset to wingman
	if ship.has("set_formation_offset"):
		ship.set_formation_offset(formation_offset_positions[slot])


func _remove_formation_slot(ship: EnemyAIShip) -> void:
	## Clean up formation assignment
	wingmen.erase(ship.get_instance_id())


func set_formation_type(new_type: FormationType) -> void:
	formation_type = new_type
	_setup_default_formation()
	formation_changed.emit(formation_type)


func get_formation_offset(ship: EnemyAIShip) -> Vector2:
	## Get the formation offset for a specific ship
	var slot = wingmen.get(ship.get_instance_id(), 0)
	return formation_offset_positions.get(slot, Vector2.ZERO)


# === State Management ===

func set_squad_state(new_state: SquadState) -> void:
	if new_state == squad_state:
		return
	
	previous_state = squad_state
	squad_state = new_state
	
	match new_state:
		SquadState.FORMING:
			_enter_forming()
		SquadState.PATROL:
			_enter_patrol()
		SquadState.TRANSIT:
			_enter_transit()
		SquadState.HUNTING:
			_enter_hunting()
		SquadState.ENGAGING:
			_enter_engaging()
		SquadState.RETREATING:
			_enter_retreating()
		SquadState.REORGANIZING:
			_enter_reorganizing()
	
	squad_state_changed.emit(previous_state, new_state)
	print("Squadron %s: State %s -> %s" % [squad_name, _get_state_name(previous_state), _get_state_name(new_state)])


func _get_state_name(state: int) -> String:
	match state:
		SquadState.FORMING: return "FORMING"
		SquadState.PATROL: return "PATROL"
		SquadState.TRANSIT: return "TRANSIT"
		SquadState.HUNTING: return "HUNTING"
		SquadState.ENGAGING: return "ENGAGING"
		SquadState.RETREATING: return "RETREATING"
		SquadState.REORGANIZING: return "REORGANIZING"
	return "UNKNOWN"


func _enter_forming() -> void:
	is_in_formation = true


func _enter_patrol() -> void:
	primary_target = null
	# Individual ships handle their own patrol state


func _enter_transit() -> void:
	# All ships follow leader's transit path
	pass


func _enter_hunting() -> void:
	for member in members:
		if is_instance_valid(member) and member.has("force_engage"):
			if is_instance_valid(primary_target):
				member.force_engage(primary_target)


func _enter_engaging() -> void:
	if primary_target != null:
		for member in members:
			if is_instance_valid(member) and member.has("force_engage"):
				member.force_engage(primary_target)


func _enter_retreating() -> void:
	for member in members:
		if is_instance_valid(member) and member.has("disengage"):
			member.disengage()


func _enter_reorganizing() -> void:
	reorganization_timer = 0.0


# === Commands ===

func set_patrol_area(center_body: CelestialBody, radius: float) -> void:
	patrol_center_body = center_body
	patrol_center = center_body.world_position if center_body else Vector2.ZERO
	patrol_area_radius = radius


func attack_target(target: Node2D) -> void:
	## Direct all ships to attack a target
	primary_target = target
	set_squad_state(SquadState.ENGAGING)
	
	for member in members:
		if is_instance_valid(member) and member.has("force_engage"):
			member.force_engage(target)


func disengage_all() -> void:
	## Pull all ships out of combat
	primary_target = null
	set_squad_state(SquadState.PATROL)
	
	for member in members:
		if is_instance_valid(member) and member.has("disengage"):
			member.disengage()


# === Status ===

func get_member_count() -> int:
	return members.size()


func get_member_at(index: int) -> EnemyAIShip:
	if index >= 0 and index < members.size():
		return members[index]
	return null


func get_alive_members() -> Array:
	var alive = []
	for member in members:
		if is_instance_valid(member) and member.get("is_alive", true):
			alive.append(member)
	return alive


func get_squadron_health() -> float:
	## Get average health percentage of squadron
	var alive = get_alive_members()
	if alive.size() == 0:
		return 0.0
	
	var total_health = 0.0
	for member in alive:
		if member.has("get_health_percent"):
			total_health += member.get_health_percent()
	
	return total_health / float(alive.size())


func get_squadron_data() -> Dictionary:
	return {
		"name": squad_name,
		"state": squad_state,
		"state_name": _get_state_name(squad_state),
		"member_count": members.size(),
		"leader": leader.ship_name if leader != null and is_instance_valid(leader) else "None",
		"formation": formation_type,
		"primary_target": primary_target.ship_name if primary_target != null and is_instance_valid(primary_target) else "None",
		"shared_targets": shared_targets.size(),
		"health": get_squadron_health()
	}


# === Position ===

var world_position: Vector2:
	get:
		if leader != null and is_instance_valid(leader):
			return leader.world_position
		# Fallback to average position
		if members.size() == 0:
			return Vector2.ZERO
		var sum = Vector2.ZERO
		var count = 0
		for member in members:
			if is_instance_valid(member):
				sum += member.world_position
				count += 1
		return sum / count if count > 0 else Vector2.ZERO