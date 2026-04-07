# Orbital Combat - Development Session Log

## Session 1: Project Foundation
**Date:** 2026-04-02

### Overview
Pivoted from previous SpaceCombat game design to create a new 2D orbital mechanics space combat game. Established core architecture and implemented Phase 1 foundation.

### Design Decisions Made

1. **Physics Approach:** Hybrid Kepler/Integration
   - Kepler propagation for on-rails coasting (stable at any time warp)
   - RK4 numerical integration only during active thrust
   - Orbital state stored as Keplerian elements, not just position/velocity

2. **Scale Handling:** Hybrid Linear/Logarithmic
   - Linear scaling for distances under 1 million km (local maneuvers)
   - Logarithmic scaling beyond (solar system view)
   - Smooth visual transition between modes

3. **Fresh Start:** New project in `Obital Combat` folder
   - Only borrowing CRT visual aesthetic from SpaceCombat
   - All gameplay systems designed fresh (especially sensors)

4. **First Milestone:** Orbital flight + maneuvers
   - Ship orbiting Earth, can plot and execute transfers
   - Before adding combat or sensors

### Files Created (18 total)

#### Autoloads (`scripts/autoload/`)
- `OrbitalConstants.gd` - Physical constants (G, AU), celestial body data, unit formatting functions
- `TimeManager.gd` - Time warp (0x to 100,000x), simulation time tracking, scheduled events with auto-pause
- `GameManager.gd` - Global game state, focus tracking, celestial body registry

#### Core Orbital Mechanics (`scripts/core/`)
- `OrbitalMechanics.gd` - The math engine:
  - Newton-Raphson Kepler equation solver (elliptical and hyperbolic)
  - State vector <-> orbital elements conversions
  - Vis-viva equation, orbital period, mean motion
  - Hohmann transfer calculations
  - RK4 numerical integration with thrust

- `OrbitState.gd` - Resource class for orbital state:
  - Keplerian elements (a, e, omega, M0, t0)
  - Kepler propagation (`update_state_vectors`)
  - Impulse application with element recalculation
  - Trajectory sampling for visualization

- `ManeuverNode.gd` - Planned velocity change:
  - Execution time and delta-v vector
  - Burn duration calculation
  - Resulting orbit preview

#### Celestial Bodies (`scripts/bodies/`)
- `CelestialBody.gd` - Base class: mass, radius, mu, SOI, surface gravity
- `Sun.gd` - Central star, stationary at origin, warm yellow with corona glow
- `Planet.gd` - Orbiting body with Kepler propagation, SOI calculation

#### Ship (`scripts/ship/`)
- `Ship.gd` - Player/NPC ship:
  - Kepler propagation when coasting
  - RK4 integration when thrusting (with substeps for stability)
  - Thrust directions: prograde, retrograde, radial in/out, manual
  - Fuel consumption and delta-v budget
  - Maneuver planning and execution
  - Automatic time warp limiting during thrust

#### Camera & Scale (`scripts/camera/`)
- `ScaleConverter.gd` - World (meters) to screen (pixels) mapping:
  - Linear mode, logarithmic mode, hybrid mode
  - Zoom level handling
  - Inverse transforms for click-to-world

- `OrbitalCamera.gd` - Zoom, pan, focus tracking (partially used)

#### UI (`scripts/ui/tactical/`)
- `TacticalDisplay.gd` - Main orbital map:
  - CRT aesthetic (dark green background, scanlines, vignette)
  - Logarithmic distance grid rings
  - Orbit path rendering
  - Celestial body and ship indicators
  - Apoapsis/Periapsis markers
  - Off-screen indicators
  - Info panel with orbital parameters

#### Main Scene
- `Main.gd` - Entry point:
  - Initializes solar system
  - Spawns player ship in 400km Earth orbit
  - Sets up tactical display

### Scenes Created
- `Main.tscn` - Root scene with solar system, camera, UI
- `SolarSystem.tscn` - Sun + Earth in realistic orbit
- `Sun.tscn`, `Planet.tscn`, `Ship.tscn` - Prefab scenes

### Controls Implemented
| Key | Action |
|-----|--------|
| W | Prograde thrust |
| S | Retrograde thrust |
| A | Radial-in thrust |
| D | Radial-out thrust |
| , | Decrease time warp |
| . | Increase time warp |
| Mouse wheel | Zoom in/out |
| M | Toggle focus (ship/Earth) |

### Bug Fixes
- Fixed zoom not working: TacticalDisplay Control was not handling mouse wheel input. Added `_gui_input` handler for zoom.

### Current State
- Ship spawns in 400km circular orbit around Earth
- Orbital period displays correctly (~92 minutes)
- Can thrust to change orbit (Kepler recalculates after thrust)
- Time warp works up to 100,000x
- Zoom and focus switching work
- CRT aesthetic displays orbit paths and info

### Next Steps (for next session)

1. **Maneuver Planning UI**
   - Clickable maneuver nodes on orbit
   - Drag handles for prograde/radial adjustment
   - Predicted trajectory display
   - Burn countdown and execution

2. **Cockpit Panels**
   - Proper NavPanel with orbital readouts
   - ShipPanel with fuel gauge and status
   - TimePanel with warp controls
   - ManeuverPanel with node details

3. **Additional Bodies**
   - Add Moon orbiting Earth
   - Test SOI transitions

4. **Polish**
   - Better ship visualization
   - Thrust effects
   - Orbit prediction during thrust

### Technical Notes

- Using Godot 4.5
- All physics in SI units (meters, kg, seconds)
- Kepler solver uses Newton-Raphson, converges in ~5 iterations typically
- Time warp simply multiplies delta-t passed to propagation
- RK4 integration uses substeps (max 1 second each) for stability at high warp

### Reference Files
- Plan saved at: `C:\Users\Molin\.claude\plans\precious-brewing-sifakis.md`
- SpaceCombat reference: `C:\Project_Games\SpaceCombat` (CRT aesthetic only)
- Godot located at: `C:\Dev_Folder`

---

## Session 2: Full Solar System & Display Fixes
**Date:** 2026-04-05

### Overview
Added all 8 planets to create a complete solar system model and fixed several bugs preventing proper display.

### Changes Made

#### 1. Complete Solar System
Added all planets with realistic orbital parameters:
| Planet  | Semi-major Axis | Eccentricity | Color |
|---------|-----------------|--------------|-------|
| Mercury | 0.387 AU        | 0.206        | Gray |
| Venus   | 0.723 AU        | 0.007        | Yellow-orange |
| Earth   | 1.000 AU        | 0.017        | Blue |
| Mars    | 1.524 AU        | 0.093        | Red-orange |
| Jupiter | 5.203 AU        | 0.049        | Orange-brown |
| Saturn  | 9.537 AU        | 0.054        | Gold |
| Uranus  | 19.19 AU        | 0.047        | Cyan |
| Neptune | 30.07 AU        | 0.009        | Deep blue |

#### 2. Scale Mode Change
- Switched from hybrid (linear + logarithmic) to **pure linear** scale
- User can zoom in/out freely with scroll wheel
- Off-screen indicators point to distant objects

#### 3. Camera Behavior
- Player ship is now **always centered** on the tactical display
- Removed focus toggle affecting centering (was causing confusion)

### Bug Fixes

1. **Missing `register_player_ship()` call** - TacticalDisplay never received the player ship reference, so ship-related drawing was skipped

2. **Undefined variable crash** - `Main.gd` referenced `earth` variable outside its scope

3. **Planet initialization order** - Planets' `_ready()` ran before `parent_body` was set, causing `_initialize_orbit()` to fail. Fixed by calling `_initialize_orbit()` manually after setting parent_body in Main.gd

4. **Main.tscn embedded SolarSystem** - Main.tscn had Sun and Earth embedded directly instead of instancing SolarSystem.tscn. Fixed to use proper scene instancing.

5. **OrbitalCamera method conflict** - `set_zoom()` conflicted with Godot's Camera2D built-in method. Renamed to `set_zoom_level()`.

### Files Modified
- `scripts/autoload/OrbitalConstants.gd` - Added planetary constants for all 8 planets
- `scripts/Main.gd` - Fixed registration, initialization order, removed broken focus call
- `scripts/camera/ScaleConverter.gd` - Changed default to LINEAR mode
- `scripts/camera/OrbitalCamera.gd` - Renamed conflicting method
- `scripts/ui/tactical/TacticalDisplay.gd` - Always center on player ship, added outer solar system grid rings
- `scenes/SolarSystem.tscn` - Added all 8 planets with orbital parameters
- `scenes/Main.tscn` - Changed to instance SolarSystem.tscn instead of embedding

### Current State
- Full solar system with 8 planets orbiting the Sun
- Player ship in 400km Earth orbit, always centered on display
- All planets visible and orbiting at correct relative speeds
- Time warp shows planetary motion (inner planets move noticeably at 10,000x+)
- Linear scale with manual zoom

### Next Steps (Priority Order)

#### 1. Maneuver Planning UI (Recommended Next)
- Click on orbit to place maneuver node
- Drag handles for prograde/radial delta-v adjustment
- Show predicted trajectory after maneuver
- Burn countdown timer and auto-execute option
- This is the core gameplay loop - plotting transfers

#### 2. Add Moon + SOI Transitions
- Add Moon orbiting Earth (~384,000 km, 27.3 day period)
- Implement SOI (Sphere of Influence) detection
- Switch parent body when crossing SOI boundary
- Test Earth-Moon transfers

#### 3. Cockpit Panels (Can Wait)
- NavPanel: Ap/Pe/Alt/Period readouts
- ShipPanel: Fuel gauge, delta-v remaining, thrust status
- TimePanel: Warp controls with visual buttons
- ManeuverPanel: Next node details, time to burn

#### 4. Polish (Later)
- Better ship/planet visualization
- Thrust particle effects
- Orbit prediction while thrusting
- Sound effects
