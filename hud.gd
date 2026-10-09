class_name HUD
extends CanvasLayer

signal screen_faded_to_black
signal screen_faded_from_black

const RadioManager = preload("res://radio_manager.gd")
const Van = preload("res://van.gd")

@export_group("Target")
## The vehicle node to observe for telemetry, fuel, and trip metrics.
@export var target_van: Van

@onready var speed_value_label: Label = %SpeedValue
@onready var drift_badge: Label = %DriftBadge
@onready var route_label: Label = %RouteLabel
@onready var fuel_bar: ProgressBar = %FuelBar
@onready var fuel_percent_label: Label = %FuelPercent
@onready var low_fuel_warning: Label = %LowFuelWarning
@onready var dispatch_panel: PanelContainer = %DispatchPanel
@onready var dispatch_label: Label = %DispatchText
@onready var fade_overlay: ColorRect = %ScreenFadeOverlay
@onready var interaction_panel: PanelContainer = %InteractionPanel
@onready var interaction_prompt_label: Label = %InteractionPromptLabel
@onready var scavenge_progress_bar: ProgressBar = %ScavengeProgressBar

var _blink_timer: float = 0.0
var _blink_visible: bool = true
var _success_message_timer: float = 0.0

# Radio dispatch typewriter & fade state
var _target_dispatch_text: String = ""
var _displayed_chars: int = 0
var _typewriter_timer: float = 0.0
var _is_typing: bool = false
var _is_displaying_dispatch: bool = false
var _dispatch_display_timer: float = 0.0
var _dispatch_hold_duration: float = 0.0
var _cursor_blink_timer: float = 0.0
var _cursor_visible: bool = true

# Screen fade to black state
var _fade_target_alpha: float = 0.0
var _fade_speed: float = 0.5
var _is_fading: bool = false

func _ready() -> void:
	add_to_group("hud")
	_find_van()
	_connect_van_signals()
	_connect_radio_manager()
	_update_initial_display()
	if dispatch_panel:
		dispatch_panel.visible = false
		dispatch_panel.modulate.a = 0.0
	if fade_overlay:
		fade_overlay.visible = false
		fade_overlay.modulate.a = 0.0
	if interaction_panel:
		interaction_panel.visible = false

func _process(delta: float) -> void:
	if not target_van:
		_find_van()
		if target_van:
			_connect_van_signals()

	# Handle status and warning blinking
	_process_status_warnings(delta)

	# Handle radio dispatch typewriter effect and smooth fade
	_process_radio_dispatch(delta)

	# Handle screen fade to black / fade from black
	_process_screen_fade(delta)

	# Handle scavenge interaction message timer
	_process_interaction_timer(delta)

	# Direct sync fallback to ensure 100% visual responsiveness
	_sync_van_state()

func _process_interaction_timer(delta: float) -> void:
	if _success_message_timer > 0.0:
		_success_message_timer -= delta
		if _success_message_timer <= 0.0:
			_success_message_timer = 0.0
			if interaction_panel:
				interaction_panel.visible = false

## Displays the scavenge interaction prompt and current progress ratio (0.0 to 1.0).
func show_scavenge_prompt(prompt_text: String = "HOLD [E] TO SCAVENGE FUEL / REPAIR", progress_ratio: float = 0.0) -> void:
	if not interaction_panel:
		return
	if _success_message_timer > 0.0:
		return
	interaction_panel.visible = true
	if interaction_prompt_label:
		interaction_prompt_label.text = prompt_text
	if scavenge_progress_bar:
		scavenge_progress_bar.visible = true
		scavenge_progress_bar.value = clampf(progress_ratio * 100.0, 0.0, 100.0)

## Hides the scavenge interaction prompt and resets progress bar.
func hide_scavenge_prompt() -> void:
	if _success_message_timer > 0.0:
		return
	if interaction_panel:
		interaction_panel.visible = false
	if scavenge_progress_bar:
		scavenge_progress_bar.value = 0.0

## Displays a confirmation message on the interaction panel after scavenging completes.
func show_scavenge_success(message: String = "[ SUPPLIES SECURED: +35 FUEL | REPAIRED ]", duration: float = 2.5) -> void:
	if not interaction_panel:
		return
	interaction_panel.visible = true
	if interaction_prompt_label:
		interaction_prompt_label.text = message
	if scavenge_progress_bar:
		scavenge_progress_bar.visible = false
	_success_message_timer = duration

## Fades screen to full black over the specified duration in seconds.
func fade_to_black(duration: float = 2.0) -> void:
	if not fade_overlay:
		return
	_fade_target_alpha = 1.0
	_fade_speed = 1.0 / maxf(0.05, duration)
	_is_fading = true
	fade_overlay.visible = true

## Fades screen from full black back to normal vision over the specified duration.
func fade_from_black(duration: float = 2.0) -> void:
	if not fade_overlay:
		return
	_fade_target_alpha = 0.0
	_fade_speed = 1.0 / maxf(0.05, duration)
	_is_fading = true
	fade_overlay.visible = true

func _process_screen_fade(delta: float) -> void:
	if not _is_fading or not fade_overlay:
		return

	fade_overlay.modulate.a = move_toward(fade_overlay.modulate.a, _fade_target_alpha, _fade_speed * delta)
	if is_equal_approx(fade_overlay.modulate.a, _fade_target_alpha):
		_is_fading = false
		if _fade_target_alpha <= 0.01:
			fade_overlay.visible = false
			screen_faded_from_black.emit()
		else:
			screen_faded_to_black.emit()

func _find_van() -> void:
	if target_van:
		return
	var parent := get_parent()
	if parent:
		var van_candidate := parent.get_node_or_null("Van") as Van
		if van_candidate:
			target_van = van_candidate
			return
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("player")
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
	if not target_van.engine_health_changed.is_connected(_on_engine_health_changed):
		target_van.engine_health_changed.connect(_on_engine_health_changed)

func _connect_radio_manager() -> void:
	if RadioManager.instance:
		if not RadioManager.instance.dispatch_received.is_connected(_on_dispatch_received):
			RadioManager.instance.dispatch_received.connect(_on_dispatch_received)

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

func _process_status_warnings(delta: float) -> void:
	if not target_van or not low_fuel_warning:
		return

	if target_van.current_engine_health <= 0.0:
		low_fuel_warning.visible = true
		low_fuel_warning.text = "[ CRITICAL ENGINE FAILURE ]"
		low_fuel_warning.modulate = Color(1.0, 0.15, 0.15, 1.0)
	elif target_van.current_fuel <= 0.0:
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
	elif target_van.current_engine_health < 30.0:
		_blink_timer += delta
		if _blink_timer >= 0.35:
			_blink_timer = 0.0
			_blink_visible = !_blink_visible
			low_fuel_warning.visible = _blink_visible
		low_fuel_warning.text = "[ ! ENGINE DAMAGED ! ]"
		low_fuel_warning.modulate = Color(1.0, 0.5, 0.15, 1.0)
	else:
		low_fuel_warning.visible = false

func _process_radio_dispatch(delta: float) -> void:
	if not dispatch_panel or not dispatch_label:
		return

	if not RadioManager.instance or not RadioManager.instance.dispatch_received.is_connected(_on_dispatch_received):
		_connect_radio_manager()

	if _is_typing:
		_typewriter_timer += delta
		_cursor_blink_timer += delta
		if _cursor_blink_timer >= 0.16:
			_cursor_blink_timer = 0.0
			_cursor_visible = not _cursor_visible

		# Progressive character reveal (~30 characters/second)
		if _typewriter_timer >= 0.032:
			_typewriter_timer = 0.0
			_displayed_chars += 1
			var current_slice: String = _target_dispatch_text.substr(0, _displayed_chars)
			var cursor: String = "_" if _cursor_visible else " "
			dispatch_label.text = current_slice + cursor

			if _displayed_chars >= _target_dispatch_text.length():
				_is_typing = false
				dispatch_label.text = _target_dispatch_text
	elif _is_displaying_dispatch:
		_dispatch_display_timer += delta
		if _dispatch_display_timer >= _dispatch_hold_duration:
			# Smooth fade out
			dispatch_panel.modulate.a = move_toward(dispatch_panel.modulate.a, 0.0, 1.6 * delta)
			if dispatch_panel.modulate.a <= 0.01:
				dispatch_panel.visible = false
				_is_displaying_dispatch = false

func _on_dispatch_received(text: String, duration: float) -> void:
	if not dispatch_panel or not dispatch_label:
		return
	_target_dispatch_text = text
	_displayed_chars = 0
	_typewriter_timer = 0.0
	_dispatch_display_timer = 0.0
	_dispatch_hold_duration = duration
	_is_typing = true
	_is_displaying_dispatch = true
	dispatch_label.text = "_"
	dispatch_panel.visible = true
	dispatch_panel.modulate.a = 1.0

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

func _on_engine_health_changed(_current: float, _max_val: float) -> void:
	pass

func _on_distance_updated(_meters: float, current_km: float) -> void:
	if route_label:
		route_label.text = "ROUTE 77  |  KM %4.1f ──> 77.0" % current_km

func _on_drift_state_changed(is_active: bool) -> void:
	if drift_badge:
		if is_active:
			drift_badge.modulate = Color(1.0, 0.68, 0.15, 1.0) # Vibrant active amber
		else:
			drift_badge.modulate = Color(0.4, 0.45, 0.48, 0.35) # Dim technical standby watermark
