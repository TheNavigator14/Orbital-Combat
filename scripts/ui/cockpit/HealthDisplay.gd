class_name HealthDisplay
extends Control
## Cockpit health and damage status display
## Shows ship health bar, critical systems status, and damage alerts

signal damage_taken(amount: float)

@export var warning_threshold: float = 50.0  # Yellow warning at this %
@export var critical_threshold: float = 25.0  # Red critical at this %

# Health bar components
@onready var health_bar_bg: ColorRect = $PanelContainer/VBox/HealthBar/HealthBarBG
@onready var health_bar_fill: ColorRect = $PanelContainer/VBox/HealthBar/HealthBarFill
@onready var health_label: Label = $PanelContainer/VBox/HealthBar/HealthLabel
@onready var status_label: Label = $PanelContainer/VBox/StatusLabel

# Systems panel
@onready var systems_container: VBoxContainer = $PanelContainer/VBox/SystemsScroll/SystemsContainer

# Damage log
@export var max_damage_entries: int = 5
var damage_log: Array = []

var target_ship: Ship = null

func _ready() -> void:
	# Setup UI styling
	_apply_crt_styling()
	
	# Listen for health changes
	health_changed.connect(_on_health_changed)

func setup(ship: Ship) -> void:
	## Connect to ship's health system
	target_ship = ship
	
	if ship:
		ship.health_changed.connect(_on_ship_health_changed)
		ship.critical_system_damaged.connect(_on_critical_system_damaged)
		ship.critical_system_destroyed.connect(_on_critical_system_destroyed)
		ship.ship_destroyed.connect(_on_ship_destroyed)
		
		# Initialize display
		update_health_display(ship.current_health, ship.max_health)
		update_systems_display()

func _apply_crt_styling() -> void:
	## Apply CRT aesthetic to the panel
	modulate = Color(0.9, 1.0, 0.9)
	
	# Setup health bar colors
	if health_bar_fill:
		health_bar_fill.color = Color(0.2, 0.9, 0.2)  # Green

func _on_ship_health_changed(current: float, maximum: float) -> void:
	## Update display when health changes
	update_health_display(current, maximum)

func update_health_display(current: float, maximum: float) -> void:
	## Update the health bar and status
	var percent = (current / maximum) * 100.0 if maximum > 0 else 0.0
	
	# Update bar fill
	if health_bar_fill:
		# Scale bar width
		var bar_width = 180.0 * (current / maximum) if maximum > 0 else 0.0
		health_bar_fill.size.x = bar_width
		
		# Color based on health level
		if percent <= critical_threshold:
			health_bar_fill.color = Color(0.9, 0.2, 0.2)  # Red
		elif percent <= warning_threshold:
			health_bar_fill.color = Color(0.9, 0.8, 0.2)  # Yellow
		else:
			health_bar_fill.color = Color(0.2, 0.9, 0.2)  # Green
	
	# Update label
	if health_label:
		health_label.text = "HULL: %d%%" % int(percent)
		
		# Flash if critical
		if percent <= critical_threshold:
			health_label.modulate = Color(1.0, 0.3, 0.3)
		else:
			health_label.modulate = Color(0.9, 1.0, 0.9)
	
	# Update status
	if status_label:
		if percent <= critical_threshold:
			status_label.text = ">>> CRITICAL DAMAGE <<<"
			status_label.modulate = Color(1.0, 0.2, 0.2)
		elif percent <= warning_threshold:
			status_label.text = "** HULL BREACH **"
			status_label.modulate = Color(1.0, 0.8, 0.2)
		else:
			status_label.text = "NOMINAL"
			status_label.modulate = Color(0.5, 1.0, 0.5)

func update_systems_display() -> void:
	## Update critical systems status
	if not target_ship:
		return
	
	# Clear existing
	for child in systems_container.get_children():
		child.queue_free()
	
	# Add system status rows
	var systems = target_ship.get_critical_status()
	for system_name in systems.keys():
		var status = systems[system_name]
		var row = _create_system_row(system_name, status)
		systems_container.add_child(row)

func _create_system_row(system_name: String, status: Dictionary) -> HBoxContainer:
	## Create a row showing system status
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 18
	
	# System name
	var name_label = Label.new()
	name_label.text = system_name.to_upper()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 10)
	row.add_child(name_label)
	
	# Status indicator
	var status_label = Label.new()
	if status.get("destroyed", false):
		status_label.text = "[OFFLINE]"
		status_label.modulate = Color(0.9, 0.2, 0.2)
	else:
		var health = status.get("health", 100.0)
		if health < 50:
			status_label.text = "[DAMAGED]"
			status_label.modulate = Color(1.0, 0.8, 0.2)
		else:
			status_label.text = "[OK]"
			status_label.modulate = Color(0.4, 1.0, 0.4)
	
	status_label.add_theme_font_size_override("font_size", 10)
	row.add_child(status_label)
	
	return row

func _on_critical_system_damaged(system_name: String, health: float) -> void:
	## Handle critical system taking damage
	add_damage_entry("SYSTEM HIT: " + system_name.to_upper())
	update_systems_display()

func _on_critical_system_destroyed(system_name: String) -> void:
	## Handle critical system being destroyed
	add_damage_entry(">>> " + system_name.to_upper() + " DESTROYED <<<")
	update_systems_display()

func _on_ship_destroyed() -> void:
	## Handle ship destruction
	if status_label:
		status_label.text = "*** SHIP DESTROYED ***"
		status_label.modulate = Color(1.0, 0.1, 0.1)

func add_damage_entry(message: String) -> void:
	## Add entry to damage log
	damage_log.append(message)
	
	# Keep only recent entries
	while damage_log.size() > max_damage_entries:
		damage_log.pop_front()