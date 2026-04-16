class_name OrbitalUtils
extends RefCounted
## Utility functions for orbital calculations

# === Constants ===
const DAYS_PER_YEAR: float = 365.25
const HOURS_PER_DAY: float = 24.0
const MINUTES_PER_HOUR: float = 60.0
const SECONDS_PER_MINUTE: float = 60.0


## Convert simulation time (seconds) to formatted string
static func format_simulation_time(seconds: float) -> String:
	if seconds < 0:
		return "-" + _format_time_absolute(-seconds)
	return _format_time_absolute(seconds)


## Format time interval with appropriate units
static func _format_time_absolute(seconds: float) -> String:
	if seconds < 60:
		return "%.1fs" % seconds
	elif seconds < 3600:
		var minutes = int(seconds / 60)
		var secs = int(seconds) % 60
		return "%dm %02ds" % [minutes, secs]
	elif seconds < 86400:
		var hours = int(seconds / 3600)
		var minutes = int(seconds / 60) % 60
		return "%dh %02dm" % [hours, minutes]
	else:
		var days = int(seconds / 86400)
		var hours = int(seconds / 3600) % 24
		if days > 0:
			return "%dd %dh" % [days, hours]
		return "%.1fd" % (seconds / 86400)


## Format distance with appropriate units (meters)
static func format_distance(meters: float) -> String:
	if absf(meters) < 1000:
		return "%.0f m" % meters
	elif absf(meters) < 1_000_000:
		return "%.1f km" % (meters / 1000.0)
	elif absf(meters) < 1_500_000_000:
		return "%.2f Mm" % (meters / 1_000_000.0)
	else:
		return "%.4f AU" % (meters / OrbitalConstants.AU)


## Format velocity (m/s)
static func format_velocity(mps: float) -> String:
	if absf(mps) < 1:
		return "%.2f m/s" % mps
	elif absf(mps) < 1000:
		return "%.1f m/s" % mps
	else:
		return "%.2f km/s" % (mps / 1000.0)


## Format mass with appropriate units (kg)
static func format_mass(kg: float) -> String:
	if absf(kg) < 1:
		return "%.2f kg" % kg
	elif absf(kg) < 1000:
		return "%.1f kg" % kg
	elif absf(kg) < 1_000_000:
		return "%.2f t" % (kg / 1000.0)
	else:
		return "%.3f kt" % (kg / 1_000_000.0)


## Format percentage
static func format_percent(value: float, decimals: int = 0) -> String:
	return ("%." + str(decimals) + "f%%") % (value * 100.0)


## Clamp value to range
static func clamp_range(value: float, min_val: float, max_val: float) -> float:
	return clampf(value, min_val, max_val)


## Linear interpolation
static func lerp_float(a: float, b: float, t: float) -> float:
	return lerpf(a, b, t)


## Angle difference (shortest path)
static func angle_difference(from: float, to: float) -> float:
	var diff = fmod(to - from + TAU, TAU)
	if diff > PI:
		diff -= TAU
	return diff