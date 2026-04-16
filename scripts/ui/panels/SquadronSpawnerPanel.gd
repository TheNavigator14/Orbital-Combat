class_name SquadronSpawnerPanel
extends PanelContainer
## UI panel for controlling squadron spawning
## Provides buttons to spawn squadrons and displays active squadron status

# === References ===
var _spawner: SquadronSpawner = null
var _squadron_list: VBoxContainer = null
var _status_label: Label = null
var _wave_label: Label = null

# === State ===
var auto_spawn_enabled: bool = false


func _ready() -> void:
	_setup_references()
	_setup_buttons()
	_update_display()


func _setup_references() -> void:
	# Find squadron list
	_squadron_list = $MarginContainer/VBoxContainer/SquadronList
	_status_label = $MarginContainer/VBoxContainer/StatusLabel
	_wave_label = $MarginContainer/VBoxContainer/WaveLabel
	
	# Try to find or create the spawner
	_spawner = _get_or_create_spawner()
	
	# Connect to spawner signals if available
	if _spawner:
		_spawner.squadron_spawned.connect(_on_squadron_spawned)
		_spawner.squadron_destroyed.connect(_on_squadron_destroyed)
		_spawner.wave_completed.connect(_on_wave_completed)


func _setup_buttons() -> void:
	# Connect spawn buttons
	var spawn_standard = $MarginContainer/VBoxContainer/SpawnButtons/SpawnStandard
	var spawn_heavy = $MarginContainer/VBoxContainer/SpawnButtons/SpawnHeavy
	var spawn_stealth = $MarginContainer/VBoxContainer/SpawnButtons/SpawnStealth
	var spawn_scout = $MarginContainer/VBoxContainer/SpawnButtons/SpawnScout
	
	spawn_standard.pressed.connect(_spawn_standard.bind())
	spawn_heavy.pressed.connect(_spawn_heavy.bind())
	spawn_stealth.pressed.connect(_spawn_stealth.bind())
	spawn_scout.pressed.connect(_spawn_scout.bind())
	
	# Wave buttons
	var spawn_wave = $MarginContainer/VBoxContainer/WaveButtons/SpawnWave
	var auto_wave = $MarginContainer/VBoxContainer/WaveButtons/AutoWave
	
	spawn_wave.pressed.connect(_spawn_wave.bind())
	auto_wave.toggled.connect(_toggle_auto_wave.bind())
	
	# Control buttons
	var clear_btn = $MarginContainer/VBoxContainer/ClearButton
	clear_btn.pressed.connect(_clear_all.bind())


func _get_or_create_spawner() -> SquadronSpawner:
	## Find or create the squadron spawner
	# Try to find existing spawner
	var main = get_node("/root/Main")
	if main and main.has_node("SquadronSpawner"):
		return main.get_node("SquadronSpawner")
	
	# Create new spawner if none exists
	var spawner = SquadronSpawner.new()
	spawner.name = "SquadronSpawner"
	spawner.default_squadron_size = 4
	spawner.max_squadrons = 3
	spawner.auto_spawn_waves = false
	
	# Add to main or self
	if main:
		main.add_child(spawner)
	else:
		add_child(spawner)
	
	print("SquadronSpawnerPanel: Created new spawner")
	return spawner


# === Spawn Methods ===

func _spawn_standard() -> void:
	if _spawner:
		var config = SquadronSpawnConfig.create_standard()
		var body = _get_nearest_celestial_body()
		_spawner.spawn_squadron(config, body)
	_update_display()


func _spawn_heavy() -> void:
	if _spawner:
		var config = SquadronSpawnConfig.create_heavy()
		var body = _get_nearest_celestial_body()
		_spawner.spawn_squadron(config, body)
	_update_display()


func _spawn_stealth() -> void:
	if _spawner:
		var config = SquadronSpawnConfig.create_stealth()
		var body = _get_nearest_celestial_body()
		_spawner.spawn_squadron(config, body)
	_update_display()


func _spawn_scout() -> void:
	if _spawner:
		var config = SquadronSpawnConfig.create_scout()
		var body = _get_nearest_celestial_body()
		_spawner.spawn_squadron(config, body)
	_update_display()


func _spawn_wave(count: int = 1) -> void:
	if _spawner:
		var body = _get_nearest_celestial_body()
		_spawner.spawn_wave(count, null, body)
	_update_display()


func _toggle_auto_wave(enabled: bool) -> void:
	if _spawner:
		_spawner.auto_spawn_waves = enabled
		auto_spawn_enabled = enabled
	_update_display()


func _clear_all() -> void:
	if _spawner:
		_spawner.remove_all_squadrons()
	_update_display()


# === Display Update ===

func _update_display() -> void:
	if not _spawner:
		_status_label.text = "Spawner: N/A"
		_wave_label.text = "Wave: -"
		return
	
	var status = _spawner.get_spawner_status()
	_status_label.text = "Active: %d / %d" % [status["active_squadrons"], status["max_squadrons"]]
	_wave_label.text = "Wave: %d" % _spawner.get_wave_number()
	
	# Update wave button text
	var spawn_wave_btn = $MarginContainer/VBoxContainer/WaveButtons/SpawnWave
	spawn_wave_btn.text = "Wave (%d)" % min(1 + _spawner.get_wave_number(), 5)
	
	# Update auto wave button
	var auto_wave_btn = $MarginContainer/VBoxContainer/WaveButtons/AutoWave
	auto_wave_btn.button_pressed = _spawner.auto_spawn_waves
	
	# Update squadron list
	_update_squadron_list()


func _update_squadron_list() -> void:
	# Clear existing entries
	for child in _squadron_list.get_children():
		child.queue_free()
	
	if not _spawner or _spawner.get_active_count() == 0:
		var no_squads = Label.new()
		no_squads.text = "(none)"
		no_squads.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		no_squads.add_theme_font_size_override("font_size", 10)
		_squadron_list.add_child(no_squads)
		return
	
	# Add entries for each squadron
	for i in range(_spawner.get_active_count()):
		var squadron = _spawner.get_squadron_at(i)
		if squadron:
			var entry = _create_squadron_entry(squadron)
			_squadron_list.add_child(entry)


func _create_squadron_entry(squadron: Squadron) -> HBoxContainer:
	var entry = HBoxContainer.new()
	
	# Squad name
	var name_label = Label.new()
	name_label.text = squadron.squad_name
	name_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(name_label)
	
	# Member count
	var count_label = Label.new()
	count_label.text = "[%d]" % squadron.get_member_count()
	count_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.7))
	count_label.add_theme_font_size_override("font_size", 10)
	entry.add_child(count_label)
	
	# State indicator
	var state_label = Label.new()
	state_label.text = squadron._get_state_name(squadron.squad_state)
	state_label.add_theme_color_override("font_color", _get_state_color(squadron.squad_state))
	state_label.add_theme_font_size_override("font_size", 10)
	entry.add_child(state_label)
	
	return entry


func _get_state_color(state: int) -> Color:
	match state:
		Squadron.SquadState.FORMING: return Color(0.5, 0.5, 0.5)
		Squadron.SquadState.PATROL: return Color(0.3, 0.7, 0.3)
		Squadron.SquadState.TRANSIT: return Color(0.7, 0.7, 0.3)
		Squadron.SquadState.HUNTING: return Color(0.9, 0.6, 0.2)
		Squadron.SquadState.ENGAGING: return Color(1.0, 0.3, 0.3)
		Squadron.SquadState.RETREATING: return Color(0.7, 0.3, 0.7)
		Squadron.SquadState.REORGANIZING: return Color(0.5, 0.5, 0.8)
	return Color(0.7, 0.7, 0.7)


func _get_nearest_celestial_body() -> CelestialBody:
	## Find the nearest celestial body for spawning
	var main = get_node("/root/Main")
	if not main:
		return null
	
	# Try to find player ship for relative positioning
	var player_ship = main.get("player_ship") if main else null
	
	# Find solar system and get Earth by default
	var solar_system = main.get("solar_system") if main else null
	if solar_system and solar_system.has_node("Earth"):
		return solar_system.get_node("Earth")
	
	# Fallback - return first planet found
	if solar_system:
		var planets = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]
		for planet_name in planets:
			if solar_system.has_node(planet_name):
				return solar_system.get_node(planet_name)
	
	return null


# === Signal Callbacks ===

func _on_squadron_spawned(squadron: Squadron) -> void:
	_update_display()


func _on_squadron_destroyed(squadron: Squadron) -> void:
	_update_display()


func _on_wave_completed(wave_number: int, remaining: int) -> void:
	_update_display()


# === Process ===

func _process(delta: float) -> void:
	# Refresh display periodically (every 0.5 seconds)
	pass  # Could add timer-based refresh if needed