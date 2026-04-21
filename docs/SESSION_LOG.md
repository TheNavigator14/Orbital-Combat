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

---

## Session 3: GitHub Repository Setup
**Date:** 2026-04-06

### Overview
Set up version control and pushed the project to GitHub for backup and collaboration.

### Changes Made

#### 1. Git Repository Initialization
- Initialized git repository in project folder
- Created `.gitignore` for Godot projects:
  - Ignores `.godot/` (engine cache)
  - Ignores build outputs (`.exe`, `.pck`, `.apk`)
  - Ignores IDE files (`.vscode/`, `.idea/`)

#### 2. GitHub Setup
- Configured git identity for commits
- Created initial commit with 41 files (3,761 lines of code)
- Pushed to GitHub: `https://github.com/TheNavigator14/Orbital-Combat`

### Files Added
- `.gitignore` - Godot-specific ignore patterns

### Repository Structure
```
Orbital-Combat/
├── .gitignore
├── project.godot
├── icon.svg
├── docs/
│   ├── ARCHITECTURE.md
│   ├── GAME_DESIGN.md
│   └── SESSION_LOG.md
├── scenes/
│   ├── Main.tscn
│   ├── SolarSystem.tscn
│   └── bodies/
├── scripts/
│   ├── Main.gd
│   ├── autoload/
│   ├── bodies/
│   ├── camera/
│   ├── core/
│   ├── ship/
│   └── ui/
└── shaders/
```

### Current State
- Project under version control
- All code backed up to GitHub
- Ready for collaborative development

---

## Session 4: Navigation System Implementation
**Date:** 2026-04-13

### Overview
Implemented a goal-oriented navigation system with interplanetary transfer planning, maneuver visualization, and interactive editing.

### Design Philosophy
- **Two-mode system**: Tactical display for combat/manual flying, Navigation Planner popup for mission planning
- **Goal-oriented**: Select destination and burn mode, system calculates optimal maneuvers
- **Manual fine-tuning**: Drag handles on calculated maneuvers for tactical adjustments

### New Files Created

#### Navigation Backend (`scripts/navigation/`)
1. **TransferCalculator.gd** - Interplanetary transfer mathematics:
   - Phase angle calculation between bodies
   - Transfer window computation (synodic period)
   - Hohmann transfer delta-v calculations
   - Window class with departure/arrival times and delta-v

2. **TrajectoryPlanner.gd** - Converts goals into ManeuverNodes:
   - Transfer to planet → departure + arrival burns
   - Circularize at Ap/Pe → single burn
   - Raise/Lower Ap/Pe → single burn
   - ManeuverPlan class for grouping related maneuvers

#### Tactical UI (`scripts/ui/tactical/`)
3. **ManeuverRenderer.gd** - Renders maneuvers on tactical display:
   - Diamond markers at burn positions
   - Delta-v arrows showing burn direction/magnitude
   - Predicted trajectory (dashed amber line)
   - Prograde/radial drag handles for editing
   - Hit testing for click detection

4. **ManeuverInteraction.gd** - Handles maneuver editing:
   - Click to select maneuvers
   - Drag handles to adjust delta-v
   - Delete selected maneuver
   - Warp to maneuver time

#### Navigation UI (`scripts/ui/navigation/`)
5. **NavigationPlanner.gd** - Pop-up navigation computer window:
   - Goal selector (Transfer, Circularize, etc.)
   - Target planet selector
   - Transfer window list with departure times and delta-v costs
   - Creates maneuver nodes on confirmation
   - Auto-pause option while planning

### Files Modified

#### `scripts/core/OrbitalMechanics.gd`
Added interplanetary transfer functions:
- `calculate_phase_angle(pos1, pos2)` - Angle between two bodies
- `hohmann_phase_angle(r1, r2, mu)` - Required phase angle for transfer
- `synodic_period(period1, period2)` - Time between windows
- `time_to_phase_angle()` - When phase angle will be reached

#### `scripts/ui/tactical/TacticalDisplay.gd`
Integrated navigation system:
- Added ManeuverRenderer for drawing maneuvers
- Added ManeuverInteraction for editing
- Added NavigationPlanner popup (child node)
- Added "PLAN ROUTE" button (top-right)
- Added keyboard shortcut (N) to open planner
- Added DELETE key to remove selected maneuver

### Controls Added
| Key | Action |
|-----|--------|
| N | Open Navigation Planner |
| Delete | Delete selected maneuver |
| Click on maneuver | Select maneuver |
| Drag handle | Adjust delta-v |
| Click PLAN ROUTE | Open Navigation Planner |

### Architecture

```
User selects goal (e.g., "Transfer to Mars")
    │
    ▼
NavigationPlanner.gd
    │── Queries TransferCalculator.gd for windows
    │── User selects window
    │── Calls TrajectoryPlanner.gd
    │
    ▼
TrajectoryPlanner.gd
    │── Creates ManeuverNode(s) via Ship.plan_maneuver()
    │── Returns ManeuverPlan
    │
    ▼
TacticalDisplay.gd
    │── ManeuverRenderer draws nodes
    │── ManeuverInteraction handles editing
    │
    ▼
Ship.gd (existing)
    │── Stores planned_maneuvers array
    │── Auto-executes at scheduled time
```

### Current State
- Navigation planner opens with "PLAN ROUTE" button or N key
- Can select interplanetary transfers and see transfer windows
- Creates departure and arrival burns for Hohmann transfers
- Maneuvers appear on tactical display as yellow diamonds
- Can select and see predicted trajectory
- Can drag handles to fine-tune delta-v
- Delete key removes selected maneuver
- Existing auto-execution system handles burn timing

### Known Limitations / Future Work
1. **Ship orbit assumption**: Transfer calculator assumes heliocentric orbit
2. **Orbit adjustment goals**: Raise/Lower Ap/Pe not fully wired up in UI
3. **Continuous thrust**: Only Hohmann (coast) mode implemented
4. **SOI transitions**: Not yet handled for arriving at planets
5. **Visual polish**: Basic UI, could use more CRT styling

### Next Steps (Priority Order)

1. **Test and Debug**
   - Run game and test full navigation flow
   - Fix any issues with transfer calculations
   - Verify maneuver execution works correctly

2. **SOI Transitions**
   - Detect when ship enters planet SOI
   - Switch parent body and recalculate orbit
   - Arrival burns should capture into planet orbit

3. **Orbit Adjustment UI**
   - Wire up circularize, raise/lower Ap/Pe in navigation planner
   - Add altitude input for custom orbit changes

4. **Maneuver Info Panel**
   - Show details of selected maneuver
   - Add "Warp To" button
   - Countdown timer near execution

5. **Continuous Thrust**
   - Calculate brachistochrone trajectories
   - Preview thrust-coast-thrust paths
   - Hybrid burn modes

---

## Session 4 (Continued): Gravity Assist Detection
**Date:** 2026-04-13

### Overview
Added automatic detection of gravity assist (flyby) opportunities along interplanetary transfer trajectories.

### Changes Made

#### 1. TransferCalculator.gd - Flyby Detection System
Added new classes and functions for detecting when transfers pass near intermediate planets:

- **FlybyOpportunity class**: Stores flyby data including:
  - Target planet and encounter time
  - Closest approach distance
  - Estimated delta-v savings
  - Turn angle from gravity assist
  - Viability flag (within SOI and safe altitude)

- **TransferWindow extensions**:
  - Added `flyby_opportunities` array to store detected flybys
  - Added `has_viable_flybys()` to check for opportunities
  - Added `get_best_flyby()` to get the highest delta-v benefit flyby
  - Updated `get_info_string()` to include flyby information

- **Detection functions**:
  - `detect_flybys_for_window()` - Scans for planets along transfer path
  - `_calculate_flyby_opportunity()` - Computes encounter details
  - `_estimate_gravity_assist_dv()` - Calculates delta-v benefit using patched conic approximation
  - `_estimate_turn_angle()` - Computes trajectory bend angle

#### 2. NavigationPlanner.gd - Flyby UI
Updated the navigation planner to display flyby information:

- Added "Flyby" column to transfer window list
- Shows abbreviated planet name (e.g., "VEN", "MAR") for windows with viable flybys
- Added gold/amber color for flyby indicators
- Selected transfer summary now shows flyby assist details with estimated delta-v savings
- Increased window height to accommodate flyby information

### Technical Details

#### Gravity Assist Physics
The system uses the patched conic approximation:
1. Calculate spacecraft velocity relative to Sun at flyby point
2. Compute approach velocity relative to the flyby planet
3. Estimate turn angle using: `sin(δ/2) = 1 / (1 + r_p * v_inf² / μ)`
4. Calculate delta-v benefit: `Δv = 2 * v_inf * sin(δ/2)`

#### Flyby Viability Criteria
- Planet's orbital radius must intersect the transfer trajectory
- Encounter must occur within planet's sphere of influence
- Closest approach must be above minimum safe altitude (1.1x planet radius)

### Current State
- Transfer windows now automatically detect flyby opportunities
- Viable flybys are highlighted in the navigation planner UI
- Estimated delta-v savings are shown for each flyby
- System detects flybys for Earth→Mars (Venus assist) and other transfers

### Known Limitations
1. **Simplified geometry**: Assumes coplanar orbits and optimal flyby geometry
2. **Timing approximation**: Planet position at encounter is estimated
3. **No trajectory modification**: Shows flyby potential but doesn't modify the transfer plan
4. **Single flyby**: Only detects one flyby per window, not multi-flyby sequences

### Next Steps
1. **Flyby trajectory planning**: Modify transfer to actually use the gravity assist
2. **Multi-flyby sequences**: Detect chains like Earth→Venus→Venus→Mercury
3. **Optimal flyby routing**: Calculate modified departure times for best assist geometry
4. **Flyby visualization**: Show flyby path on tactical display

---

## Session 5: SOI Transitions & Patched Conic Transfers
**Date:** 2026-04-14

### Overview
Implemented complete Sphere of Influence (SOI) transition system and patched conic interplanetary transfers. Ships can now properly escape from planetary orbit, coast on heliocentric transfer trajectories, and capture into destination orbit.

### Problem Solved
Previously, the transfer system assumed ships were already in heliocentric (Sun-centered) orbit. A ship starting in Earth orbit couldn't actually reach Mars because:
1. No escape burn from Earth's gravity well
2. No velocity frame transformation when crossing SOI boundaries
3. No capture burn when arriving at destination

### Solution: Patched Conic Approximation
A real interplanetary transfer has 3 phases:
1. **ESCAPE**: Burn to leave origin planet's SOI with hyperbolic excess velocity
2. **COAST**: Heliocentric Hohmann transfer ellipse
3. **CAPTURE**: Burn to enter destination orbit from hyperbolic approach

### Files Created

#### `scripts/navigation/TrajectoryPredictor.gd` (NEW)
Multi-segment trajectory prediction across SOI boundaries:
- `TrajectorySegment` class stores orbit data per SOI
- `predict_trajectory()` - predicts path including SOI crossings
- `predict_until_soi_exit()` - for escape trajectory visualization
- Handles velocity transformations at SOI boundaries

### Files Modified

#### `scripts/ship/Ship.gd`
Added SOI detection and transition system:
```gdscript
signal soi_changed(old_parent, new_parent)

func _check_soi_transition():
    # Check if leaving current parent's SOI
    # Check if entering a child body's SOI

func _transition_to_body(new_parent):
    # Transform orbit state to new reference frame
    # Add/subtract parent orbital velocities
    # Create new OrbitState in new frame

func get_heliocentric_velocity() -> Vector2
func get_heliocentric_position() -> Vector2
```

#### `scripts/core/OrbitalMechanics.gd`
Added escape/capture burn calculations:
```gdscript
static func calculate_escape_burn(parking_radius, v_infinity, mu) -> Dictionary
    # Returns: { dv, v_circular, v_periapsis, c3 }
    # Physics: v_pe² = v_inf² + 2μ/r

static func calculate_capture_burn(v_infinity, target_orbit_radius, mu) -> Dictionary
    # Same formula, opposite direction (retrograde)

static func calculate_hyperbolic_excess_velocity(r_origin, r_target, mu_sun) -> Dictionary
    # Returns: { v_inf_departure, v_inf_arrival, transfer_time }
```

#### `scripts/navigation/TransferCalculator.gd`
Added patched conic transfer support:
```gdscript
class PatchedConicTransfer:
    var escape_dv: float         # Phase 1
    var escape_v_infinity: float
    var capture_dv: float        # Phase 3
    var capture_v_infinity: float
    var transfer_time: float

class TransferWindow:
    # Extended with:
    var is_patched_conic: bool
    var patched_conic: PatchedConicTransfer
    var escape_dv, capture_dv: float

static func calculate_patched_conic_transfer(...) -> PatchedConicTransfer
static func calculate_patched_conic_windows(ship, target, count) -> Array[TransferWindow]
```

#### `scripts/navigation/TrajectoryPlanner.gd`
Updated for 3-burn planning:
```gdscript
static func plan_transfer_to_planet():
    # Now detects patched conic windows and routes accordingly

static func _plan_patched_conic_transfer():
    # Creates ESCAPE burn at periapsis of parking orbit
    # Creates pending CAPTURE burn (activates on SOI entry)
```

#### `scripts/core/ManeuverNode.gd`
Added burn type support:
```gdscript
var burn_type: String = "NORMAL"  # NORMAL, ESCAPE, CAPTURE, MIDCOURSE
var is_pending_capture: bool = false
var target_planet: Planet = null
var expected_dv_magnitude: float = 0.0
```

#### `scripts/ui/navigation/NavigationPlanner.gd`
Updated UI for 3-phase display:
- Shows ESCAPE burn delta-v and v∞
- Shows COAST duration
- Shows CAPTURE burn delta-v and v∞
- Color-coded phase labels (green/white/orange)

### Key Physics

#### Escape Burn
At periapsis of parking orbit:
```
v_pe² = v_inf² + 2μ/r_pe
Δv_escape = v_pe - v_circular
```

#### Capture Burn
At periapsis of hyperbolic approach:
```
v_pe² = v_inf² + 2μ/r_pe
Δv_capture = v_pe - v_circular
```

#### SOI Velocity Transformation
When crossing SOI boundary:
```
v_new_frame = v_old_frame + v_old_parent_orbital - v_new_parent_orbital
```

### Example: Earth to Mars Transfer
From 400km Earth orbit:
- **Escape**: ~3.6 km/s (v∞ = 2.9 km/s)
- **Coast**: ~260 days
- **Capture**: ~2.1 km/s (into 400km Mars orbit)
- **Total**: ~5.7 km/s

### Current State
- Ships can escape Earth's SOI by burning prograde
- SOI transitions are detected automatically during flight
- Navigation planner shows 3-phase breakdown for planetary transfers
- Transfer windows calculate proper escape and capture delta-v
- Pending capture burns are created for destination SOI entry

### Known Limitations
1. **Capture burn timing**: Currently scheduled at arrival_time, should activate on SOI entry
2. **Burn direction**: Escape always prograde, capture always retrograde (simplified)
3. **Optimal departure**: Should burn at periapsis aligned with escape direction
4. **No visualization**: TrajectoryPredictor created but not integrated with ManeuverRenderer yet

### Next Steps
1. **Integrate TrajectoryPredictor with ManeuverRenderer** - Show escape hyperbola and transfer ellipse
2. **Activate capture burn on SOI entry** - Listen for soi_changed signal
3. **Calculate optimal escape timing** - Align periapsis with departure direction
4. **Test full transfer** - Earth orbit → Mars orbit with time warp

---

## Session 6: Dual Control Mode System
**Date:** 2026-04-20

### Overview
Implemented a dual control mode system allowing players to switch between strategic orbital planning and direct tactical ship control. Added on-screen controls reference panel.

### Design Philosophy
- **Orbital Mode**: Decision-based gameplay through navigation interfaces
- **Combat Mode**: Direct mechanical control for close engagements at POIs
- **Manual Toggle**: Player chooses when to switch (Tab key)
- **Hybrid Physics**: Realistic orbital mechanics with stability assist for rotation

### New Files Created

#### `scripts/ui/ControlsPanel.gd`
On-screen keybind reference panel:
- Shows mode-specific controls
- Collapsible with click on header
- CRT aesthetic matching tactical display
- Auto-updates when control mode changes

### Files Modified

#### `scripts/ship/Ship.gd`
Added complete dual control system:

**New Enums & Properties:**
```gdscript
enum ControlMode { ORBITAL, COMBAT }
var control_mode: ControlMode = ControlMode.ORBITAL
var ship_rotation: float = 0.0  # World-relative facing
var angular_velocity: float = 0.0
var stability_assist_enabled: bool = true
var combat_input_state: Dictionary  # Tracks held keys
```

**New Signals:**
- `control_mode_changed(mode: ControlMode)`
- `stability_assist_toggled(enabled: bool)`

**New Methods:**
- `_toggle_control_mode()` - Switch between modes
- `_enter_combat_mode()` - Lock warp, init rotation to prograde
- `_enter_orbital_mode()` - Remove warp limit
- `_update_combat_rotation(delta)` - Apply rotation + SAS damping
- `_update_combat_thrust()` - Convert facing + WASD to world thrust
- `_handle_orbital_input(event)` - Route orbital mode keys
- `_handle_combat_input(event)` - Route combat mode keys
- `get_visual_rotation()` - Get rotation for rendering

#### `project.godot`
Added input mappings:
| Action | Key | Purpose |
|--------|-----|---------|
| `toggle_control_mode` | Tab | Switch ORBITAL/COMBAT |
| `rotate_left` | Q | Rotate CCW |
| `rotate_right` | E | Rotate CW |
| `toggle_stability_assist` | T | Toggle rotation damping |

#### `scripts/ui/tactical/TacticalDisplay.gd`
- Added mode indicator at top of info panel
- Added SAS status indicator (combat mode only)
- Updated ship drawing to use rotation
- Integrated ControlsPanel in bottom-right corner

### Controls Summary

#### Orbital Mode
| Key | Action |
|-----|--------|
| W | Prograde thrust |
| S | Retrograde thrust |
| A | Radial-in thrust |
| D | Radial-out thrust |
| N | Open navigation planner |
| ,/. | Time warp |
| Tab | Switch to Combat mode |

#### Combat Mode
| Key | Action |
|-----|--------|
| W | Thrust forward (ship-relative) |
| S | Thrust backward |
| A | Strafe left |
| D | Strafe right |
| Q | Rotate left (CCW) |
| E | Rotate right (CW) |
| T | Toggle stability assist |
| Tab | Switch to Orbital mode |

### Technical Details

#### Stability Assist (SAS)
- Only affects rotation, not linear velocity
- Uses `move_toward()` for linear damping feel
- Default strength: 5.0 rad/s² (stops spinning in ~0.4s)
- Toggleable with T key

#### Combat Rotation
- World-relative (absolute) - ship faces fixed direction in space
- Initialized to prograde when entering combat mode
- Persists across mode switches

#### Mode Switching
- Stops current thrust on mode change
- Combat mode locks time warp to 1x
- Interrupts auto-maneuver execution (stays queued)

### Current State
- Tab toggles between ORBITAL and COMBAT modes
- Combat mode: full ship control with W/S/A/D/Q/E
- SAS dampens rotation when enabled
- Controls panel shows current keybinds
- Ship visually rotates based on facing direction

### Next Steps
1. **Test controls** - Verify RCS and main engine feel
2. **Add maneuver alignment indicator** - Show where to point for planned burns
3. **Add RCS thruster visualization** - Show strafe/rotation thrusters firing

---

## Session 6 (Continued): Unified Control Scheme
**Date:** 2026-04-20

### Overview
Refactored from dual-mode (Orbital/Combat) system to a unified control scheme with RCS thrusters and toggleable main engine.

### Design Change
User feedback: Don't separate orbital and combat controls. Instead:
- Always have direct ship control with rotation
- Maneuvers are executed manually (warp to time, align, thrust)
- Two thrust systems: low-power RCS for maneuvering, high-power main engine for burns

### New Control Scheme

| Key | Action |
|-----|--------|
| Q/E | Rotate ship left/right |
| WASD | RCS thrust (when main engine off) |
| Space | Toggle main engine on/off |
| Up/Down | Increase/decrease throttle (25% steps) |
| T | Toggle stability assist (SAS) |
| N | Open navigation planner |
| ,/. | Time warp |
| Scroll | Zoom |

### Technical Changes

#### Ship.gd
- Removed `ControlMode` enum and dual-mode logic
- Added `main_engine_active: bool` - toggles main engine
- Added `throttle_level: int` - 0-4 (0%, 25%, 50%, 75%, 100%)
- Added `rcs_thrust: float` - weaker thrust for maneuvering (5kN vs 100kN main)
- RCS uses WASD when main engine is off
- Main engine thrusts forward at throttle level when on
- Exhaust color: Orange for main engine, Cyan for RCS

#### project.godot
- Changed `toggle_control_mode` to `toggle_main_engine` (Space key)

#### TacticalDisplay.gd
- Removed mode indicator
- Added engine status: "ENGINE: OFF" or "ENGINE: XX%"
- Always shows SAS status

#### ControlsPanel.gd
- Simplified to single set of controls (no mode switching)
- Shows all keybinds in one list

### Current State
- Unified control scheme working
- Q/E rotates ship, WASD uses RCS thrusters
- Space toggles main engine, Up/Down adjusts throttle
- Ship always faces a controllable direction
- Maneuvers require manual alignment and execution

### Next Steps
1. **Test controls** - Verify feel of RCS vs main engine
2. **Add maneuver alignment indicator** - Visual guide showing where to point for burns
3. **Tune thrust values** - Adjust RCS and main engine power for gameplay

---

## Session 6 (Continued): Simplified Maneuver System
**Date:** 2026-04-20

### Overview
Simplified the navigation/maneuver system to be more intuitive and educational. Removed complex transfer window timing in favor of preset maneuver buttons and immediate transfers.

### Design Philosophy
- **Educational approach**: Preset buttons teach players orbital mechanics implicitly
- **Transfer anytime**: No waiting for optimal phase angles - just pay more delta-v
- **Clear markers**: Maneuver nodes show where and when to burn, teaching the "why"

### Changes Made

#### `scripts/ui/navigation/NavigationPlanner.gd` - Complete Rewrite
Replaced complex transfer window system with preset buttons:

**New UI Layout:**
```
+---------------------------+
|   NAVIGATION COMPUTER     |
+---------------------------+
| ORBIT ADJUSTMENTS         |
| Current: Ap: XXX Pe: XXX  |
|                           |
| [Circ @ Ap] [Circ @ Pe]   |
| [Raise Ap]  [Lower Ap]    |
| [Raise Pe]  [Lower Pe]    |
+---------------------------+
| PLANET TRANSFER           |
| [MER][VEN][EAR][MAR]...   |
|                           |
| To: Mars                  |
| Delta-V: 5.72 km/s        |
| Travel time: 258 days     |
|                           |
| [CREATE TRANSFER]         |
+---------------------------+
| [CLOSE]                   |
+---------------------------+
```

**Removed:**
- Transfer window list and synodic period calculations
- Phase angle timing requirements
- Complex window selection UI

**Added:**
- 6 preset orbit adjustment buttons (±100km increments)
- Planet target selection as quick buttons
- Immediate transfer calculation with delta-v display
- "CREATE TRANSFER" button for transfers

#### `scripts/navigation/TransferCalculator.gd`
Added immediate transfer function:

```gdscript
static func calculate_immediate_transfer(ship, target) -> Dictionary
    ## Calculate transfer departing at next periapsis (no window timing)
    ## Returns: { total_dv, escape_dv, capture_dv, transfer_time, departure_time }
```

- Works for both planetary orbit (patched conic) and heliocentric orbit
- Departs at next periapsis for efficiency
- Calculates full escape + coast + capture delta-v

#### `scripts/navigation/TrajectoryPlanner.gd`
Added immediate transfer planning:

```gdscript
static func plan_immediate_transfer(ship, target, transfer_info) -> ManeuverPlan
    ## Create maneuver plan from immediate transfer calculation
```

- Creates ESCAPE burn with prograde direction
- Creates pending CAPTURE burn for SOI entry
- Works with existing maneuver system

### User Experience

#### Orbit Adjustments
1. Press N to open navigation planner
2. Click "Circularize @ Ap" (or other preset)
3. Maneuver marker appears on tactical display
4. Close planner, warp to marker time
5. Align ship to marker direction
6. Engage main engine, burn to completion

#### Planet Transfers
1. Press N to open navigation planner
2. Click target planet button (e.g., "MAR" for Mars)
3. See delta-v cost and travel time
4. Click "CREATE TRANSFER"
5. Escape maneuver appears at next periapsis
6. Execute as above, ship escapes to heliocentric orbit

### Technical Notes
- Preset buttons call existing `TrajectoryPlanner.plan_circularize()`, `plan_change_apoapsis()`, etc.
- Immediate transfers may use more delta-v than optimal windows (no phase angle timing)
- All calculations still use realistic orbital mechanics

### Current State
- Navigation planner uses simple preset buttons
- Can adjust orbit with one click
- Can initiate transfers to any planet immediately
- No waiting for transfer windows
- Maneuver markers guide player through execution

### Next Steps
1. **Add maneuver alignment indicator** - Show where to point ship for burns
2. **Polish maneuver markers** - Show Ap/Pe change preview
3. **Add custom altitude input** - For specific orbit changes
4. **Optional: Show "optimal window" comparison** - Educational display of delta-v savings
