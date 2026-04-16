class_name ThrustParticleEffect
extends Node2D
## Visual thrust particle effect for ships - creates engine exhaust visualization

# === Particle Configuration ===
@export var particle_lifetime: float = 0.8  # seconds
@export var emission_rate: float = 60.0  # particles per second
@export var max_particles: int = 120
@export var particle_speed: float = 80.0  # pixels per second
@export var spread_angle: float = 0.3  # radians

# === Visual Settings ===
@export var particle_color_hot: Color = Color(1.0, 0.8, 0.3, 0.9)  # Bright exhaust
@export var particle_color_warm: Color = Color(1.0, 0.4, 0.1, 0.6)  # Cooling exhaust
@export var particle_color_cold: Color = Color(0.3, 0.3, 0.3, 0.3)  # Fading exhaust
@export var particle_size_hot: float = 6.0
@export var particle_size_cold: float = 2.0

# === State ===
var particles: Array = []
var emission_accumulator: float = 0.0
var is_emitting: bool = false
var thrust_direction: Vector2 = Vector2.DOWN  # Default exhaust direction
var parent_ship: Ship = null

# === Particle Data Structure ===
class Particle:
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_lifetime: float
	var size: float
	var color: Color
	
	func _init(pos: Vector2, vel: Vector2, life: float, sz: float, col: Color) -> void:
		position = pos
		velocity = vel
		lifetime = life
		max_lifetime = life
		size = sz
		color = col


func _ready() -> void:
	# Find parent ship if available
	_find_parent_ship()


func _find_parent_ship() -> void:
	var parent = get_parent()
	if parent is Ship:
		parent_ship = parent


func _process(delta: float) -> void:
	# Update emission
	if is_emitting:
		emission_accumulator += emission_rate * delta
		while emission_accumulator >= 1.0 and particles.size() < max_particles:
			_emit_particle()
			emission_accumulator -= 1.0
	
	# Update existing particles
	var particles_to_remove: Array = []
	for i in range(particles.size()):
		var p: Particle = particles[i]
		p.lifetime -= delta
		if p.lifetime <= 0:
			particles_to_remove.append(i)
		else:
			p.position += p.velocity * delta
			p.velocity *= 0.98  # Drag
			# Color fades with lifetime
			var life_ratio = p.lifetime / p.max_lifetime
			if life_ratio > 0.6:
				p.color = particle_color_hot
				p.size = particle_size_hot
			elif life_ratio > 0.3:
				p.color = particle_color_warm
				p.size = lerp(particle_size_hot, particle_size_cold, 1.0 - life_ratio / 0.3)
			else:
				p.color = particle_color_cold
				p.size = particle_size_cold
	
	# Remove dead particles (reverse order)
	for i in range(particles_to_remove.size() - 1, -1, -1):
		particles.remove_at(particles_to_remove[i])
	
	queue_redraw()


func _draw() -> void:
	# Draw all particles
	for p: Particle in particles:
		# Draw particle as circle with glow
		var draw_color = p.color
		draw_color.a *= 0.5
		draw_circle(p.position, p.size * 1.5, draw_color)  # Glow
		draw_circle(p.position, p.size, p.color)


func _emit_particle() -> void:
	# Random spread around thrust direction
	var angle_offset = randf_range(-spread_angle, spread_angle)
	var direction = thrust_direction.rotated(angle_offset)
	var velocity = direction * particle_speed * randf_range(0.8, 1.2)
	
	var particle_pos = Vector2.ZERO
	var new_particle = Particle.new(particle_pos, velocity, particle_lifetime, particle_size_hot, particle_color_hot)
	particles.append(new_particle)


func start_emission(dir: Vector2 = Vector2.DOWN) -> void:
	## Start emitting thrust particles
	is_emitting = true
	thrust_direction = dir


func stop_emission() -> void:
	## Stop emitting particles (existing ones will fade out)
	is_emitting = false


func set_direction(dir: Vector2) -> void:
	## Update thrust direction
	thrust_direction = dir.normalized()


func clear_particles() -> void:
	## Immediately clear all particles
	particles.clear()
	queue_redraw()


func set_throttle(throttle: float) -> void:
	## Set emission rate based on throttle (0-1)
	var was_emitting = is_emitting
	if throttle > 0.05:
		is_emitting = true
		emission_rate = 40.0 + throttle * 80.0  # 40-120 particles/sec
	else:
		is_emitting = false