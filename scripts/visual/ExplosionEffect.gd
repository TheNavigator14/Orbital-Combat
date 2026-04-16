class_name ExplosionEffect
extends Node2D
## Visual explosion effect for ship/missile destruction

# === Explosion Configuration ===
@export var explosion_radius: float = 80.0  # Visual size in pixels
@export var duration: float = 1.5  # Total duration in seconds
@export var particle_count: int = 40

# === Visual Settings ===
@export var core_color: Color = Color(1.0, 0.9, 0.7, 1.0)  # Bright white-yellow
@export var hot_color: Color = Color(1.0, 0.5, 0.1, 0.9)  # Orange
@export var warm_color: Color = Color(1.0, 0.2, 0.1, 0.7)  # Red
@export var cool_color: Color = Color(0.3, 0.3, 0.3, 0.4)  # Smoke gray

# === State ===
var particles: Array = []
var shockwave_radius: float = 0.0
var elapsed_time: float = 0.0
var is_active: bool = true

class ExplosionParticle:
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
	# Spawn initial explosion particles
	_spawn_explosion()


func _process(delta: float) -> void:
	if not is_active:
		return
	
	elapsed_time += delta
	
	# Update particles
	var to_remove: Array = []
	for i in range(particles.size()):
		var p: ExplosionParticle = particles[i]
		p.lifetime -= delta
		if p.lifetime <= 0:
			to_remove.append(i)
		else:
			p.position += p.velocity * delta
			p.velocity *= 0.95  # Drag
			# Color transitions
			var ratio = p.lifetime / p.max_lifetime
			if ratio > 0.7:
				p.color = core_color
				p.size = lerp(p.size, 12.0, 0.1)
			elif ratio > 0.4:
				p.color = hot_color
				p.size = lerp(p.size, 8.0, 0.05)
			elif ratio > 0.15:
				p.color = warm_color
				p.size = lerp(p.size, 4.0, 0.03)
			else:
				p.color = cool_color
				p.size = lerp(p.size, 2.0, 0.02)
	
	# Update shockwave
	shockwave_radius = explosion_radius * (elapsed_time / duration) * 1.5
	
	# Remove dead particles
	for i in range(to_remove.size() - 1, -1, -1):
		particles.remove_at(to_remove[i])
	
	# Check if explosion is complete
	if elapsed_time >= duration and particles.size() == 0:
		is_active = false
		queue_redraw()
		return
	
	queue_redraw()


func _draw() -> void:
	if not is_active:
		return
	
	# Draw shockwave ring
	if elapsed_time < duration * 0.5:
		var alpha = 0.6 * (1.0 - elapsed_time / (duration * 0.5))
		var shock_color = Color(1.0, 0.6, 0.3, alpha)
		var width = 4.0 * (1.0 - elapsed_time / (duration * 0.5))
		draw_arc(Vector2.ZERO, shockwave_radius, 0, TAU, 32, shock_color, width)
	
	# Draw explosion particles
	for p: ExplosionParticle in particles:
		# Outer glow
		var glow_color = p.color
		glow_color.a *= 0.3
		draw_circle(p.position, p.size * 2.0, glow_color)
		# Core
		draw_circle(p.position, p.size, p.color)
	
	# Draw initial flash
	if elapsed_time < 0.1:
		var flash_alpha = 1.0 - elapsed_time / 0.1
		var flash_color = Color(1.0, 1.0, 0.8, flash_alpha)
		draw_circle(Vector2.ZERO, explosion_radius * 0.3 * flash_alpha, flash_color)


func _spawn_explosion() -> void:
	# Spawn explosion particles in all directions
	for _i in range(particle_count):
		var angle = randf() * TAU
		var speed = randf_range(30.0, explosion_radius / duration * 2.0)
		var velocity = Vector2.from_angle(angle) * speed
		
		var lifetime = duration * randf_range(0.5, 1.0)
		var size = randf_range(4.0, 12.0)
		
		# Random offset from center
		var offset = Vector2.from_angle(randf() * TAU) * randf() * 20.0
		
		var particle = ExplosionParticle.new(offset, velocity, lifetime, size, core_color)
		particles.append(particle)


func set_explosion_size(size: float) -> void:
	## Scale explosion by size modifier
	explosion_radius *= size
	particle_count = int(particle_count * size)


func is_complete() -> bool:
	## Check if explosion animation is done
	return not is_active