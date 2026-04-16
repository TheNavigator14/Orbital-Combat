# Orbital Combat - Game Design Document

## Vision Statement

A 2D space combat game featuring realistic orbital mechanics, tactical sensor-based gameplay, and a tactile cockpit interface. Inspired by **HighFleet**, **Silent Hunter III**, and **Kerbal Space Program**.

The player operates a spacecraft through sensor screens and instrument panels, plotting orbital maneuvers, tracking targets through passive and active sensors, and engaging in missile combat where physics and stealth matter.

---

## Core Pillars

### 1. Realistic Orbital Mechanics
- True Keplerian orbits with proper physics
- Slowing down speeds you up (reduces orbital radius)
- Hohmann transfers, gravity assists, orbital intercepts
- Time warp system for realistic AU-scale distances
- Player plots maneuvers, system calculates burn timing, player executes

### 2. Sensor-Based Gameplay
- **Thermal Sensors (Passive):** Detect engine burns and ship heat signatures
  - No target awareness - completely covert
  - Requires investigation to identify (plume size vs acceleration = ship class)
  - Limited information, must build picture over time

- **Radar (Active):** Full target information and precise tracking
  - Target KNOWS they're being tracked
  - Enables countermeasures (jammers, chaff)
  - Required for hard locks and firing solutions

### 3. Physicalized Combat
- Missiles obey orbital mechanics
- Player chooses launch profiles:
  - **Coasting launch:** Inherit ship velocity, save fuel for terminal maneuvering, harder to detect
  - **Immediate burn:** Faster intercept, but visible thermal signature
- PDCs for point defense, cannons for close range
- Ammunition and fuel are limited resources

### 4. Stealth & Terrain
- Planet horizons block line of sight BOTH ways
- Can hide movements and launches behind celestial bodies
- Heat management affects detectability
- Cold coast vs hot burn tradeoffs

### 5. Tactile Cockpit Interface
- CRT-aesthetic sensor displays
- Operate through screens and instruments
- Information must be interpreted, not just displayed
- Satisfying button presses and system interactions

---

## Scale & Setting

### Solar System
- Realistic AU-scale distances
- Real orbital periods (Earth: 365 days, etc.)
- Time warp from 1x to 100,000x
- Auto-pause for maneuvers and events

### Units
- Distance: Meters (display as km, Mm, AU)
- Mass: Kilograms
- Time: Seconds (display as h:m:s, days)
- Velocity: m/s (display as km/s)

---

## Ship Systems

### Propulsion
- Main engine with thrust (Newtons) and specific impulse
- Fuel/propellant is consumed (Tsiolkovsky rocket equation)
- Delta-v budget determines mission capability
- Orientation control for pointing ship

### Sensors
- Thermal detection range and sensitivity
- Radar range and tracking accuracy
- Lock acquisition speed
- Investigation/identification capability

### Weapons
- **Missiles:** Various types with different guidance, range, warhead
- **PDCs:** Point defense for incoming missiles
- **Cannons:** Short-range kinetic weapons

### Countermeasures
- Chaff for radar confusion
- Flares for IR missiles
- Jammers for radar degradation

---

## Gameplay Loop

### Patrol/Transit Phase
1. Plot orbital transfer to patrol area
2. Execute maneuvers
3. Time warp during coast phases
4. Monitor passive sensors

### Detection Phase
1. Thermal contact detected
2. Investigate signature (military? cargo? size?)
3. Decide to engage or observe
4. Position for advantageous approach

### Engagement Phase
1. Activate radar for hard lock (reveals your position)
2. Configure missile launch profile
3. Launch missiles
4. Manage countermeasures if targeted
5. Guide missiles or let autonomous seekers work

### Resolution
- Target destroyed, escaped, or surrendered
- Assess damage and ammunition
- Continue patrol or return to base

---

## UI Layout (Planned)

```
+----------------------------------+
|  TACTICAL DISPLAY                |
|  (Orbital map, contacts, orbits) |
|                                  |
+----------------------------------+
|  NAV PANEL  |  SHIP PANEL        |
|  Ap/Pe/Alt  |  Fuel/dV/Thrust    |
|  Period     |  Heat/Status       |
+-------------+--------------------+
|  TIME: Y1 D045 12:34:56  [>>>]   |
+----------------------------------+
```

---

## Development Phases

### Phase 1: Orbital Foundation ✅ COMPLETE
- [x] Kepler orbital mechanics
- [x] Full solar system (Sun + 8 planets with realistic orbits)
- [x] Ship with thrust and orbital maneuvers
- [x] Time warp system (1x to 100,000x)
- [x] Basic tactical display (ship-centered, linear scale, CRT aesthetic)
- [x] Maneuver node planning UI (N key adds node, panel controls)
- [x] Polished cockpit panels (Nav, Ship, Time, Maneuver, Sound)
- [x] Moon + SOI transitions (Earth has Moon, SOI detection)

### Phase 2: Sensors & Detection ✅ COMPLETE
- [x] Thermal sensor system (passive detection, engine burn signatures)
- [x] Radar system with target awareness (active tracking, reveals position)
- [x] Planet horizon occlusion (line of sight blocking)
- [x] Contact identification mechanics (signature analysis, ship class ID)

### Phase 3: Combat ✅ COMPLETE
- [x] Physicalized missiles (orbital propagation, types, profiles)
- [x] Launch profile configuration (immediate/coast/tangential)
- [x] Guidance modes (autonomous, player-guided, heat-seeking, pro-nav)
- [x] PDCs and point defense (auto-fire, threat tracking, hit detection)
- [x] Damage model (health, critical systems, damage events)

### Phase 4: AI & Missions ✅ COMPLETE
- [x] AI ship behaviors (patrol, intercept, evade, engage)
- [x] Mission objectives (objectives, tracking, save/load)
- [x] Multiple ship encounters (squadron spawning, wave system)
- [x] Campaign structure (story progression, mission selection UI)

### Phase 5: Polish ✅ COMPLETE
- [x] Full cockpit UI (CRT overlay, cockpit panels integrated)
- [x] Ship Status Panel (fuel, health, thrust, orbit info)
- [x] Sound design (procedural audio, CRT tones)
- [x] Visual effects (scanlines, vignette, phosphor glow, noise, flicker)
- [x] Ship customization/upgrades (loadout system, CRT panel)

---

## Inspirations

- **HighFleet:** Tactile cockpit feel, CRT aesthetics, tense sensor gameplay
- **Silent Hunter III:** Submarine tension, plotting intercepts, passive vs active sonar
- **Kerbal Space Program:** Orbital mechanics satisfaction, maneuver planning, delta-v budgets
- **Children of a Dead Earth:** Realistic space combat physics
- **The Expanse:** Hard sci-fi aesthetic, missile combat, sensor warfare
