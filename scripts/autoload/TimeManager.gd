extends Node
## Manages simulation time and time warp
## Autoload singleton - access via TimeManager

signal time_warp_changed(multiplier: float)
signal simulation_paused()
signal simulation_resumed()
signal event_triggered(event_name: String)

# === Time Warp Levels ===
enum WarpLevel {
	PAUSED,      # 0x
	REAL_TIME,   # 1x
	X10,         # 10x
	X100,        # 100x
	X1000,       # 1000x
	X10000,      # 10000x
	X100000      # 100000x
}

const WARP_MULTIPLIERS = {
	WarpLevel.PAUSED: 0.0,
	WarpLevel.REAL_TIME: 1.0,
	WarpLevel.X10: 10.0,
	WarpLevel.X100: 100.0,
	WarpLevel.X1000: 1000.0,
	WarpLevel.X10000: 10000.0,
	WarpLevel.X100000: 100000.0
}

const WARP_LABELS = {
	WarpLevel.PAUSED: "PAUSED",
	WarpLevel.REAL_TIME: "1x",
	WarpLevel.X10: "10x",
	WarpLevel.X100: "100x",
	WarpLevel.X1000: "1,000x",
	WarpLevel.X10000: "10,000x",
	WarpLevel.X100000: "100,000x"
}

# === State ===
var current_warp_level: WarpLevel = WarpLevel.REAL_TIME
var simulation_time: float = 0.0  # Total elapsed simulation time in seconds
var is_paused: bool = false
var max_warp_allowed: WarpLevel = WarpLevel.X100000  # Can be limited during maneuvers

# === Scheduled Events ===
# Events that will auto-pause or trigger actions at specific times
var scheduled_events: Array[Dictionary] = []  # { time: float, name: String, callback: Callable }

# === Properties ===
var warp_multiplier: float:
	get:
		if is_paused:
			return 0.0
		return WARP_MULTIPLIERS[current_warp_level]

var warp_label: String:
	get:
		if is_paused:
			return "PAUSED"
		return WARP_LABELS[current_warp_level]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing even when paused


func _process(delta: float) -> void:
	if is_paused:
		return

	# Advance simulation time
	var sim_delta = delta * warp_multiplier
	simulation_time += sim_delta

	# Check for scheduled events
	_process_scheduled_events()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("time_warp_increase"):
		increase_warp()
	elif event.is_action_pressed("time_warp_decrease"):
		decrease_warp()


# === Time Warp Control ===

func increase_warp() -> void:
	## Increase time warp to next level
	if is_paused:
		resume()
		return

	var new_level = mini(current_warp_level + 1, max_warp_allowed)
	if new_level != current_warp_level:
		set_warp_level(new_level)


func decrease_warp() -> void:
	## Decrease time warp to previous level
	if current_warp_level == WarpLevel.PAUSED:
		return

	if current_warp_level == WarpLevel.REAL_TIME:
		pause()
	else:
		set_warp_level(current_warp_level - 1)


func set_warp_level(level: WarpLevel) -> void:
	## Set specific warp level
	if level > max_warp_allowed:
		level = max_warp_allowed

	if level != current_warp_level:
		current_warp_level = level
		if level == WarpLevel.PAUSED:
			is_paused = true
			simulation_paused.emit()
		else:
			is_paused = false
		time_warp_changed.emit(warp_multiplier)


func set_realtime() -> void:
	## Reset to real-time (1x)
	set_warp_level(WarpLevel.REAL_TIME)


func pause() -> void:
	## Pause simulation
	is_paused = true
	simulation_paused.emit()
	time_warp_changed.emit(0.0)


func resume() -> void:
	## Resume simulation
	if current_warp_level == WarpLevel.PAUSED:
		current_warp_level = WarpLevel.REAL_TIME
	is_paused = false
	simulation_resumed.emit()
	time_warp_changed.emit(warp_multiplier)


func toggle_pause() -> void:
	if is_paused:
		resume()
	else:
		pause()


func limit_warp(max_level: WarpLevel) -> void:
	## Limit maximum warp (e.g., during maneuvers)
	max_warp_allowed = max_level
	if current_warp_level > max_level:
		set_warp_level(max_level)


func remove_warp_limit() -> void:
	## Remove warp limitation
	max_warp_allowed = WarpLevel.X100000


# === Delta Time ===

func get_delta_time(frame_delta: float) -> float:
	## Get scaled delta time for physics/orbital calculations
	if is_paused:
		return 0.0
	return frame_delta * warp_multiplier


# === Scheduled Events ===

func schedule_event(event_time: float, event_name: String, callback: Callable = Callable(), auto_pause: bool = true) -> void:
	## Schedule an event at a specific simulation time
	var event = {
		"time": event_time,
		"name": event_name,
		"callback": callback,
		"auto_pause": auto_pause
	}

	# Insert sorted by time
	var insert_index = 0
	for i in range(scheduled_events.size()):
		if scheduled_events[i].time > event_time:
			break
		insert_index = i + 1

	scheduled_events.insert(insert_index, event)


func cancel_event(event_name: String) -> void:
	## Cancel a scheduled event by name
	for i in range(scheduled_events.size() - 1, -1, -1):
		if scheduled_events[i].name == event_name:
			scheduled_events.remove_at(i)


func get_next_event() -> Dictionary:
	## Get the next scheduled event
	if scheduled_events.size() > 0:
		return scheduled_events[0]
	return {}


func get_time_to_next_event() -> float:
	## Get time until next scheduled event
	if scheduled_events.size() > 0:
		return scheduled_events[0].time - simulation_time
	return INF


func _process_scheduled_events() -> void:
	## Check and trigger any events that have been reached
	while scheduled_events.size() > 0 and scheduled_events[0].time <= simulation_time:
		var event = scheduled_events.pop_front()

		event_triggered.emit(event.name)

		if event.callback.is_valid():
			event.callback.call()

		if event.auto_pause:
			pause()


# === Warp To Time ===

func warp_to_time(target_time: float, final_warp: WarpLevel = WarpLevel.REAL_TIME) -> void:
	## Start warping toward a target time
	## Will schedule an event to return to specified warp level

	if target_time <= simulation_time:
		return

	# Determine appropriate warp level based on time difference
	var dt = target_time - simulation_time
	var warp_level: WarpLevel

	if dt < 60:  # Less than 1 minute
		warp_level = WarpLevel.X10
	elif dt < 3600:  # Less than 1 hour
		warp_level = WarpLevel.X100
	elif dt < 86400:  # Less than 1 day
		warp_level = WarpLevel.X1000
	elif dt < 864000:  # Less than 10 days
		warp_level = WarpLevel.X10000
	else:
		warp_level = WarpLevel.X100000

	# Schedule return to normal warp
	schedule_event(
		target_time,
		"warp_complete",
		func(): set_warp_level(final_warp),
		true
	)

	set_warp_level(warp_level)


# === Utility ===

func get_formatted_time() -> String:
	## Get simulation time as formatted string
	return OrbitalConstantsClass.format_timestamp(simulation_time)


func get_formatted_warp() -> String:
	## Get current warp as formatted string
	return warp_label
