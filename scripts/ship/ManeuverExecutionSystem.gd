# ManeuverExecutionSystem.gd
# Executes planned maneuvers by controlling ship physics
# Integrates with Ship.gd's maneuver system

class_name ManeuverExecutionSystem
extends Node

# Ship reference (parent should be Ship)
var _ship: Ship = null

# Current active maneuver
var active_maneuver: Dictionary = {}
var burn_remaining: float = 0.0
var current_node_index: int = 0

# Timeline state
var node_timeline: Array = []
var current_time: float = 0.0

# Execution state
enum State { IDLE, EXECUTING, PAUSED, COMPLETED }
var _state: int = State.IDLE

signal maneuver_started(maneuver: Dictionary)
signal maneuver_completed(maneuver: Dictionary)
signal node_reached(node_index: int, node: Dictionary)
signal state_changed(new_state: int)
signal burn_updated(remaining_dv: float)

func _ready() -> void:
	_ship = get_parent() as Ship
	if not _ship:
		push_error("ManeuverExecutionSystem: Parent is not a Ship!")
		set_process(false)

func _process(delta: float) -> void:
	if _state != State.EXECUTING:
		return
	
	current_time += delta
	_execute_current_node(delta)

# === Public API ===

func load_maneuver(maneuver: Dictionary) -> bool:
	"""Load a maneuver from ManeuverPlanningPanel format."""
	if not maneuver.has("nodes") or maneuver.nodes.size() == 0:
		push_error("ManeuverExecutionSystem: Invalid maneuver format - no nodes")
		return false
	
	# Convert planning nodes to execution nodes
	node_timeline.clear()
	for node in maneuver.nodes:
		var exec_node = {
			"type": node.get("type", "burn"),
			"duration": node.get("duration", 10.0),
			"direction": node.get("direction", Vector2.ZERO),
			"thrust_percent": node.get("thrust_percent", 100.0),
			"name": node.get("name", "Node"),
			"delta_v": node.get("delta_v", 0.0),
			"remaining_dv": node.get("delta_v", 0.0)
		}
		node_timeline.append(exec_node)
	
	active_maneuver = maneuver
	current_node_index = 0
	current_time = 0.0
	burn_remaining = maneuver.get("total_delta_v", maneuver.get("delta_v", 0.0))
	_state = State.IDLE
	
	return true

func start() -> bool:
	"""Begin executing the loaded maneuver."""
	if node_timeline.size() == 0:
		push_error("ManeuverExecutionSystem: No maneuver loaded")
		return false
	
	if not _ship:
		push_error("ManeuverExecutionSystem: No ship reference")
		return false
	
	_state = State.EXECUTING
	maneuver_started.emit(active_maneuver)
	state_changed.emit(_state)
	return true

func pause() -> void:
	"""Pause maneuver execution."""
	if _state == State.EXECUTING:
		_stop_thrust()
		_state = State.PAUSED
		state_changed.emit(_state)

func resume() -> void:
	"""Resume paused maneuver."""
	if _state == State.PAUSED:
		_state = State.EXECUTING
		state_changed.emit(_state)

func cancel() -> void:
	"""Cancel the current maneuver."""
	_stop_thrust()
	_state = State.IDLE
	node_timeline.clear()
	current_node_index = 0
	state_changed.emit(_state)

func get_state() -> int:
	return _state

func is_executing() -> bool:
	return _state == State.EXECUTING

func get_progress() -> float:
	"""Get overall maneuver progress (0-1)."""
	if node_timeline.size() == 0:
		return 0.0
	
	var total_duration: float = 0.0
	var completed_duration: float = 0.0
	
	for i in range(node_timeline.size()):
		var node_duration: float = node_timeline[i].duration
		total_duration += node_duration
		if i < current_node_index:
			completed_duration += node_duration
	
	# Add current node progress
	if current_node_index < node_timeline.size():
		var elapsed = current_time - _get_node_start_time()
		completed_duration += elapsed
	
	return clamp(completed_duration / total_duration if total_duration > 0 else 0.0, 0.0, 1.0)

func get_current_node() -> Dictionary:
	if current_node_index < node_timeline.size():
		return node_timeline[current_node_index]
	return {}

func get_burn_remaining() -> float:
	return burn_remaining

func get_total_duration() -> float:
	var total: float = 0.0
	for node in node_timeline:
		total += node.duration
	return total

# === Internal Methods ===

func _execute_current_node(delta: float) -> void:
	"""Execute the current node in the timeline."""
	if current_node_index >= node_timeline.size():
		_complete_maneuver()
		return
	
	var node: Dictionary = node_timeline[current_node_index]
	var elapsed: float = current_time - _get_node_start_time()
	var node_duration: float = node.duration
	
	if elapsed >= node_duration:
		# Move to next node
		_stop_thrust()
		node_reached.emit(current_node_index, node)
		current_node_index += 1
		return
	
	# Execute node type
	match node.type:
		"burn":
			_execute_burn_node(node, delta)
		"coast":
			_stop_thrust()
		"turn":
			_execute_turn_node(node, delta)

func _execute_burn_node(node: Dictionary, delta: float) -> void:
	"""Execute a burn maneuver node using Ship's maneuver system."""
	if not _ship:
		return
	
	var thrust_percent: float = node.get("thrust_percent", 100.0) / 100.0
	var direction: Vector2 = node.get("direction", Vector2.ZERO).normalized()
	
	# Set ship throttle based on thrust percent
	_ship.throttle = thrust_percent
	
	# Calculate burn duration remaining
	var elapsed: float = current_time - _get_node_start_time()
	var remaining: float = node.duration - elapsed
	
	# Execute the burn using ship's thrust system
	var burn_direction: int = _get_burn_direction_enum(direction)
	_ship.start_thrust(burn_direction, thrust_percent)
	
	# Track remaining delta-v
	var dv_consumed: float = _estimate_dv_consumed(thrust_percent, delta)
	burn_remaining = max(0, burn_remaining - dv_consumed)
	node.remaining_dv = burn_remaining
	
	burn_updated.emit(burn_remaining)

func _execute_turn_node(node: Dictionary, delta: float) -> void:
	"""Execute a turn maneuver node."""
	# For turns, just maintain attitude - ship handles rotation separately
	_stop_thrust()

func _stop_thrust() -> void:
	"""Stop all thrust on the ship."""
	if _ship:
		_ship.current_thrust_direction = Ship.ThrustDirection.NONE
		_ship.throttle = 0.0
		_ship.is_executing_maneuver = false

func _complete_maneuver() -> void:
	"""Finish the maneuver execution."""
	_stop_thrust()
	_state = State.COMPLETED
	maneuver_completed.emit(active_maneuver)
	state_changed.emit(_state)

func _get_node_start_time() -> float:
	"""Calculate when the current node started."""
	var start_time: float = 0.0
	for i in range(current_node_index):
		if i < node_timeline.size():
			start_time += node_timeline[i].duration
	return start_time

func _get_burn_direction_enum(direction: Vector2) -> int:
	"""Convert direction vector to Ship.ThrustDirection enum."""
	if direction.length_squared() < 0.1:
		return Ship.ThrustDirection.NONE
	
	# Calculate angle to determine direction
	var angle: float = direction.angle()
	var prograde_angle: float = _ship.orbit_state.velocity.angle() if _ship.orbit_state else 0.0
	var angle_diff: float = abs(fmod(angle - prograde_angle, TAU))
	
	# Classify based on relative angle
	if angle_diff < PI / 4 or angle_diff > 7 * PI / 4:
		return Ship.ThrustDirection.PROGRADE
	elif angle_diff > 3 * PI / 4 and angle_diff < 5 * PI / 4:
		return Ship.ThrustDirection.RETROGRADE
	
	return Ship.ThrustDirection.MANUAL

func _estimate_dv_consumed(thrust_percent: float, delta: float) -> float:
	"""Estimate delta-v consumed during a burn."""
	if not _ship or _ship.total_mass <= 0:
		return 0.0
	
	var thrust_force: float = _ship.max_thrust * thrust_percent
	var acceleration: float = thrust_force / _ship.total_mass
	return acceleration * delta