class_name CockpitCustomizationPanel
extends Control

## Panel for ship customization - loadouts, upgrades, and appearance
## Part of Phase 5: Polish - Ship customization

signal loadout_changed(loadout_name: String)
signal upgrade_changed(upgrade_name: String, enabled: bool)
signal panel_closed()
signal customization_applied()

# === CRT Colors ===
const CRT_GREEN = Color(0.2, 1.0, 0.4)
const CRT_GREEN_DIM = Color(0.1, 0.5, 0.2)
const CRT_GREEN_BRIGHT = Color(0.4, 1.0, 0.6)
const CRT_AMBER = Color(1.0, 0.6, 0.2)
const CRT_RED = Color(1.0, 0.3, 0.2)

# === State ===
var is_visible_panel: bool = false
var current_loadout: String = "Standard"
var selected_category: int = 0  # 0=Weapons, 1=Sensors, 2=Propulsion, 3=Appearance
var credits_available: int = 1000

# === Loadout Definitions ===
const LOADOUTS: Dictionary = {
	"Standard": {
		"missiles": 4,
		"pdc_count": 1,
		"thermal_sensor": 1.0,
		"radar_range": 1.0,
		"thrust_mult": 1.0,
		"fuel_capacity": 1.0,
		"description": "Balanced combat configuration"
	},
	"Heavy Striker": {
		"missiles": 8,
		"pdc_count": 1,
		"thermal_sensor": 0.8,
		"radar_range": 0.9,
		"thrust_mult": 0.7,
		"fuel_capacity": 1.0,
		"description": "Missile-focused, reduced maneuverability"
	},
	"Scout": {
		"missiles": 2,
		"pdc_count": 0,
		"thermal_sensor": 1.5,
		"radar_range": 1.5,
		"thrust_mult": 1.3,
		"fuel_capacity": 1.5,
		"description": "High-speed reconnaissance setup"
	},
	"Interdictor": {
		"missiles": 6,
		"pdc_count": 2,
		"thermal_sensor": 1.2,
		"radar_range": 1.2,
		"thrust_mult": 0.8,
		"fuel_capacity": 0.8,
		"description": "Point defense emphasis"
	}
}

# === Upgrade Definitions ===
const UPGRADES: Dictionary = {
	"extended_fuel_tanks": {
		"display_name": "Extended Fuel Tanks",
		"category": 2,  # Propulsion
		"cost": 200,
		"stat_mults": {"fuel_capacity": 1.5},
		"description": "+50% fuel capacity"
	},
	"advanced_sensors": {
		"display_name": "Advanced Sensors",
		"category": 1,  # Sensors
		"cost": 300,
		"stat_mults": {"thermal_sensor": 1.3, "radar_range": 1.3},
		"description": "+30% sensor range"
	},
	"stealth_coating": {
		"display_name": "Stealth Coating",
		"category": 3,  # Appearance/Stealth
		"cost": 400,
		"stat_mults": {"signature_mult": 0.5},
		"description": "-50% detection signature"
	},
	"reinforced_armor": {
		"display_name": "Reinforced Armor",
		"category": 0,  # Weapons
		"cost": 350,
		"stat_mults": {"max_health": 1.5},
		"description": "+50% hull integrity"
	},
	"overclocked_thrusters": {
		"display_name": "Overclocked Thrusters",
		"category": 2,  # Propulsion
		"cost": 250,
		"stat_mults": {"thrust_mult": 1.2},
		"description": "+20% thrust power"
	},
	"countermeasure_boost": {
		"display_name": "Countermeasure Boost",
		"category": 1,  # Sensors
		"cost": 200,
		"stat_mults": {"cm_capacity": 2.0},
		"description": "+100% countermeasures"
	}
}

# === Node References ===
@onready var panel_container: PanelContainer = $PanelContainer
@onready var category_tabs: TabContainer = $PanelContainer/VBox/CategoryTabs
@onready var weapons_tab: VBoxContainer = $PanelContainer/VBox/CategoryTabs/WeaponsTab
@onready var sensors_tab: VBoxContainer = $PanelContainer/VBox/CategoryTabs/SensorsTab
@onready var propulsion_tab: VBoxContainer = $PanelContainer/VBox/CategoryTabs/PropulsionTab
@onready var appearance_tab: VBoxContainer = $PanelContainer/VBox/CategoryTabs/AppearanceTab
@onready var loadout_container: VBoxContainer = $PanelContainer/VBox/LoadoutSection
@onready var loadout_selector: OptionButton = $PanelContainer/VBox/LoadoutSection/LoadoutSelector
@onready var loadout_desc: Label = $PanelContainer/VBox/LoadoutSection/LoadoutDesc
@onready var stats_container: VBoxContainer = $PanelContainer/VBox/StatsDisplay/StatsContainer
@onready var credits_label: Label = $PanelContainer/VBox/CreditsDisplay/CreditsValue
@onready var apply_button: Button = $PanelContainer/VBox/ButtonRow/ApplyButton
@onready var close_button: Button = $PanelContainer/VBox/ButtonRow/CloseButton
@onready var toggle_button: Button = $ToggleButton

# === Dynamic Upgrade UI ===
var upgrade_checkboxes: Dictionary = {}  # upgrade_name -> CheckBox

func _ready() -> void:
	_apply_crt_theme()
	_setup_loadouts()
	_setup_upgrades()
	_setup_connections()
	_update_display()

func _apply_crt_theme() -> void:
	# Apply CRT styling to panel
	panel_container.add_theme_stylebox_override("panel", _get_crt_panel_style())
	
	# Apply to labels
	if loadout_desc:
		loadout_desc.add_theme_color_override("font_color", CRT_GREEN)
		loadout_desc.add_theme_color_override("font_shadow_color", Color(0.1, 0.5, 0.2, 0.3))
	
	if credits_label:
		credits_label.add_theme_color_override("font_color", CRT_AMBER)

func _get_crt_panel_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.05, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = CRT_GREEN_DIM
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _setup_loadouts() -> void:
	# Populate loadout dropdown
	loadout_selector.clear()
	for loadout_name in LOADOUTS.keys():
		loadout_selector.add_item(loadout_name)

func _setup_upgrades() -> void:
	# Create upgrade checkboxes for each category tab
	for upgrade_name in UPGRADES.keys():
		var upgrade = UPGRADES[upgrade_name]
		var checkbox = _create_upgrade_checkbox(upgrade_name, upgrade)
		
		# Add to appropriate tab
		match upgrade.category:
			0:  # Weapons
				weapons_tab.add_child(checkbox)
			1:  # Sensors
				sensors_tab.add_child(checkbox)
			2:  # Propulsion
				propulsion_tab.add_child(checkbox)
			3:  # Appearance
				appearance_tab.add_child(checkbox)
		
		upgrade_checkboxes[upgrade_name] = checkbox

func _create_upgrade_checkbox(upgrade_name: String, upgrade_data: Dictionary) -> CheckBox:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	
	var checkbox = CheckBox.new()
	checkbox.text = upgrade_data.display_name
	checkbox.metadata = upgrade_name  # Store upgrade name for reference
	
	# Set initial state
	checkbox.button_pressed = false
	
	# Connect signal
	checkbox.toggled.connect(_on_upgrade_toggled)
	
	# Create cost label
	var cost_label = Label.new()
	cost_label.text = "[%d CR]" % upgrade_data.cost
	cost_label.add_theme_color_override("font_color", CRT_AMBER)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	# Create description label
	var desc_label = Label.new()
	desc_label.text = upgrade_data.description
	desc_label.add_theme_color_override("font_color", CRT_GREEN_DIM)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	
	container.add_child(checkbox)
	container.add_child(cost_label)
	container.add_child(desc_label)
	
	# Store checkbox reference
	container.metadata = checkbox
	
	return checkbox

func _setup_connections() -> void:
	loadout_selector.item_selected.connect(_on_loadout_selected)
	category_tabs.tab_changed.connect(_on_category_changed)
	apply_button.pressed.connect(_on_apply_changes)
	close_button.pressed.connect(_on_close_panel)
	toggle_button.pressed.connect(_on_toggle_panel)

func _on_loadout_selected(index: int) -> void:
	var loadouts = LOADOUTS.keys()
	if index < loadouts.size():
		current_loadout = loadouts[index]
		var loadout = LOADOUTS[current_loadout]
		loadout_desc.text = loadout.description
		_update_stats_display()

func _on_category_changed(tab_index: int) -> void:
	selected_category = tab_index

func _on_upgrade_toggled(button_pressed: bool) -> void:
	var checkbox: CheckBox = get_parent()
	if not checkbox or checkbox is not CheckBox:
		checkbox = self
	if not checkbox.metadata:
		return
	
	var upgrade_name = checkbox.metadata as String
	if not (upgrade_name in UPGRADES):
		return
	
	var upgrade = UPGRADES[upgrade_name]
	var cost = upgrade.cost
	
	# Update credits
	if button_pressed:
		# Purchasing upgrade
		if credits_available >= cost:
			credits_available -= cost
			upgrades[upgrade_name] = true
			upgrade_changed.emit(upgrade_name, true)
		else:
			# Can't afford - revert
			checkbox.set_pressed_no_signal(false)
			return
	else:
		# Removing upgrade - refund
		credits_available += cost
		upgrades[upgrade_name] = false
		upgrade_changed.emit(upgrade_name, false)
	
	_update_credits_display()
	_update_stats_display()

func _update_display() -> void:
	_update_credits_display()
	_update_loadout_display()
	_update_stats_display()
	_update_upgrade_display()

func _update_credits_display() -> void:
	if credits_label:
		credits_label.text = "%d CR" % credits_available

func _update_loadout_display() -> void:
	# Find and select current loadout in dropdown
	var loadouts = LOADOUTS.keys()
	var index = loadouts.find(current_loadout)
	if index >= 0:
		loadout_selector.selected = index
	
	if loadout_desc and current_loadout in LOADOUTS:
		loadout_desc.text = LOADOUTS[current_loadout].description

func _update_stats_display() -> void:
	# Clear existing stats
	for child in stats_container.get_children():
		child.queue_free()
	
	# Get base loadout stats
	var base_stats = _get_current_stats()
	
	# Add stat labels
	_add_stat_row("MISSILES", str(base_stats.missiles))
	_add_stat_row("PDCs", str(base_stats.pdc_count))
	_add_stat_row("THERMAL SENS", "%.1fx" % base_stats.thermal_sensor)
	_add_stat_row("RADAR RNG", "%.1fx" % base_stats.radar_range)
	_add_stat_row("THRUST", "%.1fx" % base_stats.thrust_mult)
	_add_stat_row("FUEL CAP", "%.1fx" % base_stats.fuel_capacity)
	
	if "max_health" in base_stats:
		_add_stat_row("ARMOR", "%.0f" % base_stats.max_health)
	
	if "signature_mult" in base_stats:
		_add_stat_row("STEALTH", "%.0f%%" % (base_stats.signature_mult * 100))

func _add_stat_row(label_text: String, value_text: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", CRT_GREEN_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var value = Label.new()
	value.text = value_text
	value.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	
	row.add_child(label)
	row.add_child(value)
	stats_container.add_child(row)

func _update_upgrade_display() -> void:
	# Update upgrade checkbox states and affordability
	for upgrade_name in upgrade_checkboxes.keys():
		var checkbox = upgrade_checkboxes[upgrade_name]
		var upgrade = UPGRADES[upgrade_name]
		var cost = upgrade.cost
		
		# Update checkbox state
		if checkbox.button_pressed != upgrades[upgrade_name]:
			checkbox.set_pressed_no_signal(upgrades[upgrade_name])
		
		# Update appearance based on affordability
		if not upgrades[upgrade_name] and credits_available < cost:
			checkbox.modulate = Color(0.5, 0.5, 0.5)  # Grayed out if can't afford
		else:
			checkbox.modulate = Color(1.0, 1.0, 1.0)

func _get_current_stats() -> Dictionary:
	## Calculate current stats including loadout and upgrades
	var stats = LOADOUTS[current_loadout].duplicate()
	
	# Apply upgrade stat multipliers
	for upgrade_name in upgrades.keys():
		if upgrades[upgrade_name] and upgrade_name in UPGRADES:
			var stat_mults = UPGRADES[upgrade_name].stat_mults
			for stat_name in stat_mults.keys():
				if stat_name in stats:
					stats[stat_name] *= stat_mults[stat_name]
				else:
					stats[stat_name] = stat_mults[stat_name]
	
	return stats

func get_full_loadout_config() -> Dictionary:
	## Get complete loadout configuration for applying to ship
	var config = _get_current_stats()
	config["loadout_name"] = current_loadout
	
	# Add list of active upgrades
	var active_upgrades: Array = []
	for upgrade_name in upgrades.keys():
		if upgrades[upgrade_name]:
			active_upgrades.append(upgrade_name)
	config["active_upgrades"] = active_upgrades
	
	return config

func _on_apply_changes() -> void:
	# Get full configuration and emit
	var config = get_full_loadout_config()
	loadout_changed.emit(current_loadout)
	customization_applied.emit(config)
	print("CockpitCustomization: Applied loadout '%s' with upgrades" % current_loadout)
	
	# Visual feedback
	_apply_button_press_effect()

func _apply_button_press_effect() -> void:
	# Brief color flash on apply
	var original_color = apply_button.get_theme_color("font_color", "Button")
	apply_button.add_theme_color_override("font_color", CRT_GREEN_BRIGHT)
	
	await get_tree().create_timer(0.2).timeout
	apply_button.add_theme_color_override("font_color", original_color)

func _on_close_panel() -> void:
	panel_container.visible = false
	is_visible_panel = false
	panel_closed.emit()

func _on_toggle_panel() -> void:
	is_visible_panel = not is_visible_panel
	panel_container.visible = is_visible_panel
	
	if is_visible_panel:
		_update_display()

func set_credits(amount: int) -> void:
	## Set available credits (called from game manager)
	credits_available = amount
	if is_visible_panel:
		_update_credits_display()
		_update_upgrade_display()

func reset_upgrades() -> void:
	## Reset all upgrades and refund credits
	for upgrade_name in upgrades.keys():
		if upgrades[upgrade_name]:
			var cost = UPGRADES[upgrade_name].cost
			credits_available += cost
			upgrades[upgrade_name] = false
			if upgrade_name in upgrade_checkboxes:
				upgrade_checkboxes[upgrade_name].set_pressed_no_signal(false)
	
	if is_visible_panel:
		_update_credits_display()
		_update_upgrade_display()
		_update_stats_display()