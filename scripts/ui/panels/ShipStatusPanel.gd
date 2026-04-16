class_name ShipStatusPanel
extends PanelContainer
## Ship status readout panel for cockpit display
## Shows fuel, health, thrust status, and critical systems

@onready var fuel_bar: TextureProgressBar = null
@onready var health_bar: TextureProgressBar = null
@onready var thrust_label: Label = null
@onready var orbit_label: Label = null
@onready var altitude_label: Label = null
@onready var velocity_label: Label = null
@onready var critical_systems_container: VBoxContainer = null

var _player_ship: Ship = null

func _ready() -> void:
	_setup_ui_elements()
	_connect_to_ship()
	
	# Initial update
	await get_tree().physics_frame
	_update_status()


func _setup_ui_elements() -> void:
	## Find or create UI elements
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = ">> SHIP STATUS <<"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Fuel section
	var fuel_container = HBoxContainer.new()
	vbox.add_child(fuel_container)
	
	var fuel_label = Label.new()
	fuel_label.text = "FUEL:"
	fuel_label.custom_minimum_size.x = 60
	fuel_container.add_child(fuel_label)
	
	fuel_bar = TextureProgressBar.new()
	fuel_bar.name = "FuelBar"
	fuel_bar.custom_minimum_size = Vector2(120, 16)
	fuel_bar.max_value = 100
	fuel_bar.value = 100
	fuel_bar.step = 1
	fuel_container.add_child(fuel_bar)
	
	var fuel_pct = Label.new()
	fuel_pct.name = "FuelPct"
	fuel_pct.text = "100%"
	fuel_pct.custom_minimum_size.x = 45
	fuel_container.add_child(fuel_pct)
	
	# Health section
	var health_container = HBoxContainer.new()
	vbox.add_child(health_container)
	
	var health_label = Label.new()
	health_label.text = "HLTH:"
	health_label.custom_minimum_size.x = 60
	health_container.add_child(health_label)
	
	health_bar = TextureProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size = Vector2(120, 16)
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.step = 1
	health_container.add_child(health_bar)
	
	var health_pct = Label.new()
	health_pct.name = "HealthPct"
	health_pct.text = "100%"
	health_pct.custom_minimum_size.x = 45
	health_container.add_child(health_pct)
	
	# Thrust status
	thrust_label = Label.new()
	thrust_label.text = "THRUST: IDLE"
	thrust_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(thrust_label)
	
	# Orbit info
	orbit_label = Label.new()
	orbit_label.text = "ORBIT: --"
	orbit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(orbit_label)
	
	# Altitude
	altitude_label = Label.new()
	altitude_label.text = "ALT: -- km"
	altitude_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(altitude_label)
	
	# Velocity
	velocity_label = Label.new()
	velocity_label.text = "VEL: -- m/s"
	velocity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(velocity_label)
	
	# Critical systems header
	var crit_header = Label.new()
	crit_header.text = "--- SYSTEMS ---"
	crit_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(crit_header)
	
	# Critical systems list
	critical_systems_container = VBoxContainer.new()
	critical_systems_container.name = "CriticalSystems"
	vbox.add_child(critical_systems_container)


func _connect_to_ship() -> void:
	## Connect to player ship signals
	var main = get_tree().root.get_node("Main")
	if main and main.has("player_ship"):
		_player_ship = main.player_ship
		
		if _player_ship:
			if _player_ship.has_signal("fuel_depleted"):
				_player_ship.fuel_depleted.connect(_on_fuel_depleted)
			if _player_ship.has_signal("health_changed"):
				_player_ship.health_changed.connect(_on_health_changed)
			if _player_ship.has_signal("thrust_started"):
				_player_ship.thrust_started.connect(_on_thrust_changed)
			if _player_ship.has_signal("thrust_ended"):
				_player_ship.thrust_ended.connect(_on_thrust_changed)
			if _player_ship.has_signal("critical_system_damaged"):
				_player_ship.critical_system_damaged.connect(_on_system_damaged)
			if _player_ship.has_signal("critical_system_destroyed"):
				_player_ship.critical_system_destroyed.connect(_on_system_destroyed)
	
	# Update at regular interval
	var timer = Timer.new()
	timer.name = "UpdateTimer"
	timer.wait_time = 0.5
	timer.timeout.connect(_update_status)
	add_child(timer)
	timer.start()


func _update_status() -> void:
	## Update all status displays
	if not is_instance_valid(self):
		return
	
	if _player_ship and is_instance_valid(_player_ship):
		# Fuel
		var fuel_pct = _player_ship.get_fuel_percent()
		if fuel_bar:
			fuel_bar.value = fuel_pct
		
		var fuel_label = find_child("FuelPct", false, false)
		if fuel_label and fuel_label is Label:
			fuel_label.text = "%d%%" % int(fuel_pct)
		
		# Color fuel bar based on level
		if fuel_bar:
			if fuel_pct < 10:
				fuel_bar.modulate = Color.RED
			elif fuel_pct < 25:
				fuel_bar.modulate = Color.ORANGE
			else:
				fuel_bar.modulate = Color.GREEN
		
		# Health
		if _player_ship.has_method("get_health_percent"):
			var health_pct = _player_ship.get_health_percent()
			if health_bar:
				health_bar.value = health_pct
			
			var health_label = find_child("HealthPct", false, false)
			if health_label and health_label is Label:
				health_label.text = "%d%%" % int(health_pct)
			
			# Color health bar
			if health_bar:
				if health_pct < 25:
					health_bar.modulate = Color.RED
				elif health_pct < 50:
					health_bar.modulate = Color.ORANGE
				else:
					health_bar.modulate = Color.GREEN
		
		# Thrust status
		if thrust_label:
			if _player_ship.is_thrusting:
				var dir_names = ["NONE", "PRO", "RETRO", "RAD-IN", "RAD-OUT", "MANUAL"]
				var dir_idx = _player_ship.current_thrust_direction as int
				var dir_name = dir_names[dir_idx] if dir_idx < dir_names.size() else "ACTIVE"
				var throttle_pct = int(_player_ship.throttle * 100)
				thrust_label.text = "THRUST: %s %d%%" % [dir_name, throttle_pct]
				thrust_label.modulate = Color.GREEN
			else:
				thrust_label.text = "THRUST: IDLE"
				thrust_label.modulate = Color.GRAY
		
		# Orbit info
		if orbit_label:
			if _player_ship.parent_body:
				var body_name = _player_ship.parent_body.body_name if "body_name" in _player_ship.parent_body else "Body"
				orbit_label.text = "ORBIT: %s" % body_name
			else:
				orbit_label.text = "ORBIT: SUN"
		
		# Altitude
		if altitude_label:
			var alt_km = _player_ship.altitude_above_parent / 1000.0
			altitude_label.text = "ALT: %.1f km" % alt_km
		
		# Velocity
		if velocity_label:
			if _player_ship.orbit_state:
				var vel_ms = _player_ship.orbit_state.velocity.length()
				velocity_label.text = "VEL: %.1f m/s" % vel_ms


func _on_fuel_depleted() -> void:
	if fuel_bar:
		fuel_bar.modulate = Color.RED
	if thrust_label:
		thrust_label.text = "THRUST: NO FUEL"
		thrust_label.modulate = Color.RED


func _on_health_changed(current: float, maximum: float) -> void:
	# Updates handled in _update_status
	pass


func _on_thrust_changed() -> void:
	# Updates handled in _update_status
	pass


func _on_system_damaged(system_name: String, health: float) -> void:
	_update_critical_systems()


func _on_system_destroyed(system_name: String) -> void:
	_update_critical_systems()
	
	# Flash warning
	if thrust_label:
		thrust_label.text = "SYSTEM OFFLINE: %s" % system_name.to_upper()
		thrust_label.modulate = Color.RED


func _update_critical_systems() -> void:
	## Update critical systems display
	if not critical_systems_container:
		return
	
	# Clear existing
	for child in critical_systems_container.get_children():
		child.queue_free()
	
	if not _player_ship:
		return
	
	# Get critical systems status
	var systems = _player_ship.get_critical_status()
	
	for system_name in systems.keys():
		var status = systems[system_name]
		var system_label = Label.new()
		
		var health_pct = (status["health"] / 100.0) * 100.0
		var destroyed = status.get("destroyed", false)
		var critical = status.get("critical", false)
		
		if destroyed:
			system_label.text = "[OFFLINE] %s" % system_name.to_upper()
			system_label.modulate = Color.RED
		elif critical or health_pct < 50:
			system_label.text = "[DAMAGED] %s: %d%%" % [system_name.capitalize(), int(health_pct)]
			system_label.modulate = Color.ORANGE
		else:
			system_label.text = "[OK] %s: %d%%" % [system_name.capitalize(), int(health_pct)]
			system_label.modulate = Color.GREEN
		
		system_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		critical_systems_container.add_child(system_label)