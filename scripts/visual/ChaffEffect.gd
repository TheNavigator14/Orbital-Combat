class_name ChaffEffect
extends Node2D
## Visual chaff cloud effect for radar confusion countermeasures
## Creates a diffuse reflective cloud that confuses enemy radar

# === Chaff Configuration ===
@export var cloud_duration: float = 15.0  # seconds
@export var initial_particle_count: int = 50  # Number of particles spawned initially
@export var spread_radius: float = 50.0  # How far particles spread
@export var max_particles: int = 100

# === Visual Settings ===
@export var chaff_color: Color = Color(0.9, 0.9, 0.95, 0.6)  # Silver-white metallic
@export var glint_color: Color = Color(1.0, 1.0, 0.8, 0.8)  # Occasional glint
@export var fade_color: Color = Color(0.7, 0.7, 0.75, 0.2)  # Faded chaff

@export var particle_size: float = 2.0
@export var glint_interval: float = 0.3  # Seconds between glints

# === State ===
var particles: Array = []
var is_active: bool = true
var elapsed_time: float = 0.0
var next_glint_time: float = 0.0
var glinting_particle: int = -1

# === Chaff Particle Data Structure ===
class ChaffParticle:
	var position: Vector2
	var velocity: Vector2
	var lifetime: float
	var max_lifetime: float
	var size: float
	var base_color: Color
	var is_glinting: bool
	
	func _init(pos: Vector2, vel: Vector2, life: float, sz: float, col: Color) -> void:
		position = pos
		velocity = vel
		lifetime = life
		max_lifetime = life
		size = sz
		base_color = col
		is_glinting = false
	
	func get_color() -> Color:
		## Get current color with lifetime fade
		var ratio = lifetime / max_lifetime
		var col = base_color
		col.a = base_color.a * ratio
		if is_glinting:
			col = Color(1.0, 1.0, 0.8, col.a * 1.5)
		return col


func _ready() -> void:
	# Spawn initial particles
	_spawn_cloud(initial_particle_count)


func _process(delta: float) -> void:
	if not is_active:
		return
	
	elapsed_time += delta
	
	# Check if cloud has dissipated
	if elapsed_time >= cloud_duration:
		is_active = false
		queue_redraw()
		return
	
	# Update glinting
	next_glint_time += delta
	if next_glint_time >= glint_interval:
		_trigger_glint()
		next_glint_time = 0.0
	
	# Update particles
	var to_remove: Array = []
	for i in range(particles.size()):
		var p: ChaffParticle = particles[i]
		p.lifetime -= delta
		
		if p.lifetime <= 0:
			to_remove.append(i)
		else:
			# Gentle drift
			p.position += p.velocity * delta
			p.velocity *= 0.995  # Slow drag
			
			# Occasional random motion
			if randf() > 0.95:
				p.velocity += Vector2.from_angle(randf() * TAU) * 5.0
	
	# Remove dead particles
	for i in range(to_remove.size() - 1, -1, -1):
		particles.remove_at(to_remove[i])
	
	queue_redraw()


func _draw() -> void:
	if not is_active:
		return
	
	# Calculate fade based on remaining time
	var fade_ratio = 1.0 - (elapsed_time / cloud_duration)
	
	# Draw cloud boundary hint (subtle gradient)
	var boundary_alpha = 0.1 * fade_ratio
	draw_circle(Vector2.ZERO, spread_radius * 1.5, Color(0.8, 0.8, 0.85, boundary_alpha))
	
	# Draw all particles
	for p: ChaffParticle in particles:
		var col = p.get_color()
		col.a *= fade_ratio
		
		# Draw particle with slight glow when glinting
		if p.is_glinting:
			# Glint effect - brighter with glow
			draw_circle(p.position, particle_size * 2.5, Color(1.0, 1.0, 0.9, col.a * 0.5))
		
		# Core chaff strand
		draw_circle(p.position, particle_size, col)
		
		# Draw elongated strand effect
		var strand_dir = p.velocity.normalized()
		if strand_dir.length() > 0.1:
			var strand_end = p.position + strand_dir * particle_size * 2.0
			var strand_col = Color(col.r, col.g, col.b, col.a * 0.5)
			draw_line(p.position, strand_end, strand_col, 1.0)


func _spawn_cloud(count: int) -> void:
	## Spawn chaff particles in a cloud pattern
	for _i in range(count):
		_emit_single_particle()


func _emit_single_particle() -> void:
	# Random position within spread radius
	var angle = randf() * TAU
	var distance = randf() * spread_radius
	var position = Vector2.from_angle(angle) * distance
	
	# Slow drift - generally outward but random
	var drift_angle = angle + randf_range(-0.5, 0.5)
	var drift_speed = randf_range(5.0, 20.0)
	var velocity = Vector2.from_angle(drift_angle) * drift_speed
	
	# Randomize lifetime slightly
	var lifetime = cloud_duration * randf_range(0.7, 1.0)
	
	var particle = ChaffParticle.new(position, velocity, lifetime, particle_size, chaff_color)
	particles.append(particle)


func _trigger_glint() -> void:
	## Randomly make one particle glint
	if particles.size() == 0:
		return
	
	# Clear previous glint
	if glinting_particle >= 0 and glinting_particle < particles.size():
		particles[glinting_particle].is_glinting = false
	
	# Pick random particle to glint
	glinting_particle = randi() % particles.size()
	particles[glinting_particle].is_glinting = true
	
	# Schedule glint to end
	var glint_duration = glint_interval * randf_range(0.3, 0.8)
	await get_tree().create_timer(glint_duration).timeout
	if glinting_particle >= 0 and glinting_particle < particles.size():
		particles[glinting_particle].is_glinting = false


func spawn_cloud(cluster_size: int = 20) -> void:
	## Spawn or add to cloud
	# Spawn additional particles
	for _i in range(cluster_size):
		if particles.size() < max_particles:
			_emit_single_particle()


func is_active() -> bool:
	## Check if chaff cloud is still active
	return is_active


func get_radar_confusion_strength() -> float:
	## Returns how much radar confusion this cloud provides (1.0 = maximum)
	var particle_ratio = float(particles.size()) / float(max_particles)
	var time_ratio = 1.0 - (elapsed_time / cloud_duration)
	return particle_ratio * time_ratio


func get_particle_count() -> int:
	## Get current number of active particles
	return particles.size()


func dissipate() -> void:
	## Quickly dissipate the cloud (emergency deployment)
	elapsed_time = cloud_duration
	is_active = false