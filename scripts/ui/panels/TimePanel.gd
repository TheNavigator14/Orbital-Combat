class_name TimePanel
extends Control

## Panel for time warp controls and display
## CRT phosphor-green aesthetic with scanlines and glow effects

signal warp_changed(warp_factor: float)

# === Time Warp Settings ===
var warp_factors = [1, 2, 5, 10, 25, 50, 100, 500, 1000, 5000, 10000, 50000, 100000]
var current_warp_index: int = 0

# === CRT Effects ===
var flicker_timer: float = 0.0

# === CRT Colors ===
const CRT_GREEN = Color(0.2, 1.0, 0.4)
const CRT_GREEN_DIM = Color(0.1, 0.5, 0.2)
const CRT_GREEN_BRIGHT = Color(0.4, 1.0, 0.6)
const CRT_AMBER = Color(1.0, 0.6, 0.2)
const CRT_GLOW = Color(0.1, 0.5, 0.2, 0.3)

# === Node References ===
@onready var time_label: Label = $VBoxContainer/TimeContainer/TimeLabel
@onready var date_label: Label = $VBoxContainer/DateContainer/DateLabel
@onready var warp_label: Label = $VBoxContainer/WarpContainer/WarpLabel
@onready var warp_bar: ProgressBar = $VBoxContainer/WarpContainer/WarpBar
@onready var warp_buttons: HBoxContainer = $VBoxContainer/WarpButtons
@onready var pause_button: Button = $VBoxContainer/ControlButtons/PauseButton
@onready var real_time_label: Label = $VBoxContainer/RealTimeContainer/RealTimeLabel

var time_manager = null
var game_manager = null

func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)
	
	# Get references to autoloads
	time_manager = get_node("/root/TimeManager") if has_node("/root/TimeManager") else null
	game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	
	_apply_crt_theme()
	_update_warp_display()

func _apply_crt_theme() -> void:
	# Apply phosphor-green color scheme
	var all_labels = [time_label, date_label, warp_label, real_time_label]
	for label in all_labels:
		if label:
			label.add_theme_color_override("font_color", CRT_GREEN)
			label.add_theme_constant_override("shadow_outline_size", 2)
			label.add_theme_color_override("font_shadow_color", CRT_GLOW)
	
	# Style warp label specially
	if warp_label:
		warp_label.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
		warp_label.add_theme_constant_override("outline_size", 2)
	
	# Style warp bar
	if warp_bar:
		warp_bar.add_theme_stylebox_override("fill", _create_crt_progress_style())
		warp_bar.add_theme_color_override("font_color", CRT_GREEN_DIM)

func _create_crt_progress_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = CRT_GREEN
	style.set_corner_radius_all(2)
	return style

func _process(delta: float) -> void:
	# Update CRT flicker
	_update_crt_flicker(delta)
	
	if time_manager == null:
		return
	
	# Update time display
	var sim_time = time_manager.simulation_time
	
	# Display simulation date (days from start)
	var days_elapsed = sim_time / 86400.0
	date_label.text = "Day %.1f" % days_elapsed
	
	# Time of day
	var seconds_of_day = fmod(sim_time, 86400.0)
	var hours = int(seconds_of_day / 3600)
	var minutes = int(fmod(seconds_of_day, 3600) / 60)
	var seconds = int(fmod(seconds_of_day, 60))
	time_label.text = "%02d:%02d:%02d" % [hours, minutes, seconds]
	
	# Warp display
	var warp = time_manager.time_warp
	if warp >= 1000:
		warp_label.text = "WARP: %.0fx" % warp
	elif warp >= 100:
		warp_label.text = "WARP: %.0fx" % warp
	else:
		warp_label.text = "WARP: %.1fx" % warp
	
	# Warp bar (logarithmic scale visualization)
	var warp_normalized = _warp_to_normalized(warp)
	warp_bar.value = warp_normalized * 100
	
	# Pause state - color the button
	if time_manager.is_paused:
		pause_button.text = "RESUME"
		pause_button.add_theme_color_override("font_color", CRT_AMBER)
	else:
		pause_button.text = "PAUSE"
		pause_button.add_theme_color_override("font_color", CRT_GREEN)
	
	# Real time elapsed
	var real_elapsed = Time.get_ticks_msec() / 1000.0
	var rt_hours = int(real_elapsed / 3600)
	var rt_mins = int(fmod(real_elapsed, 3600) / 60)
	var rt_secs = int(fmod(real_elapsed, 60))
	real_time_label.text = "RT: %02d:%02d:%02d" % [rt_hours, rt_mins, rt_secs]

func _warp_to_normalized(warp: float) -> float:
	# Convert warp factor to 0-1 range (logarithmic)
	if warp <= 1:
		return 0.0
	var log_warp = log(warp) / log(100000.0)
	return clamp(log_warp, 0.0, 1.0)

func _normalized_to_warp(normalized: float) -> float:
	# Convert 0-1 range to warp factor
	if normalized <= 0:
		return 1.0
	var warp = pow(100000.0, normalized)
	return clamp(warp, 1.0, 100000.0)

func _update_warp_display() -> void:
	pass

func _on_warp_up_pressed() -> void:
	if current_warp_index < warp_factors.size() - 1:
		current_warp_index += 1
		_apply_warp(warp_factors[current_warp_index])
		warp_changed.emit(warp_factors[current_warp_index])

func _on_warp_down_pressed() -> void:
	if current_warp_index > 0:
		current_warp_index -= 1
		_apply_warp(warp_factors[current_warp_index])
		warp_changed.emit(warp_factors[current_warp_index])

func _on_warp_max_pressed() -> void:
	if time_manager:
		time_manager.set_time_warp(100000.0)
		warp_changed.emit(100000.0)

func _on_warp_1x_pressed() -> void:
	if time_manager:
		time_manager.set_time_warp(1.0)
		current_warp_index = 0
		warp_changed.emit(1.0)

func _on_pause_button_pressed() -> void:
	if time_manager:
		if time_manager.is_paused:
			time_manager.resume()
		else:
			time_manager.pause()

func _apply_warp(factor: float) -> void:
	if time_manager:
		time_manager.set_time_warp(factor)
		# Update index to match
		for i in range(warp_factors.size()):
			if abs(warp_factors[i] - factor) < 0.01:
				current_warp_index = i
				break

func _update_crt_flicker(delta: float) -> void:
	# Subtle phosphor flicker
	flicker_timer += delta
	if flicker_timer > 0.15:
		flicker_timer = 0.0
		if randf() > 0.97:
			modulate = Color(0.88, 0.88, 0.88, 1.0)
		else:
			modulate = Color(1.0, 1.0, 1.0, 1.0)