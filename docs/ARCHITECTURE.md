# Orbital Combat - Technical Architecture

## Project Structure

```
Obital Combat/
├── project.godot              # Godot 4.5 project config
├── icon.svg                   # Project icon
│
├── scripts/
│   ├── autoload/              # Singleton managers
│   │   ├── OrbitalConstants.gd    # G, AU, body data, formatting
│   │   ├── TimeManager.gd         # Time warp, simulation time
│   │   └── GameManager.gd         # Global state, focus tracking
│   │
│   ├── core/                  # Orbital mechanics engine
│   │   ├── OrbitalMechanics.gd    # Static math functions
│   │   ├── OrbitState.gd          # Orbital state resource
│   │   └── ManeuverNode.gd        # Planned maneuver resource
│   │
│   ├── bodies/                # Celestial bodies
│   │   ├── CelestialBody.gd       # Base class
│   │   ├── Sun.gd                 # Central star
│   │   └── Planet.gd              # Orbiting body
│   │
│   ├── ship/                  # Player/NPC ships
│   │   └── Ship.gd                # Ship with thrust & maneuvers
│   │
│   ├── camera/                # View management
│   │   ├── ScaleConverter.gd      # World <-> screen coords
│   │   └── OrbitalCamera.gd       # Zoom, pan, focus
│   │
│   ├── ui/
│   │   └── tactical/
│   │       └── TacticalDisplay.gd # Main orbital map
│   │
│   └── Main.gd                # Entry point
│
├── scenes/
│   ├── Main.tscn              # Root scene (instances SolarSystem.tscn)
│   ├── SolarSystem.tscn       # Sun + 8 planets (Mercury-Neptune)
│   └── bodies/
│       ├── Sun.tscn
│       ├── Planet.tscn
│       └── Ship.tscn
│
├── docs/
│   ├── GAME_DESIGN.md         # Design document
│   ├── SESSION_LOG.md         # Development log
│   └── ARCHITECTURE.md        # This file
│
└── shaders/                   # (planned)
```

## Core Systems

### 1. Orbital Mechanics (`OrbitalMechanics.gd`)

Static class with pure math functions:

```gdscript
# Kepler equation solver
solve_kepler(M, e) -> E

# Coordinate conversions
elements_to_state(a, e, omega, M, mu) -> {position, velocity}
state_to_elements(pos, vel, mu) -> {a, e, omega, M, ...}

# Orbital parameters
get_orbital_period(a, mu) -> T
vis_viva(r, a, mu) -> v
get_apoapsis(a, e) -> r_a
get_periapsis(a, e) -> r_p

# Transfers
hohmann_transfer(r1, r2, mu) -> {dv1, dv2, transfer_time}

# Integration
rk4_step(pos, vel, mu, dt, thrust) -> {pos, vel}
```

### 2. Orbit State (`OrbitState.gd`)

Resource holding orbital elements and cached state vectors:

```gdscript
# Keplerian elements
semi_major_axis: float      # a (meters)
eccentricity: float         # e
argument_of_periapsis: float # omega (radians)
mean_anomaly_at_epoch: float # M0 (radians)
epoch_time: float           # t0 (seconds)
parent_mu: float            # G*M of parent

# Cached state (updated by propagation)
position: Vector2
velocity: Vector2

# Key methods
update_state_vectors(time)     # Kepler propagation
apply_impulse(delta_v, time)   # Maneuver execution
sample_orbit_points(n)         # For visualization
```

### 3. Time Manager (`TimeManager.gd`)

Singleton controlling simulation time:

```gdscript
# State
simulation_time: float     # Total elapsed seconds
current_warp_level: WarpLevel
is_paused: bool

# Warp levels: PAUSED, REAL_TIME, X10, X100, X1000, X10000, X100000

# Methods
get_delta_time(frame_delta) -> float  # Scaled delta
increase_warp() / decrease_warp()
schedule_event(time, name, callback, auto_pause)
warp_to_time(target_time)
```

### 4. Ship (`Ship.gd`)

Spacecraft with orbital mechanics:

```gdscript
# State
orbit_state: OrbitState
parent_body: CelestialBody
fuel_mass: float
is_thrusting: bool

# Thrust directions
enum ThrustDirection { NONE, PROGRADE, RETROGRADE, RADIAL_IN, RADIAL_OUT, MANUAL }

# Physics loop
_physics_process(delta):
    if is_thrusting:
        _integrate_thrust(sim_delta)  # RK4
    else:
        orbit_state.update_state_vectors(time)  # Kepler

# Maneuvers
plan_maneuver(time, delta_v) -> ManeuverNode
plan_hohmann_to_altitude(altitude) -> [node1, node2]
```

### 5. Scale Converter (`ScaleConverter.gd`)

Handles the AU-scale to screen-pixels problem:

```gdscript
# Modes (LINEAR is default)
enum ScaleMode { LINEAR, LOGARITHMIC, HYBRID }

# Settings
focus_position: Vector2    # World center (meters) - always player ship
zoom_level: float          # Higher = more zoomed in (scroll wheel)

# Transforms
world_to_screen(world_pos) -> Vector2
screen_to_world(screen_pos) -> Vector2
distance_to_screen(meters) -> pixels
```

**Current behavior:** Pure linear scale with manual zoom. Player ship always centered. Off-screen indicators point to distant objects.

## Data Flow

```
TimeManager.simulation_time
        │
        ▼
┌───────────────────┐
│  Celestial Bodies │
│  (Kepler prop)    │
└─────────┬─────────┘
          │ world_position
          ▼
┌───────────────────┐     ┌───────────────────┐
│       Ship        │────▶│   OrbitState      │
│ (Kepler or RK4)   │     │ (elements + state)│
└─────────┬─────────┘     └───────────────────┘
          │ world_position
          ▼
┌───────────────────┐
│  ScaleConverter   │
│ (world → screen)  │
└─────────┬─────────┘
          │ screen coordinates
          ▼
┌───────────────────┐
│  TacticalDisplay  │
│ (renders orbits)  │
└───────────────────┘
```

## Physics Modes

### Coasting (Kepler Propagation)
- Analytically exact, no drift
- Works at any time warp
- Fast: just solve Kepler equation

```
M(t) = M0 + n * (t - t0)
E = solve_kepler(M, e)
nu = eccentric_to_true(E, e)
r = a * (1 - e * cos(E))
pos = rotate(r, nu + omega)
```

### Thrusting (RK4 Integration)
- Numerical integration with thrust force
- Substeps for stability (max 1 second each)
- Recalculates orbital elements after burn

```
for step in subdivide(delta):
    {pos, vel} = rk4_step(pos, vel, mu, step, thrust_accel)
    fuel -= mass_flow_rate * step
orbital_elements = state_to_elements(pos, vel, mu)
```

## Key Algorithms

### Kepler Equation Solver (Newton-Raphson)
```
E_n+1 = E_n - (E_n - e*sin(E_n) - M) / (1 - e*cos(E_n))
```
Converges in ~5 iterations for typical orbits.

### Hohmann Transfer
```
a_transfer = (r1 + r2) / 2
dv1 = sqrt(mu * (2/r1 - 1/a_transfer)) - sqrt(mu/r1)
dv2 = sqrt(mu/r2) - sqrt(mu * (2/r2 - 1/a_transfer))
t_transfer = PI * sqrt(a_transfer^3 / mu)
```

### Vis-Viva Equation
```
v^2 = mu * (2/r - 1/a)
```
Gives orbital velocity at any radius.

## Units Convention

| Quantity | Unit | Notes |
|----------|------|-------|
| Distance | meters | 1 AU = 1.496e11 m |
| Mass | kilograms | Earth = 5.972e24 kg |
| Time | seconds | 1 day = 86400 s |
| Velocity | m/s | Earth orbital = 29,780 m/s |
| Angle | radians | |
| G | 6.67430e-11 | m^3/(kg*s^2) |
