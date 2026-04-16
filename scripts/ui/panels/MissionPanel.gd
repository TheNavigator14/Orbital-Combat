class_name MissionPanel
extends Control

## Panel displaying mission objectives, progression, and campaign status
## CRT phosphor-green aesthetic with scanlines and glow effects

signal mission_selected(mission_id: int)
signal start_mission_requested(mission_id: int)
signal mission_abandoned()

# === CRT Effects ===
var flicker_timer: float = 0.0

# === CRT Colors ===
const CRT_GREEN = Color(0.2, 1.0, 0.4)
const CRT_GREEN_DIM = Color(0.1, 0.5, 0.2)
const CRT_GREEN_BRIGHT = Color(0.4, 1.0, 0.6)
const CRT_AMBER = Color(1.0, 0.6, 0.2)
const CRT_RED = Color(1.0, 0.3, 0.2)
const CRT_GLOW = Color(0.1, 0.5, 0.2, 0.3)

# === Mission Manager Reference ===
var mission_manager = null

# === Node References ===
@onready var mission_list_container: VBoxContainer = $VBoxContainer/MissionListContainer/MissionList
@onready var mission_details_container: VBoxContainer = $VBoxContainer/DetailsContainer
@onready var mission_title_label: Label = $VBoxContainer/DetailsContainer/MissionTitleLabel
@onready var mission_description_label: Label = $VBoxContainer/DetailsContainer/MissionDescriptionLabel
@onready var objectives_container: VBoxContainer = $VBoxContainer/DetailsContainer/ObjectivesContainer
@onready var mission_status_label: Label = $VBoxContainer/DetailsContainer/StatusContainer/StatusLabel
@onready var time_remaining_label: Label = $VBoxContainer/DetailsContainer/TimeContainer/TimeLabel
@onready var start_button: Button = $VBoxContainer/DetailsContainer/ButtonContainer/StartButton
@onready var abandon_button: Button = $VBoxContainer/DetailsContainer/ButtonContainer/AbandonButton
@onready var campaign_summary_label: Label = $VBoxContainer/CampaignSummaryLabel
@onready var prev_mission_button: Button = $VBoxContainer/MissionNavContainer/PrevMissionBtn
@onready var next_mission_button: Button = $VBoxContainer/MissionNavContainer/NextMissionBtn

# === State ===
var mission_buttons: Array = []
var selected_mission_id: int = -1
var displayed_mission_index: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(300, 500)
	_apply_crt_theme()
	_setup_mission_manager()
	_connect_signals()

func _apply_crt_theme() -> void:
	var labels = [mission_title_label, mission_description_label, mission_status_label, 
		time_remaining_label, campaign_summary_label]
	for label in labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)
			label.add_theme_constant_override("shadow_outline_size", 2)

func _setup_mission_manager() -> void:
	if has_node("/root/MissionManager"):
		mission_manager = get_node("/root/MissionManager")

func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_mission)
	abandon_button.pressed.connect(_on_abandon_mission)
	prev_mission_button.pressed.connect(_on_prev_mission)
	next_mission_button.pressed.connect(_on_next_mission)
	
	if mission_manager:
		mission_manager.mission_started.connect(_on_mission_started)
		mission_manager.mission_completed.connect(_on_mission_completed)
		mission_manager.objective_completed.connect(_on_objective_completed)

func _process(delta: float) -> void:
	_update_crt_flicker(delta)
	if mission_manager:
		_refresh_mission_display()

func _update_crt_flicker(delta: float) -> void:
	flicker_timer += delta
	if flicker_timer > 0.1:
		flicker_timer = 0.0
		if randf() > 0.97:
			modulate = Color(0.88, 0.88, 0.88, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)

func refresh_missions() -> void:
	## Called externally to refresh mission list
	_clear_mission_list()
	_populate_mission_list()
	_update_campaign_summary()

func _clear_mission_list() -> void:
	for btn in mission_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	mission_buttons.clear()

func _populate_mission_list() -> void:
	if not mission_manager:
		return
	
	var mission_ids = range(mission_manager.mission_data.size())
	for mission_id in mission_ids:
		var mission_info = mission_manager.mission_data[mission_id]
		var state = mission_manager.get_mission_status(mission_id)
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(260, 32)
		btn.text = _get_mission_button_text(mission_id, mission_info, state)
		btn.pressed.connect(_on_mission_button_pressed.bind(mission_id))
		
		# Color by state
		match state:
			mission_manager.MissionState.COMPLETED:
				btn.add_theme_color_override("font_color", CRT_GREEN_DIM)
			mission_manager.MissionState.ACTIVE:
				btn.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
			mission_manager.MissionState.FAILED:
				btn.add_theme_color_override("font_color", CRT_RED)
			_:
				btn.add_theme_color_override("font_color", CRT_GREEN_DIM)
		
		mission_list_container.add_child(btn)
		mission_buttons.append(btn)

func _get_mission_button_text(mission_id: int, mission_info: Dictionary, state: int) -> String:
	var prefix = ""
	match state:
		mission_manager.MissionState.COMPLETED:
			prefix = "[OK] "
		mission_manager.MissionState.ACTIVE:
			prefix = "[>>] "
		mission_manager.MissionState.FAILED:
			prefix = "[!!] "
		_:
			prefix = "[--] "
	return prefix + mission_info.get("name", "Mission %d" % mission_id)

func _on_mission_button_pressed(mission_id: int) -> void:
	selected_mission_id = mission_id
	mission_selected.emit(mission_id)
	_update_mission_details(mission_id)

func _update_mission_details(mission_id: int) -> void:
	if not mission_manager or mission_id < 0:
		_clear_details()
		return
	
	var mission_info = mission_manager.get_mission_data(mission_id)
	var state = mission_manager.get_mission_status(mission_id)
	
	if mission_info.is_empty():
		_clear_details()
		return
	
	mission_title_label.text = "[ %s ]" % mission_info.get("name", "Unknown")
	mission_description_label.text = mission_info.get("description", "")
	
	# Update status text
	match state:
		mission_manager.MissionState.INACTIVE:
			mission_status_label.text = "Status: AVAILABLE"
			mission_status_label.add_theme_color_override("font_color", CRT_AMBER)
		mission_manager.MissionState.ACTIVE:
			mission_status_label.text = "Status: IN PROGRESS"
			mission_status_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
		mission_manager.MissionState.COMPLETED:
			mission_status_label.text = "Status: COMPLETED"
			mission_status_label.add_theme_color_override("font_color", CRT_GREEN)
		mission_manager.MissionState.FAILED:
			mission_status_label.text = "Status: FAILED"
			mission_status_label.add_theme_color_override("font_color", CRT_RED)
	
	# Clear and populate objectives
	for child in objectives_container.get_children():
		child.queue_free()
	
	var objectives = mission_info.get("objectives", [])
	for obj in objectives:
		var obj_label = Label.new()
		obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		obj_label.text = _format_objective_text(obj)
		obj_label.add_theme_color_override("font_color", CRT_GREEN_DIM)
		objectives_container.add_child(obj_label)
	
	# Update time limit display
	var time_limit = mission_info.get("time_limit", 0.0)
	if time_limit > 0:
		time_remaining_label.text = "Time Limit: %s" % _format_time(time_limit)
	else:
		time_remaining_label.text = "Time Limit: No limit"
	
	# Show/hide buttons based on state
	start_button.visible = (state == mission_manager.MissionState.INACTIVE)
	abandon_button.visible = (state == mission_manager.MissionState.ACTIVE)

func _format_objective_text(objective: Dictionary) -> String:
	var obj_type = objective.get("type", 0)
	var description = objective.get("description", "Unknown objective")
	var is_optional = objective.get("optional", false)
	var prefix = "[X]" if is_optional else "[*]"
	
	match obj_type:
		0: return "%s DESTROY: %s" % [prefix, description]
		1: return "%s SURVIVE: %s" % [prefix, description]
		2: return "%s PATROL: %s" % [prefix, description]
		3: return "%s REACH: %s" % [prefix, description]
		4: return "%s ESCORT: %s" % [prefix, description]
		5: return "%s INTERCEPT: %s" % [prefix, description]
		6: return "%s DETECT: %s" % [prefix, description]
		7: return "%s ANALYZE: %s" % [prefix, description]
		8: return "%s STEALTH: %s" % [prefix, description]
		9: return "%s ESCAPE: %s" % [prefix, description]
		10: return "%s COUNTERMEASURES: %s" % [prefix, description]
	return "%s %s" % [prefix, description]

func _format_time(seconds: float) -> String:
	if seconds < 60:
		return "%.0f sec" % seconds
	elif seconds < 3600:
		return "%.1f min" % (seconds / 60.0)
	else:
		return "%.1f hr" % (seconds / 3600.0)

func _clear_details() -> void:
	mission_title_label.text = "[ NO MISSION SELECTED ]"
	mission_description_label.text = "Select a mission from the list to view details."
	mission_status_label.text = "Status: ---"
	time_remaining_label.text = "Time Limit: ---"
	
	for child in objectives_container.get_children():
		child.queue_free()
	
	start_button.visible = false
	abandon_button.visible = false

func _refresh_mission_display() -> void:
	## Update active mission progress display
	if selected_mission_id < 0:
		return
	
	var state = mission_manager.get_mission_status(selected_mission_id)
	if state == mission_manager.MissionState.ACTIVE:
		_update_active_objectives()

func _update_active_objectives() -> void:
	## Update objective progress for active mission
	pass  # Could add real-time progress tracking here

func _update_campaign_summary() -> void:
	if not mission_manager:
		campaign_summary_label.text = "Campaign: N/A"
		return
	
	var summary = mission_manager.get_mission_summary()
	campaign_summary_label.text = "Campaign: %d/%d missions" % [
		summary.completed, summary.total_missions
	]

func _on_start_mission() -> void:
	if mission_manager and selected_mission_id >= 0:
		mission_manager.start_mission(selected_mission_id)
		start_mission_requested.emit(selected_mission_id)
		refresh_missions()

func _on_abandon_mission() -> void:
	if mission_manager and selected_mission_id >= 0:
		mission_manager.fail_mission("Player abandoned mission")
		mission_abandoned.emit()
		refresh_missions()

func _on_mission_started(mission_id: int) -> void:
	refresh_missions()

func _on_mission_completed(mission_id: int, success: bool) -> void:
	refresh_missions()

func _on_objective_completed(objective_id: int) -> void:
	refresh_missions()

func _on_prev_mission() -> void:
	if not mission_manager:
		return
	var total = mission_manager.mission_data.size()
	if total <= 1:
		return
	displayed_mission_index = (displayed_mission_index - 1 + total) % total
	selected_mission_id = displayed_mission_index
	_update_mission_details(selected_mission_id)

func _on_next_mission() -> void:
	if not mission_manager:
		return
	var total = mission_manager.mission_data.size()
	if total <= 1:
		return
	displayed_mission_index = (displayed_mission_index + 1) % total
	selected_mission_id = displayed_mission_index
	_update_mission_details(selected_mission_id)

func select_next_available() -> void:
	## Public method to auto-select next available mission
	if not mission_manager:
		return
	var next_id = mission_manager.get_next_available_mission()
	if next_id >= 0:
		selected_mission_id = next_id
		_update_mission_details(next_id)