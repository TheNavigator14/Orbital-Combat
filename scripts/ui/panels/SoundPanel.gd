class_name SoundPanel
extends Control
## CRT-styled sound and audio controls panel

@onready var master_container: HBoxContainer = null
@onready var sfx_container: HBoxContainer = null
@onready var ui_container: HBoxContainer = null
@onready var mute_container: HBoxContainer = null

# References
var sound_manager: Node = null

# Theme colors
var crt_green: Color = Color(0.2, 0.9, 0.4)
var crt_dim: Color = Color(0.15, 0.5, 0.3)
var crt_bright: Color = Color(0.4, 1.0, 0.6)

func _ready() -> void:
	custom_minimum_size = Vector2(280, 200)
	setup_ui()
	
	# Try to get SoundManager
	sound_manager = get_node("/root/SoundManager")
	if sound_manager == null:
		# Create it if it doesn't exist
		sound_manager = preload("res://scripts/autoload/SoundManager.gd").new()
		get_tree().root.add_child(sound_manager)
	
	_update_display()


func setup_ui() -> void:
	## Build the CRT-styled UI
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.1, 0.05, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# Title
	var title = Label.new()
	title.text = "[ AUDIO CONTROL ]"
	title.position = Vector2(10, 8)
	title.add_theme_color_override("font_color", crt_bright)
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)
	
	# Separator
	var sep1 = HSeparator.new()
	sep1.position = Vector2(10, 28)
	sep1.size = Vector2(260, 2)
	add_child(sep1)
	
	# Master Volume
	var y = 40
	_add_slider_control("MASTER", 0.0, y, "_on_master_changed")
	
	# SFX Volume
	y += 35
	_add_slider_control("SFX", 1.0, y, "_on_sfx_changed")
	
	# UI Volume
	y += 35
	_add_slider_control("UI", 1.0, y, "_on_ui_changed")
	
	# Mute button
	y += 40
	_add_mute_button(y)
	
	# Test button
	y += 45
	_add_test_button(y)
	
	# Mute status
	var mute_label = Label.new()
	mute_label.name = "MuteLabel"
	mute_label.text = "MUTED: OFF"
	mute_label.position = Vector2(10, y)
	mute_label.add_theme_color_override("font_color", crt_green)
	add_child(mute_label)


func _add_slider_control(label: String, initial_value: float, y_offset: float, callback: String) -> void:
	var container = HBoxContainer.new()
	container.position = Vector2(10, y_offset)
	container.size = Vector2(260, 30)
	add_child(container)
	
	# Label
	var label_node = Label.new()
	label_node.text = label + ":"
	label_node.custom_minimum_size = Vector2(60, 0)
	label_node.add_theme_color_override("font_color", crt_green)
	container.add_child(label_node)
	
	# Slider
	var slider = HSlider.new()
	slider.name = label + "Slider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_make_callback(callback))
	container.add_child(slider)
	
	# Value display
	var value_label = Label.new()
	value_label.name = label + "Value"
	value_label.text = "%d%%" % int(initial_value * 100)
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", crt_dim)
	container.add_child(value_label)


func _add_mute_button(y_offset: float) -> void:
	var container = HBoxContainer.new()
	container.position = Vector2(10, y_offset)
	container.size = Vector2(260, 30)
	add_child(container)
	
	var mute_btn = Button.new()
	mute_btn.text = "[ MUTE ]"
	mute_btn.custom_minimum_size = Vector2(80, 28)
	mute_btn.pressed.connect(_on_mute_pressed)
	container.add_child(mute_btn)
	
	var unmute_btn = Button.new()
	unmute_btn.text = "[ UNMUTE ]"
	unmute_btn.custom_minimum_size = Vector2(90, 28)
	unmute_btn.pressed.connect(_on_unmute_pressed)
	container.add_child(unmute_btn)
	
	var toggle_btn = Button.new()
	toggle_btn.text = "[ TOGGLE ]"
	toggle_btn.custom_minimum_size = Vector2(80, 28)
	toggle_btn.pressed.connect(_on_toggle_mute_pressed)
	container.add_child(toggle_btn)


func _add_test_button(y_offset: float) -> void:
	var test_btn = Button.new()
	test_btn.text = "[ TEST SOUND ]"
	test_btn.position = Vector2(10, y_offset)
	test_btn.custom_minimum_size = Vector2(260, 30)
	test_btn.pressed.connect(_on_test_sound_pressed)
	add_child(test_btn)


func _make_callback(method_name: String) -> Callable:
	return Callable(self, method_name)


func _on_master_changed(value: float) -> void:
	if sound_manager and sound_manager.has_method("set_master_volume"):
		sound_manager.set_master_volume(value)
	_update_slider_label("MASTER", value)


func _on_sfx_changed(value: float) -> void:
	if sound_manager and sound_manager.has_method("set_sfx_volume"):
		sound_manager.set_sfx_volume(value)
	_update_slider_label("SFX", value)


func _on_ui_changed(value: float) -> void:
	if sound_manager and sound_manager.has_method("set_ui_volume"):
		sound_manager.set_ui_volume(value)
	_update_slider_label("UI", value)


func _update_slider_label(name: String, value: float) -> void:
	var container = get_node_or_null(name + "Slider")
	if container and container is HSlider:
		var value_label = container.get_node_or_null(name + "Value")
		if value_label and value_label is Label:
			value_label.text = "%d%%" % int(value * 100)


func _on_mute_pressed() -> void:
	if sound_manager:
		sound_manager.mute()
		_update_mute_display()


func _on_unmute_pressed() -> void:
	if sound_manager:
		sound_manager.unmute()
		_update_mute_display()


func _on_toggle_mute_pressed() -> void:
	if sound_manager:
		sound_manager.toggle_mute()
		_update_mute_display()


func _on_test_sound_pressed() -> void:
	if sound_manager:
		# Test different sound categories
		sound_manager.play_ui("ui_beep")
		await get_tree().create_timer(0.2).timeout
		sound_manager.play("alert_contact")
		await get_tree().create_timer(0.3).timeout
		sound_manager.play("explosion_small")


func _update_mute_display() -> void:
	var mute_label = get_node_or_null("MuteLabel")
	if mute_label and mute_label is Label:
		if sound_manager and sound_manager.is_muted():
			mute_label.text = "MUTED: ON"
			mute_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		else:
			mute_label.text = "MUTED: OFF"
			mute_label.add_theme_color_override("font_color", crt_green)


func _update_display() -> void:
	## Update all displays from current state
	if not sound_manager:
		return
	
	# Update slider values
	var master_slider = get_node_or_null("MASTERSlider")
	if master_slider and master_slider is HSlider:
		master_slider.value = sound_manager.get_master_volume()
	
	_update_mute_display()