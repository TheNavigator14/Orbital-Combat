class_name CRTOverlay
extends CanvasLayer

## Full CRT Overlay Effect for cockpit aesthetic
## Part of Phase 5: Polish - Visual effects

# === Configuration ===
@export var enable_scanlines: bool = true
@export var enable_vignette: bool = true
@export var enable_phosphor_glow: bool = true
@export var enable_screen_noise: bool = true
@export var enable_rolling_interference: bool = false

# Visual effect intensities
@export var scanline_intensity: float = 0.15
@export var vignette_intensity: float = 0.4
@export var glow_intensity: float = 0.08
@export var noise_intensity: float = 0.03

# Flicker effect
@export var enable_flicker: bool = true
@export var flicker_frequency: float = 0.3  # Hz

# Color shift (slight RGB separation)
@export var enable_color_fringing: bool = true
@export var color_fringe_amount: float = 1.5

# Quality settings
enum QualityMode { LOW, MEDIUM, HIGH }
@export var quality_mode: QualityMode = QualityMode.HIGH

# Reference to player ship for status effects
var target_ship: Ship = null

# Shader materials
var scanline_material: ShaderMaterial
var vignette_material: ShaderMaterial
var glow_material: ShaderMaterial
var noise_material: ShaderMaterial

# Effect panels
var scanline_panel: ColorRect
var vignette_panel: ColorRect
var glow_panel: ColorRect
var noise_panel: ColorRect
var interference_panel: ColorRect

# Timers for random effects
var interference_timer: float = 0.0
var interference_duration: float = 0.0
var interference_intensity: float = 0.0
var _time: float = 0.0
var _noise_update_timer: float = 0.0
var _flicker_value: float = 1.0

# === CRT Colors ===
const CRT_GREEN := Color(0.0, 0.9, 0.4, 1.0)
const CRT_AMBER := Color(1.0, 0.6, 0.1, 1.0)
const CRT_PHOSPHOR := Color(0.0, 0.85, 0.35, 0.25)

func _ready() -> void:
	_setup_crt_effects()
	process_priority = 100

func _process(delta: float) -> void:
	_time += delta
	_noise_update_timer += delta
	
	# Update noise texture periodically
	if _noise_update_timer > 0.1 and enable_screen_noise:
		_noise_update_timer = 0.0
	
	# Flicker effect
	if enable_flicker:
		_update_flicker(delta)
	
	# Rolling interference
	if enable_rolling_interference:
		_update_interference(delta)

func _setup_crt_effects() -> void:
	# Create effect layers
	_create_scanlines_layer()
	_create_vignette_layer()
	_create_glow_layer()
	_create_noise_layer()
	_create_interference_layer()
	
	# Apply quality settings
	_apply_quality_mode()

func _create_scanlines_layer() -> void:
	## Create animated scanline effect
	scanline_panel = ColorRect.new()
	scanline_panel.name = "Scanlines"
	scanline_panel.anchors_preset = Control.PRESET_FULL_RECT
	scanline_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scanline_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# Use shader for animated scanlines
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 0.5) = 0.15;
uniform float line_count : hint_range(100.0, 1000.0) = 480.0;
uniform float time : hint_range(0.0, 10.0) = 0.0;

void fragment() {
	float y = UV.y * line_count;
	float line = mod(floor(y + time * 0.5), 2.0);
	float alpha = mix(intensity * 0.5, intensity, line);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
"""
	
	scanline_material = ShaderMaterial.new()
	scanline_material.shader = shader
	scanline_material.set_shader_parameter("intensity", scanline_intensity)
	scanline_material.set_shader_parameter("line_count", _get_quality_line_count())
	scanline_material.set_shader_parameter("time", 0.0)
	
	scanline_panel.material = scanline_material
	add_child(scanline_panel)
	
	if not enable_scanlines:
		scanline_panel.visible = false

func _create_vignette_layer() -> void:
	## Create vignette darkening effect
	vignette_panel = ColorRect.new()
	vignette_panel.name = "Vignette"
	vignette_panel.anchors_preset = Control.PRESET_FULL_RECT
	vignette_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vignette_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	// Smooth vignette falloff
	float vignette = smoothstep(0.8, 0.2, dist);
	vignette = pow(vignette, 1.5);
	COLOR = vec4(0.0, 0.0, 0.0, vignette * intensity);
}
"""
	
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = shader
	vignette_material.set_shader_parameter("intensity", vignette_intensity)
	
	vignette_panel.material = vignette_material
	add_child(vignette_panel)
	
	if not enable_vignette:
		vignette_panel.visible = false

func _create_glow_layer() -> void:
	## Create phosphor screen glow
	glow_panel = ColorRect.new()
	glow_panel.name = "PhosphorGlow"
	glow_panel.anchors_preset = Control.PRESET_FULL_RECT
	glow_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	glow_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	glow_panel.color = CRT_PHOSPHOR
	add_child(glow_panel)
	
	if not enable_phosphor_glow:
		glow_panel.visible = false

func _create_noise_layer() -> void:
	## Create animated screen noise
	noise_panel = ColorRect.new()
	noise_panel.name = "ScreenNoise"
	noise_panel.anchors_preset = Control.PRESET_FULL_RECT
	noise_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	glow_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 0.2) = 0.03;
uniform float time : hint_range(0.0, 100.0) = 0.0;

// Pseudo-random hash
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV * 100.0;
	float noise = hash(vec2(uv.x + time * 10.0, uv.y));
	float alpha = noise * intensity;
	COLOR = vec4(noise, noise, noise, alpha);
}
"""
	
	noise_material = ShaderMaterial.new()
	noise_material.shader = shader
	noise_material.set_shader_parameter("intensity", noise_intensity)
	noise_material.set_shader_parameter("time", 0.0)
	
	noise_panel.material = noise_material
	add_child(noise_panel)
	
	if not enable_screen_noise:
		noise_panel.visible = false

func _create_interference_layer() -> void:
	## Create rolling interference burst effect
	interference_panel = ColorRect.new()
	interference_panel.name = "Interference"
	interference_panel.anchors_preset = Control.PRESET_FULL_RECT
	interference_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	interference_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	interference_panel.visible = false
	
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.3;
uniform float time : hint_range(0.0, 10.0) = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	float y_pos = UV.y + time * 0.1;
	float interference = hash(floor(y_pos * 50.0) + time) * intensity;
	// Horizontal bar pattern
	float bar = step(0.7, fract(y_pos * 30.0));
	COLOR = vec4(1.0, 1.0, 1.0, interference * (0.3 + bar * 0.7));
}
"""
	
	var interference_material := ShaderMaterial.new()
	interference_material.shader = shader
	interference_material.set_shader_parameter("intensity", 0.0)
	interference_material.set_shader_parameter("time", 0.0)
	
	interference_panel.material = interference_material
	add_child(interference_panel)

func _update_flicker(delta: float) -> void:
	## Subtle CRT flicker
	_flicker_value = 1.0
	
	if enable_flicker:
		# Base sine flicker
		var sine_flicker := sin(_time * 10.0) * 0.02
		
		# Random additional flicker
		if randf() > 0.95:
			sine_flicker += randf_range(-0.05, 0.08)
		
		_flicker_value = 1.0 + sine_flicker
	
	# Apply to glow
	if glow_panel:
		glow_panel.modulate.a = glow_intensity * _flicker_value

func _update_interference(delta: float) -> void:
	## Rolling interference burst
	interference_timer += delta
	
	if interference_timer >= interference_duration and randf() > 0.97:
		# Trigger new interference burst
		interference_duration = randf_range(0.2, 0.8)
		interference_intensity = randf_range(0.1, 0.4)
		interference_timer = 0.0
		interference_panel.visible = true
		
		if interference_material:
			interference_material.set_shader_parameter("intensity", interference_intensity)
	
	if interference_panel.visible:
		if interference_material:
			interference_material.set_shader_parameter("time", _time)
		
		if interference_timer >= interference_duration:
			interference_panel.visible = false

func _get_quality_line_count() -> float:
	match quality_mode:
		QualityMode.LOW:
			return 240.0
		QualityMode.MEDIUM:
			return 480.0
		QualityMode.HIGH:
			return 720.0
	return 480.0

func _apply_quality_mode() -> void:
	match quality_mode:
		QualityMode.LOW:
			noise_material.set_shader_parameter("intensity", noise_intensity * 0.5) if noise_material else ""
			enable_flicker = false
		QualityMode.MEDIUM:
			pass  # Default settings
		QualityMode.HIGH:
			pass  # Full settings
	
	if scanline_material:
		scanline_material.set_shader_parameter("line_count", _get_quality_line_count())

# === Public API ===

func set_scanlines(enabled: bool) -> void:
	enable_scanlines = enabled
	if scanline_panel:
		scanline_panel.visible = enabled

func set_vignette(enabled: bool) -> void:
	enable_vignette = enabled
	if vignette_panel:
		vignette_panel.visible = enabled

func set_glow(enabled: bool) -> void:
	enable_phosphor_glow = enabled
	if glow_panel:
		glow_panel.visible = enabled

func set_noise(enabled: bool) -> void:
	enable_screen_noise = enabled
	if noise_panel:
		noise_panel.visible = enabled

func set_all_effects(enabled: bool) -> void:
	enable_scanlines = enabled
	enable_vignette = enabled
	enable_phosphor_glow = enabled
	enable_screen_noise = enabled
	set_scanlines(enabled)
	set_vignette(enabled)
	set_glow(enabled)
	set_noise(enabled)

func set_color_mode(is_amber: bool) -> void:
	## Switch between green and amber phosphor modes
	if glow_panel:
		if is_amber:
			glow_panel.color = Color(0.95, 0.55, 0.1, 0.2)
		else:
			glow_panel.color = CRT_PHOSPHOR

func set_quality(mode: int) -> void:
	quality_mode = mode as QualityMode
	_apply_quality_mode()

func get_flicker_intensity() -> float:
	return _flicker_value

# === Status Effects ===

func connect_to_ship(ship: Ship) -> void:
	target_ship = ship
	if ship and ship.has_signal("damaged"):
		ship.damaged.connect(_on_ship_damaged)

func _on_ship_damaged(damage: float) -> void:
	## Increase visual disturbance when ship takes damage
	if noise_material:
		var damage_noise := noise_intensity + (damage * 0.02)
		noise_material.set_shader_parameter("intensity", min(damage_noise, 0.3))
		
		# Reset after delay
		await get_tree().create_timer(0.5).timeout
		noise_material.set_shader_parameter("intensity", noise_intensity)

func trigger_death_effect() -> void:
	## Red flash on ship destruction
	if glow_panel:
		var original_color := glow_panel.color
		glow_panel.color = Color(1.0, 0.2, 0.2, 0.8)
		
		await get_tree().create_timer(0.3).timeout
		
		# Fade out
		var tween := create_tween()
		tween.tween_property(glow_panel, "modulate:a", 0.0, 1.0)
		await tween.finished
		
		glow_panel.color = original_color