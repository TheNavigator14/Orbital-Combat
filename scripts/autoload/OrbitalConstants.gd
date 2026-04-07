extends Node
class_name OrbitalConstantsClass
## Global orbital mechanics constants and unit conversions

# === Fundamental Constants ===
const G: float = 6.67430e-11  # Gravitational constant (m^3 / kg / s^2)
const AU: float = 149597870700.0  # Astronomical Unit in meters
const LIGHT_SECOND: float = 299792458.0  # Speed of light (m/s)

# === Time Constants ===
const SECONDS_PER_MINUTE: float = 60.0
const SECONDS_PER_HOUR: float = 3600.0
const SECONDS_PER_DAY: float = 86400.0
const SECONDS_PER_YEAR: float = 31557600.0  # Julian year (365.25 days)

# === Celestial Body Data ===
# All masses in kg, radii in meters, orbital radii in meters

const SUN_MASS: float = 1.989e30
const SUN_RADIUS: float = 6.96e8
const SUN_MU: float = 1.32712440018e20  # G * M_sun (m^3/s^2)

const EARTH_MASS: float = 5.972e24
const EARTH_RADIUS: float = 6.371e6
const EARTH_MU: float = 3.986004418e14  # G * M_earth
const EARTH_ORBITAL_RADIUS: float = 1.0 * AU
const EARTH_ECCENTRICITY: float = 0.017
const EARTH_ORBITAL_PERIOD: float = 365.25 * SECONDS_PER_DAY

const MOON_MASS: float = 7.342e22
const MOON_RADIUS: float = 1.737e6
const MOON_MU: float = 4.9028e12
const MOON_ORBITAL_RADIUS: float = 3.844e8  # From Earth
const MOON_ORBITAL_PERIOD: float = 27.3 * SECONDS_PER_DAY

# Mercury
const MERCURY_MASS: float = 3.301e23
const MERCURY_RADIUS: float = 2.440e6
const MERCURY_MU: float = 2.2032e13
const MERCURY_ORBITAL_RADIUS: float = 0.387 * AU
const MERCURY_ECCENTRICITY: float = 0.206
const MERCURY_ORBITAL_PERIOD: float = 88.0 * SECONDS_PER_DAY

# Venus
const VENUS_MASS: float = 4.867e24
const VENUS_RADIUS: float = 6.052e6
const VENUS_MU: float = 3.24859e14
const VENUS_ORBITAL_RADIUS: float = 0.723 * AU
const VENUS_ECCENTRICITY: float = 0.007
const VENUS_ORBITAL_PERIOD: float = 224.7 * SECONDS_PER_DAY

# Mars
const MARS_MASS: float = 6.417e23
const MARS_RADIUS: float = 3.390e6
const MARS_MU: float = 4.282837e13
const MARS_ORBITAL_RADIUS: float = 1.524 * AU
const MARS_ECCENTRICITY: float = 0.093
const MARS_ORBITAL_PERIOD: float = 687.0 * SECONDS_PER_DAY

# Jupiter
const JUPITER_MASS: float = 1.898e27
const JUPITER_RADIUS: float = 6.991e7
const JUPITER_MU: float = 1.26687e17
const JUPITER_ORBITAL_RADIUS: float = 5.203 * AU
const JUPITER_ECCENTRICITY: float = 0.049
const JUPITER_ORBITAL_PERIOD: float = 4333.0 * SECONDS_PER_DAY

# Saturn
const SATURN_MASS: float = 5.683e26
const SATURN_RADIUS: float = 5.823e7
const SATURN_MU: float = 3.7931e16
const SATURN_ORBITAL_RADIUS: float = 9.537 * AU
const SATURN_ECCENTRICITY: float = 0.054
const SATURN_ORBITAL_PERIOD: float = 10759.0 * SECONDS_PER_DAY

# Uranus
const URANUS_MASS: float = 8.681e25
const URANUS_RADIUS: float = 2.536e7
const URANUS_MU: float = 5.7940e15
const URANUS_ORBITAL_RADIUS: float = 19.19 * AU
const URANUS_ECCENTRICITY: float = 0.047
const URANUS_ORBITAL_PERIOD: float = 30687.0 * SECONDS_PER_DAY

# Neptune
const NEPTUNE_MASS: float = 1.024e26
const NEPTUNE_RADIUS: float = 2.462e7
const NEPTUNE_MU: float = 6.8351e15
const NEPTUNE_ORBITAL_RADIUS: float = 30.07 * AU
const NEPTUNE_ECCENTRICITY: float = 0.009
const NEPTUNE_ORBITAL_PERIOD: float = 60190.0 * SECONDS_PER_DAY

# === Display/Scale Constants ===
const LINEAR_SCALE_THRESHOLD: float = 1.0e9  # 1 million km - switch to log beyond this
const LOG_SCALE_FACTOR: float = 50.0  # Pixels per log10 unit
const MIN_ZOOM: float = 0.001
const MAX_ZOOM: float = 1000.0

# === Ship Constants (defaults) ===
const DEFAULT_SHIP_THRUST: float = 100000.0  # 100 kN
const DEFAULT_SHIP_ISP: float = 350.0  # seconds (chemical rocket)
const DEFAULT_EXHAUST_VELOCITY: float = DEFAULT_SHIP_ISP * 9.80665  # m/s
const DEFAULT_DRY_MASS: float = 10000.0  # 10 tons
const DEFAULT_FUEL_CAPACITY: float = 20000.0  # 20 tons

# === Utility Functions ===

static func meters_to_km(m: float) -> float:
	return m / 1000.0

static func km_to_meters(km: float) -> float:
	return km * 1000.0

static func meters_to_au(m: float) -> float:
	return m / AU

static func au_to_meters(au: float) -> float:
	return au * AU

static func seconds_to_hours(s: float) -> float:
	return s / SECONDS_PER_HOUR

static func seconds_to_days(s: float) -> float:
	return s / SECONDS_PER_DAY

static func format_distance(meters: float) -> String:
	## Format a distance for display with appropriate units
	var abs_m = abs(meters)
	if abs_m < 1000.0:
		return "%.1f m" % meters
	elif abs_m < 1.0e6:
		return "%.2f km" % (meters / 1000.0)
	elif abs_m < 1.0e9:
		return "%.2f Mm" % (meters / 1.0e6)  # Megameters
	elif abs_m < AU * 0.1:
		return "%.2f Gm" % (meters / 1.0e9)  # Gigameters
	else:
		return "%.4f AU" % (meters / AU)

static func format_velocity(mps: float) -> String:
	## Format velocity for display
	var abs_v = abs(mps)
	if abs_v < 1000.0:
		return "%.1f m/s" % mps
	else:
		return "%.2f km/s" % (mps / 1000.0)

static func format_time(seconds: float) -> String:
	## Format time duration for display
	var abs_s = abs(seconds)
	if abs_s < 60.0:
		return "%.1f s" % seconds
	elif abs_s < 3600.0:
		var mins = int(seconds / 60.0)
		var secs = fmod(seconds, 60.0)
		return "%d m %02d s" % [mins, int(secs)]
	elif abs_s < 86400.0:
		var hours = int(seconds / 3600.0)
		var mins = int(fmod(seconds, 3600.0) / 60.0)
		return "%d h %02d m" % [hours, mins]
	else:
		var days = int(seconds / 86400.0)
		var hours = int(fmod(seconds, 86400.0) / 3600.0)
		return "%d d %02d h" % [days, hours]

static func format_timestamp(simulation_seconds: float) -> String:
	## Format absolute simulation time as Year Day Hour:Minute:Second
	var years = int(simulation_seconds / SECONDS_PER_YEAR)
	var remainder = fmod(simulation_seconds, SECONDS_PER_YEAR)
	var days = int(remainder / SECONDS_PER_DAY)
	remainder = fmod(remainder, SECONDS_PER_DAY)
	var hours = int(remainder / SECONDS_PER_HOUR)
	remainder = fmod(remainder, SECONDS_PER_HOUR)
	var minutes = int(remainder / SECONDS_PER_MINUTE)
	var seconds = int(fmod(remainder, SECONDS_PER_MINUTE))

	return "Y%d D%03d %02d:%02d:%02d" % [years + 1, days + 1, hours, minutes, seconds]
