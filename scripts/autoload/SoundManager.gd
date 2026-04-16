class_name SoundManager
extends Node
## Central sound system for Orbital Combat
## Manages all audio playback with CRT-era audio aesthetic

# === Sound Categories ===
enum Category {
	UI,           # Interface sounds (clicks, beeps, confirmations)
	THRUST,       # Engine thrust sounds
	COMBAT,       # Weapon and explosion sounds  
	ALERT,        # Warning and alert tones
	SENSOR,       # Radar and sensor pings
	AMBIENT       # Background hum and atmosphere
}

# === Sound Effect Definitions ===
const SOUNDS: Dictionary = {
	# UI Sounds
	"ui_click": {"freq": 800.0, "category": Category.UI, "volume": -10.0, "duration": 0.03, "wave": 0},
	"ui_confirm": {"freq": 1200.0, "category": Category.UI, "volume": -8.0, "duration": 0.1, "wave": 0},
	"ui_cancel": {"freq": 400.0, "category": Category.UI, "volume": -12.0, "duration": 0.08, "wave": 1},
	"ui_beep": {"freq": 2000.0, "category": Category.UI, "volume": -15.0, "duration": 0.05, "wave": 0},
	"ui_alarm": {"freq": 1800.0, "category": Category.UI, "volume": -5.0, "duration": 0.15, "wave": 1},
	
	# Thrust Sounds
	"thrust_main": {"freq": 80.0, "category": Category.THRUST, "volume": -6.0, "duration": 0.2, "wave": 3},
	"thrust_maneuver": {"freq": 120.0, "category": Category.THRUST, "volume": -10.0, "duration": 0.15, "wave": 3},
	"thrust_rcs": {"freq": 200.0, "category": Category.THRUST, "volume": -18.0, "duration": 0.05, "wave": 0},
	
	# Combat Sounds
	"weapon_fire": {"freq": 150.0, "category": Category.COMBAT, "volume": -4.0, "duration": 0.1, "wave": 2},
	"missile_launch": {"freq": 100.0, "category": Category.COMBAT, "volume": -6.0, "duration": 0.3, "wave": 3},
	"missile_track": {"freq": 600.0, "category": Category.COMBAT, "volume": -12.0, "duration": 0.5, "wave": 0},
	"pdc_fire": {"freq": 2000.0, "category": Category.COMBAT, "volume": -8.0, "duration": 0.05, "wave": 1},
	"explosion_small": {"freq": 60.0, "category": Category.COMBAT, "volume": -5.0, "duration": 0.4, "wave": 3},
	"explosion_large": {"freq": 40.0, "category": Category.COMBAT, "volume": -2.0, "duration": 0.8, "wave": 3},
	"hit_armor": {"freq": 300.0, "category": Category.COMBAT, "volume": -10.0, "duration": 0.1, "wave": 2},
	"hit_critical": {"freq": 500.0, "category": Category.COMBAT, "volume": -6.0, "duration": 0.15, "wave": 1},
	
	# Alert Sounds
	"alert_contact": {"freq": 880.0, "category": Category.ALERT, "volume": -8.0, "duration": 0.2, "wave": 0},
	"alert_lock": {"freq": 1200.0, "category": Category.ALERT, "volume": -6.0, "duration": 0.3, "wave": 0},
	"alert_missile": {"freq": 1600.0, "category": Category.ALERT, "volume": -4.0, "duration": 0.5, "wave": 1},
	"alert_damage": {"freq": 440.0, "category": Category.ALERT, "volume": -5.0, "duration": 0.25, "wave": 2},
	"alert_critical": {"freq": 2000.0, "category": Category.ALERT, "volume": -3.0, "duration": 0.4, "wave": 1},
	
	# Sensor Sounds
	"sensor_ping": {"freq": 3000.0, "category": Category.SENSOR, "volume": -14.0, "duration": 0.1, "wave": 0},
	"sensor_sweep": {"freq": 1500.0, "category": Category.SENSOR, "volume": -16.0, "duration": 0.8, "wave": 0},
	"sensor_lock": {"freq": 2400.0, "category": Category.SENSOR, "volume": -10.0, "duration": 0.2, "wave": 0},
	"sensor_scan": {"freq": 1800.0, "category": Category.SENSOR, "volume": -12.0, "duration": 0.3, "wave": 0},
}

# === State ===
var _is_muted: bool = false
var _master_volume: float = 1.0
var _sfx_volume: float = 1.0
var _ui_volume: float = 1.0
var _ambient_volume: float = 0.8

# === Active Players ===
var _active_players: Array = []


func _ready() -> void:
	_setup_audio_buses()
	print("SoundManager: Initialized with procedural audio")


func _setup_audio_buses() -> void:
	## Ensure audio buses exist
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus == -1:
		AudioServer.add_bus_layout_item("SFX")
	
	var ui_bus = AudioServer.get_bus_index("UI")
	if ui_bus == -1:
		AudioServer.add_bus_layout_item("UI")
	
	var ambient_bus = AudioServer.get_bus_index("Ambient")
	if ambient_bus == -1:
		AudioServer.add_bus_layout_item("Ambient")


# === Public API ===

func play(sound_name: String, volume_mod: float = 0.0) -> void:
	## Play a sound effect by name
	if _is_muted:
		return
	
	if not SOUNDS.has(sound_name):
		push_warning("SoundManager: Unknown sound: ", sound_name)
		return
	
	var data = SOUNDS[sound_name]
	var freq = data.freq * (1.0 + randf_range(-0.05, 0.05))  # Slight pitch variation
	var volume = data.volume + volume_mod + _get_volume_for_category(data.category)
	
	_play_tone(freq, data.duration, data.wave, volume)


func play_ui(sound_name: String) -> void:
	## Play UI sound with UI volume modifier
	if _is_muted:
		return
	
	if not SOUNDS.has(sound_name):
		return
	
	var data = SOUNDS[sound_name]
	_play_tone(data.freq, data.duration, data.wave, data.volume)


func play_alert(alert_type: String) -> void:
	## Play alert sound with appropriate urgency
	match alert_type:
		"contact": play("alert_contact")
		"lock": play("alert_lock")
		"missile": play("alert_missile")
		"damage": play("alert_damage")
		"critical": play("alert_critical")


func play_weapon_fire(type: String) -> void:
	## Play weapon fire sound based on weapon type
	match type:
		"missile": play("missile_launch")
		"pdc": play("pdc_fire")
		_: play("weapon_fire")


func play_explosion(size: String) -> void:
	## Play appropriate explosion sound
	match size:
		"small": play("explosion_small")
		"large": play("explosion_large")
		_: play("explosion_small")


func play_sensor(mode: String) -> void:
	## Play sensor-related sound
	match mode:
		"ping": play("sensor_ping")
		"sweep": play("sensor_sweep")
		"lock": play("sensor_lock")
		"scan": play("sensor_scan")


func play_thrust(intensity: float = 1.0) -> void:
	## Play thrust sound with intensity (0-1)
	if _is_muted:
		return
	
	var freq = 60.0 + intensity * 40.0
	var volume = -8.0 + (1.0 - intensity) * 4.0
	_play_tone(freq, 0.1, 3, volume)


# === Volume Control ===

func set_master_volume(volume: float) -> void:
	_master_volume = clamp(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(_master_volume))


func set_sfx_volume(volume: float) -> void:
	_sfx_volume = clamp(volume, 0.0, 1.0)


func set_ui_volume(volume: float) -> void:
	_ui_volume = clamp(volume, 0.0, 1.0)


func mute() -> void:
	_is_muted = true


func unmute() -> void:
	_is_muted = false


func toggle_mute() -> bool:
	_is_muted = not _is_muted
	return _is_muted


func get_master_volume() -> float:
	return _master_volume


func is_muted() -> bool:
	return _is_muted


func get_sound_names() -> Array:
	return SOUNDS.keys()


# === Internal ===

func _get_volume_for_category(category: Category) -> float:
	match category:
		Category.UI: return linear_to_db(_ui_volume)
		Category.AMBIENT: return linear_to_db(_ambient_volume)
		_: return linear_to_db(_sfx_volume)


func _play_tone(frequency: float, duration: float, waveform: int, volume_db: float) -> void:
	## Play a procedurally generated tone
	# Create a temporary player
	var player = AudioStreamPlayer.new()
	add_child(player)
	_active_players.append(player)
	
	# Generate audio data
	var audio_data = _generate_tone_audio(frequency, duration, waveform)
	player.stream = audio_data
	player.volume_db = volume_db
	
	# Connect for cleanup
	player.finished.connect(_on_player_finished.bind(player))
	
	player.play()


func _on_player_finished(player: AudioStreamPlayer) -> void:
	_active_players.erase(player)
	player.queue_free()


func _generate_tone_audio(frequency: float, duration: float, waveform: int) -> AudioStreamWAV:
	## Generate a WAV tone with the given parameters
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	
	var stream = AudioStreamWAV.new()
	stream.mix_rate = float(sample_rate)
	stream.stereo = false
	
	var data = PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit samples
	
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample: float
		
		# Envelope
		var envelope = 1.0
		var attack = 0.005
		var decay_start = duration * 0.2
		
		if t < attack:
			envelope = t / attack
		elif t > decay_start:
			envelope = 1.0 - ((t - decay_start) / (duration - decay_start))
		
		envelope = clamp(envelope, 0.0, 1.0)
		
		# Waveform
		var phase = 2.0 * PI * frequency * t
		match waveform:
			0:  # Sine
				sample = sin(phase)
			1:  # Square
				sample = 1.0 if sin(phase) > 0 else -1.0
			2:  # Saw
				sample = 2.0 * fmod(phase / (2.0 * PI), 1.0) - 1.0
			3:  # Triangle
				sample = 2.0 * abs(2.0 * fmod(phase / (2.0 * PI), 1.0) - 1.0) - 1.0
			_:
				sample = sin(phase)
		
		# Add slight noise
		sample += randf_range(-0.01, 0.01)
		
		# Apply envelope
		sample *= envelope * 0.3
		sample = clamp(sample, -0.99, 0.99)
		
		# Convert to 16-bit integer
		var sample_int = int(sample * 32767)
		data[i * 2] = sample_int & 0xFF
		data[i * 2 + 1] = (sample_int >> 8) & 0xFF
	
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16BIT
	
	return stream


func stop_all_sounds() -> void:
	## Stop all playing sounds
	for player in _active_players:
		if is_instance_valid(player):
			player.stop()
	_active_players.clear()