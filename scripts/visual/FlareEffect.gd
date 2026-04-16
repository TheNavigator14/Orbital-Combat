class_name FlareEffect
extends Node2D
## Visual flare effect for heat-seeking missile countermeasures
## Creates an IR decoy that distracts heat-seeking missiles

# === Flare Configuration ===
@export var burn_duration: float = 8.0  # seconds
@export var particle_emission_rate: float = 30.0  # particles per second
@export var max_particles: int = 240
@export var particle_lifetime: float = 1.5  # seconds

# === Visual Settings ===
@export var hot_color: Color = Color(1.0, 0.8, 0.3, 0.9)  # Bright orange-yellow
@export var warm_color: Color = Color(1.0, 0.5, 0.1, 0.7)  # Orange
@export var fading_color: Color = Color(0.8, 0.2, 0.1, 0.4)  # Red fading
@export var smoke_color: Color = Color(0.3, 0.3, 0.3, 0.2)  # Smoke

@export var particle_size_hot: float = 8.0
@export var particle_size_cold: float = 3.0

# === State ===
var particles: Array = []
var emission_accumulator: float = 0.0
var is_active: bool = true
var elapsed_time: float = 0.0
var drift_direction: Vector2 = Vector2.UP
var lifetime_ratio: float = 1.0  # 1.0 = fresh, 0.0 = nearly expired

# === Particle Data Structure ===
class FlareParticle:
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_lifetime: float
	var size: float
	var color: Color
	var type: int  # 0 = flame, 1 = smoke
	
	func _init(pos: Vector2, vel: Vector2, life: float, sz: float, col: Color, t: int = 0) -> void:
		position = pos
		velocity = vel
		lifetime = life
		max_lifetime = life
		size = sz
		color = col
		type = t


func _ready() -> void:
	# Start emitting immediately
	pass


func _process(delta: float) -> void:
	if not is_active:
		return
	
	elapsed_time += delta
	lifetime_ratio = 1.0 - (elapsed_time / burn_duration)
	
	# Check if burn is complete
	if elapsed_time >= burn_duration:
		is_active = false
		queue_redraw()
		return
	
	# Update emission rate based on remaining lifetime
	var emission_modifier = lifetime_ratio  # Full rate when fresh
	
	# Emit new particles
	emission_accumulator += emission_rate * delta * emission_modifier
	while emission_accumulator >= 1.0 and particles.size() < max_particles:
		_emit_particle()
		emission_accumulator -= 1.0
	
	# Update existing particles
	var to_remove: Array = []
	for i in range(particles.size()):
		var p: FlareParticle = particles[i]
		p.lifetime -= delta
		
		if p.lifetime <= 0:
			to_remove.append(i)
		else:
			# Move particle
			p.position += p.velocity * delta
			
			# Add drift
			p.velocity += drift_direction * 10.0 * delta
			p.velocity *= 0.98  # Drag
			
			# Update color based on lifetime
			var life_ratio = p.lifetime / p.max_lifetime
			if p.type == 0:  # Flame particle
				if life_ratio > 0.7:
					p.color = hot_color
					p.size = particle_size_hot
				elif life_ratio > 0.4:
					p.color = warm_color
					p.size = lerp(particle_size_hot, particle_size_cold, (0.4 - life_ratio) / 0.4)
				elif life_ratio > 0.1:
					p.color = fading_color
					p.size = particle_size_cold
				else:
					p.color = smoke_color
					p.size = particle_size_cold * 0.5
					p.type = 1  # Convert to smoke
			else:  # Smoke particle
				p.color.a *= 0.95  # Fade out
				p.size *= 1.01  # Expand slightly
	
	# Remove dead particles
	for i in range(to_remove.size() - 1, -1, -1):
		particles.remove_at(to_remove[i])
	
	queue_redraw()


func _draw() -> void:
	if not is_active:
		return
	
	# Draw initial bright core
	var core_alpha = lifetime_ratio * 0.8
	var core_size = 15.0 * lifetime_ratio + 5.0
	draw_circle(Vector2.ZERO, core_size, Color(1.0, 0.9, 0.5, core_alpha))
	
	# Draw glow
	draw_circle(Vector2.ZERO, core_size * 2.0, Color(1.0, 0.6, 0.2, core_alpha * 0.3))
	
	# Draw particles
	for p: FlareParticle in particles:
		var draw_color = p.color
		if p.type == 1:  # Smoke has different draw
			draw_color.a *= 0.3
			draw_circle(p.position, p.size * 1.5, draw_color)
		else:
			# Flame glow
			draw_color.a *= 0.4
			draw_circle(p.position, p.size * 1.8, draw_color)
		# Core
		draw_circle(p.position, p.size, p.color)


func _emit_particle() -> void:
	# Determine particle type
	var is_smoke = randf() > (0.7 + lifetime_ratio * 0.2)  # More smoke as it ages
	var p_type = 1 if is_smoke else 0
	
	# Random offset from center
	var offset = Vector2.from_angle(randf() * TAU) * randf() * 8.0
	
	# Velocity - generally upward but with spread
	var angle = -PI/2  # Upward
	angle += randf_range(-0.5, 0.5)  # Spread
	var speed = randf_range(30.0, 80.0)
	var velocity = Vector2.from_angle(angle) * speed
	
	# Lifetime varies
	var lifetime = particle_lifetime * randf_range(0.5, 1.0)
	
	var particle = FlareParticle.new(offset, velocity, lifetime, particle_size_hot if p_type == 0 else particle_size_cold, hot_color if p_type == 0 else smoke_color, p_type)
	particles.append(particle)


func launch(direction: Vector2 = Vector2.UP) -> void:
	## Launch the flare (starts burn)
	drift_direction = direction.normalized()
	is_active = true
	elapsed_time = 0.0
	lifetime_ratio = 1.0


func is_active() -> bool:
	## Check if flare is still burning
	return is_active


func get_thermal_signature() -> float:
	## Returns thermal signature strength (1.0 = maximum)
	return lifetime_ratio


func set_brightness(brightness: float) -> void:
	## Adjust flare brightness (0.0-1.0)
	# This affects particle emission rate
	emission_rate = particle_emission_rate * brightness