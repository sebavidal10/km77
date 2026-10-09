class_name HUD
extends CanvasLayer

@export_group("Target")
## The vehicle node to observe for telemetry, fuel, and trip metrics.
@export var target_van: Van

@onready var speed_value_label: Label = %SpeedValue
@onready var drift_badge: Label = %DriftBadge
@onready var route_label: Label = %RouteLabel
@onready var fuel_bar: ProgressBar = %FuelBar
@onready var fuel_percent_label: Label = %FuelPercent
@onready var low_fuel_warning: Label = %LowFuelWarning

var _blink_timer: float = 0.0
var _blink_visible: bool = true

func _ready() -> void:
	_find_van()
	_connect_van_signals()
	_update_initial_display()

func _process(delta: float) -> void:
	if not target_van:
		_find_van()
		if target_van:
			_connect_van_signals()
		return

	# Handle low fuel warning blinking
	_process_low_fuel_warning(delta)

	# Direct sync fallback to ensure 100% visual responsiveness
	_sync_van_state()

func _find_van() -> void:
	if target_van:
		return
	var parent := get_parent()
	if parent:
		var van_candidate := parent.get_node_or_null("Van") as Van
		if van_candidate:
			target_van = van_candidate
			return
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Van:
		target_van = nodes[0] as Van

func _connect_van_signals() -> void:
	if not target_van:
		return
	if not target_van.speed_updated.is_connected(_on_speed_updated):
		target_van.speed_updated.connect(_on_speed_updated)
	if not target_van.fuel_changed.is_connected(_on_fuel_changed):
		target_van.fuel_changed.connect(_on_fuel_changed)
	if not target_van.distance_updated.is_connected(_on_distance_updated):
		target_van.distance_updated.connect(_on_distance_updated)
	if not target_van.drift_state_changed.is_connected(_on_drift_state_changed):
		target_van.drift_state_changed.connect(_on_drift_state_changed)

func _update_initial_display() -> void:
	if target_van:
		_sync_van_state()
	else:
		_on_speed_updated(0.0)
		_on_fuel_changed(100.0, 100.0)
		_on_distance_updated(0.0, 85.0)
		_on_drift_state_changed(false)

func _sync_van_state() -> void:
	if not target_van:
		return
	_on_speed_updated(target_van.current_speed_kmh)
	_on_fuel_changed(target_van.current_fuel, target_van.max_fuel)
	_on_distance_updated(target_van.distance_traveled_meters, target_van.current_kilometer)
	_on_drift_state_changed(target_van.is_actively_drifting)

func _process_low_fuel_warning(delta: float) -> void:
	if not target_van or not low_fuel_warning:
		return

	if target_van.current_fuel <= 0.0:
		low_fuel_warning.visible = true
		low_fuel_warning.text = "[ NO FUEL - ENGINE STALLED ]"
		low_fuel_warning.modulate = Color(1.0, 0.2, 0.2, 1.0)
	elif target_van.current_fuel < 20.0:
		_blink_timer += delta
		if _blink_timer >= 0.35:
			_blink_timer = 0.0
			_blink_visible = !_blink_visible
			low_fuel_warning.visible = _blink_visible
		low_fuel_warning.text = "[ ! LOW FUEL ! ]"
		low_fuel_warning.modulate = Color(1.0, 0.35, 0.2, 1.0)
	else:
		low_fuel_warning.visible = false

func _on_speed_updated(speed_kmh: float) -> void:
	if speed_value_label:
		speed_value_label.text = "%03d" % int(round(speed_kmh))

func _on_fuel_changed(current: float, max_val: float) -> void:
	var percent: float = (current / max_val) * 100.0 if max_val > 0.0 else 0.0
	if fuel_bar:
		fuel_bar.max_value = max_val
		fuel_bar.value = current
	if fuel_percent_label:
		fuel_percent_label.text = "%3.0f%%" % percent

func _on_distance_updated(_meters: float, current_km: float) -> void:
	if route_label:
		route_label.text = "ROUTE 77  |  KM %4.1f ──> 77.0" % current_km

func _on_drift_state_changed(is_active: bool) -> void:
	if drift_badge:
		if is_active:
			drift_badge.modulate = Color(1.0, 0.68, 0.15, 1.0) # Vibrant active amber
		else:
			drift_badge.modulate = Color(0.4, 0.45, 0.48, 0.35) # Dim technical standby watermark
