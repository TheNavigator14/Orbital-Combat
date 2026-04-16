class_name ContactDisplayPanel
extends PanelContainer
## Displays detected sensor contacts with thermal analysis
## CRT-style panel showing unknown contacts and their signatures

signal contact_selected(contact: SensorManager.SensorContact)
signal investigation_requested(contact: SensorManager.SensorContact)

# === Style Settings ===
const CRT_GREEN := Color(0.2, 1.0, 0.4)
const CRT_AMBER := Color(1.0, 0.6, 0.2)
const CRT_DIM := Color(0.15, 0.35, 0.25)
const CRT_BRIGHT := Color(0.5, 1.0, 0.6)
const CRT_ALERT := Color(1.0, 0.3, 0.2)

# === References ===
var sensor_manager: SensorManager = null
var selected_contact: SensorManager.SensorContact = null
var contacts_list: VBoxContainer = null
var details_panel: PanelContainer = null
var no_contacts_label: Label = null

# === Style ===
var base_style: StyleBoxFlat
var selected_style: StyleBoxFlat
var hover_style: StyleBoxFlat

func _ready() -> void:
	_setup_styles()
	_create_ui()


func _setup_styles() -> void:
	# Base style - dark CRT background
	base_style = StyleBoxFlat.new()
	base_style.bg_color = Color(0.02, 0.08, 0.04, 0.9)
	base_style.border_color = CRT_GREEN * 0.5
	base_style.border_width_left = 2
	base_style.border_width_right = 2
	base_style.border_width_top = 2
	base_style.border_width_bottom = 2
	base_style.corner_radius_top_left = 4
	base_style.corner_radius_top_right = 4
	base_style.corner_radius_bottom_left = 4
	base_style.corner_radius_bottom_right = 4
	
	# Selected style - brighter border
	selected_style = base_style.duplicate()
	selected_style.border_color = CRT_BRIGHT
	
	# Hover style
	hover_style = base_style.duplicate()
	hover_style.border_color = CRT_GREEN


func _create_ui() -> void:
	# Title bar
	var title_bar = HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 28)
	add_child(title_bar)
	
	var title = Label.new()
	title.text = "  SENSOR CONTACTS"
	title.add_theme_color_override("font_color", CRT_GREEN)
	title.add_theme_stylebox_override("normal", _create_label_style())
	title_bar.add_child(title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer)
	
	# Status indicator
	var status = Label.new()
	status.name = "status_label"
	status.text = "[PASSIVE]"
	status.add_theme_color_override("font_color", CRT_GREEN)
	status.add_theme_stylebox_override("normal", _create_label_style())
	title_bar.add_child(status)
	
	# Content area
	var content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(content)
	
	# No contacts message
	no_contacts_label = Label.new()
	no_contacts_label.text = "\n\n  NO CONTACTS\n  DETECTED"
	no_contacts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_contacts_label.add_theme_color_override("font_color", CRT_DIM)
	no_contacts_label.add_theme_stylebox_override("normal", _create_label_style())
	no_contacts_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(no_contacts_label)
	
	# Scroll container for contacts
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.visible = false
	content.add_child(scroll)
	
	contacts_list = VBoxContainer.new()
	contacts_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(contacts_list)
	
	# Details panel (bottom)
	details_panel = _create_details_panel()
	details_panel.visible = false
	content.add_child(details_panel)


func _create_label_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	return style


func _create_details_panel() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 120)
	panel.set("theme_override_styles/panel", base_style.duplicate())
	
	var container = VBoxContainer.new()
	panel.add_child(container)
	
	# Contact header
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 24)
	container.add_child(header)
	
	var name_label = Label.new()
	name_label.name = "contact_name"
	name_label.text = "CONTACT"
	name_label.add_theme_color_override("font_color", CRT_BRIGHT)
	header.add_child(name_label)
	
	header.add_child(_create_spacer())
	
	var dist_label = Label.new()
	dist_label.name = "distance_label"
	dist_label.text = "---"
	dist_label.add_theme_color_override("font_color", CRT_GREEN)
	header.add_child(dist_label)
	
	# Thermal analysis
	var thermal_box = HBoxContainer.new()
	thermal_box.custom_minimum_size = Vector2(0, 20)
	container.add_child(thermal_box)
	
	var thermal_label = Label.new()
	thermal_label.text = "THERMAL: "
	thermal_label.add_theme_color_override("font_color", CRT_DIM)
	thermal_box.add_child(thermal_label)
	
	var thermal_value = Label.new()
	thermal_value.name = "thermal_label"
	thermal_value.text = "---"
	thermal_value.add_theme_color_override("font_color", CRT_GREEN)
	thermal_box.add_child(thermal_value)
	
	thermal_box.add_child(_create_spacer())
	
	var class_label = Label.new()
	class_label.text = "CLASS: "
	class_label.add_theme_color_override("font_color", CRT_DIM)
	thermal_box.add_child(class_label)
	
	var class_value = Label.new()
	class_value.name = "class_label"
	class_value.text = "??? (0%)"
	class_value.add_theme_color_override("font_color", CRT_AMBER)
	thermal_box.add_child(class_value)
	
	# Bearing and intercept
	var tactical_box = HBoxContainer.new()
	tactical_box.custom_minimum_size = Vector2(0, 20)
	container.add_child(tactical_box)
	
	var bearing_label = Label.new()
	bearing_label.text = "BRG: "
	bearing_label.add_theme_color_override("font_color", CRT_DIM)
	tactical_box.add_child(bearing_label)
	
	var bearing_value = Label.new()
	bearing_value.name = "bearing_label"
	bearing_value.text = "---"
	bearing_value.add_theme_color_override("font_color", CRT_GREEN)
	tactical_box.add_child(bearing_value)
	
	tactical_box.add_child(_create_spacer())
	
	var intercept_label = Label.new()
	intercept_label.text = "T-I: "
	intercept_label.add_theme_color_override("font_color", CRT_DIM)
	tactical_box.add_child(intercept_label)
	
	var intercept_value = Label.new()
	intercept_value.name = "intercept_label"
	intercept_value.text = "---"
	intercept_value.add_theme_color_override("font_color", CRT_AMBER)
	tactical_box.add_child(intercept_value)
	
	# Trend indicator
	var trend_box = HBoxContainer.new()
	trend_box.custom_minimum_size = Vector2(0, 20)
	container.add_child(trend_box)
	
	var trend_label = Label.new()
	trend_label.text = "HEAT TREND: "
	trend_label.add_theme_color_override("font_color", CRT_DIM)
	trend_box.add_child(trend_label)
	
	var trend_value = Label.new()
	trend_value.name = "trend_label"
	trend_value.text = "STABLE"
	trend_box.add_child(trend_value)
	
	return panel


func _create_spacer() -> Control:
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func initialize(sensor_mgr: SensorManager) -> void:
	sensor_manager = sensor_mgr
	
	# Connect to sensor manager signals
	if sensor_manager.has_signal("thermal_contact_detected"):
		sensor_manager.thermal_contact_detected.connect(_on_thermal_contact_detected)
	if sensor_manager.has_signal("contact_updated"):
		sensor_manager.contact_updated.connect(_on_contact_updated)
	if sensor_manager.has_signal("contact_lost"):
		sensor_manager.contact_lost.connect(_on_contact_lost)


func _on_thermal_contact_detected(contact: SensorManager.SensorContact) -> void:
	# Create UI entry for new contact
	_add_contact_entry(contact)
	_update_contact_list()
	_update_no_contacts_visibility()


func _on_contact_updated(contact: SensorManager.SensorContact) -> void:
	_update_contact_entry(contact)
	
	if selected_contact == contact:
		_update_details_panel(contact)


func _on_contact_lost(contact: SensorManager.SensorContact) -> void:
	_remove_contact_entry(contact)
	_update_contact_list()
	_update_no_contacts_visibility()
	
	if selected_contact == contact:
		selected_contact = null
		details_panel.visible = false


func _add_contact_entry(contact: SensorManager.SensorContact) -> void:
	var entry = _create_contact_entry(contact)
	contacts_list.add_child(entry)


func _create_contact_entry(contact: SensorManager.SensorContact) -> PanelContainer:
	var entry = PanelContainer.new()
	entry.custom_minimum_size = Vector2(0, 50)
	entry.set("theme_override_styles/panel", base_style.duplicate())
	
	var container = VBoxContainer.new()
	entry.add_child(container)
	
	# Header row
	var header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 22)
	container.add_child(header)
	
	# Contact marker (unknown contact = question mark)
	var marker = Label.new()
	marker.name = "marker"
	marker.text = " ? "
	marker.add_theme_color_override("font_color", CRT_AMBER)
	header.add_child(marker)
	
	# Contact name
	var name = Label.new()
	name.name = "name"
	name.text = "UNKNOWN CONTACT"
	name.add_theme_color_override("font_color", CRT_GREEN)
	header.add_child(name)
	
	header.add_child(_create_spacer())
	
	# Distance
	var dist = Label.new()
	dist.name = "distance"
	dist.text = contact.get_distance_string()
	dist.add_theme_color_override("font_color", CRT_GREEN)
	header.add_child(dist)
	
	# Signal strength bar
	var sig_row = HBoxContainer.new()
	sig_row.custom_minimum_size = Vector2(0, 20)
	container.add_child(sig_row)
	
	var sig_label = Label.new()
	sig_label.text = "SIG: "
	sig_label.add_theme_color_override("font_color", CRT_DIM)
	sig_row.add_child(sig_label)
	
	var sig_bar = Label.new()
	sig_bar.name = "signal"
	sig_bar.text = _format_signal_bar(contact.thermal_signal_strength)
	sig_bar.add_theme_color_override("font_color", _signal_color(contact.thermal_signal_strength))
	sig_row.add_child(sig_bar)
	
	sig_row.add_child(_create_spacer())
	
	# Bearing
	var brg = Label.new()
	brg.name = "bearing"
	brg.text = contact.get_bearing_string()
	brg.add_theme_color_override("font_color", CRT_DIM)
	sig_row.add_child(brg)
	
	# Store reference
	entry.set_meta("contact", contact)
	
	return entry


func _format_signal_bar(strength: float) -> String:
	## Format signal strength as visual bar
	var filled = int(strength * 10)
	var bar = "["
	for i in range(10):
		if i < filled:
			bar += "|"
		else:
			bar += "."
	bar += "]"
	return bar


func _signal_color(strength: float) -> Color:
	if strength > 0.7:
		return CRT_BRIGHT
	elif strength > 0.3:
		return CRT_GREEN
	else:
		return CRT_AMBER


func _update_contact_entry(contact: SensorManager.SensorContact) -> void:
	# Find entry by contact reference
	for i in range(contacts_list.get_child_count()):
		var entry = contacts_list.get_child(i)
		if entry.get_meta("contact") == contact:
			_update_entry_values(entry, contact)
			break


func _update_entry_values(entry: PanelContainer, contact: SensorManager.SensorContact) -> void:
	# Update distance
	var distance_label = entry.get_node_or_null("distance")
	if distance_label:
		distance_label.text = contact.get_distance_string()
	
	# Update signal bar
	var signal_label = entry.get_node_or_null("signal")
	if signal_label:
		signal_label.text = _format_signal_bar(contact.thermal_signal_strength)
		signal_label.add_theme_color_override("font_color", _signal_color(contact.thermal_signal_strength))
	
	# Update bearing
	var bearing_label = entry.get_node_or_null("bearing")
	if bearing_label:
		bearing_label.text = contact.get_bearing_string()
	
	# Update marker based on status
	var marker = entry.get_node_or_null("marker")
	if marker:
		match contact.status:
			SensorManager.ContactStatus.UNKNOWN:
				marker.text = " ? "
				marker.add_theme_color_override("font_color", CRT_AMBER)
			SensorManager.ContactStatus.INVESTIGATING:
				marker.text = " ~ "
				marker.add_theme_color_override("font_color", CRT_GREEN)
			SensorManager.ContactStatus.IDENTIFIED:
				marker.text = " ! "
				marker.add_theme_color_override("font_color", CRT_BRIGHT)


func _remove_contact_entry(contact: SensorManager.SensorContact) -> void:
	for i in range(contacts_list.get_child_count()):
		var entry = contacts_list.get_child(i)
		if entry.get_meta("contact") == contact:
			contacts_list.remove_child(entry)
			entry.queue_free()
			break


func _update_contact_list() -> void:
	# Update status indicator
	var status_label = get_node_or_null("status_label")
	if status_label and sensor_manager:
		match sensor_manager.active_scan_mode:
			SensorManager.SensorMode.PASSIVE:
				status_label.text = "[PASSIVE]"
				status_label.add_theme_color_override("font_color", CRT_GREEN)
			SensorManager.SensorMode.RADAR:
				status_label.text = "[RADAR]"
				status_label.add_theme_color_override("font_color", CRT_ALERT)
			SensorManager.SensorMode.ACTIVE:
				status_label.text = "[ACTIVE]"
				status_label.add_theme_color_override("font_color", CRT_AMBER)


func _update_no_contacts_visibility() -> void:
	var has_contacts = contacts_list.get_child_count() > 0
	no_contacts_label.visible = not has_contacts
	contacts_list.get_parent().visible = has_contacts


func _update_details_panel(contact: SensorManager.SensorContact) -> void:
	details_panel.visible = true
	
	# Update contact name
	var name_label = details_panel.get_node_or_null("contact_name")
	if name_label:
		name_label.text = contact.get_display_name()
	
	# Update distance
	var dist_label = details_panel.get_node_or_null("distance_label")
	if dist_label:
		dist_label.text = contact.get_distance_string()
	
	# Update thermal value
	var thermal_label = details_panel.get_node_or_null("thermal_label")
	if thermal_label:
		thermal_label.text = "%.0f%%" % (contact.thermal_signal_strength * 100.0)
		thermal_label.add_theme_color_override("font_color", _signal_color(contact.thermal_signal_strength))
	
	# Update class
	var class_label = details_panel.get_node_or_null("class_label")
	if class_label:
		class_label.text = "%s (%.0f%%)" % [contact.get_ship_class_string(), contact.ship_class_confidence * 100.0]
	
	# Update bearing
	var bearing_label = details_panel.get_node_or_null("bearing_label")
	if bearing_label:
		bearing_label.text = contact.get_bearing_string()
	
	# Update intercept time
	var intercept_label = details_panel.get_node_or_null("intercept_label")
	if intercept_label:
		intercept_label.text = contact.get_intercept_string()
	
	# Update trend
	var trend_label = details_panel.get_node_or_null("trend_label")
	if trend_label:
		match contact.get_heat_trend():
			1:
				trend_label.text = "RISING"
				trend_label.add_theme_color_override("font_color", CRT_ALERT)
			-1:
				trend_label.text = "FALLING"
				trend_label.add_theme_color_override("font_color", CRT_GREEN)
			_:
				trend_label.text = "STABLE"
				trend_label.add_theme_color_override("font_color", CRT_DIM)


func _process(delta: float) -> void:
	# Update contact analysis periodically
	if sensor_manager == null:
		return
	
	var contacts = sensor_manager.get_all_detected_contacts()
	for contact in contacts:
		if contact.is_thermally_detected:
			contact.update_contact_age()
			contact.analyze_heat_signature()
			contact.update_intercept_data()
			_update_contact_entry(contact)
	
	# Update details if contact selected
	if selected_contact:
		_update_details_panel(selected_contact)