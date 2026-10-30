class_name HUD
extends CanvasLayer

signal screen_faded_to_black
signal screen_faded_from_black

@export_group("Target")
## The vehicle node to observe for telemetry, fuel, and trip metrics.
@export var target_van: Van

const COLOR_PHOSPHOR_GREEN := Color(0.88, 0.85, 0.78, 1.0) # Pale Bone / Tarnished Silver
const COLOR_ANALOG_AMBER := Color(0.96, 0.62, 0.18, 1.0)   # Candlelight Amber
const COLOR_BLOOD_RED := Color(0.95, 0.16, 0.16, 1.0)       # Sepulchral Blood Crimson
const COLOR_HIGH_BEAM_BLUE := Color(0.32, 0.68, 1.0, 1.0)
const COLOR_LOW_BEAM_GREEN := Color(0.88, 0.85, 0.78, 0.9)

@onready var speed_value_label: Label = %SpeedValue
@onready var drift_badge: Label = %DriftBadge
@onready var headlight_badge: Label = %HeadlightBadge
@onready var rear_mirror_camera: Camera3D = %RearMirrorCamera
@onready var route_label: Label = %RouteLabel
@onready var relics_label: Label = get_node_or_null("%RelicsLabel") as Label
@onready var fuel_bar: ProgressBar = %FuelBar
@onready var fuel_percent_label: Label = %FuelPercent
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_percent_label: Label = %HealthPercent
@onready var bottom_right: VBoxContainer = get_node_or_null("MarginContainer/Control/BottomRight") as VBoxContainer
@onready var low_fuel_warning: Label = %LowFuelWarning
@onready var dispatch_panel: PanelContainer = %DispatchPanel
@onready var dispatch_header: Label = %DispatchHeader
@onready var dispatch_label: Label = %DispatchText
@onready var fade_overlay: ColorRect = %ScreenFadeOverlay
@onready var reboot_label: Label = %RebootLabel
@onready var interaction_panel: PanelContainer = %InteractionPanel
@onready var interaction_prompt_label: Label = %InteractionPromptLabel
@onready var scavenge_progress_bar: ProgressBar = %ScavengeProgressBar
@onready var forensic_panel: PanelContainer = %ForensicPanel
@onready var forensic_header: Label = %ForensicHeader
@onready var forensic_text: Label = %ForensicText
@onready var pause_overlay: ColorRect = %PauseOverlay
@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var quit_menu_button: Button = %QuitMenuButton
@onready var static_audio: AudioStreamPlayer = get_node_or_null("%StaticAudio") as AudioStreamPlayer
var horn_button: Button
var turbo_button: Button
var _health_fill_style: StyleBoxFlat
var _true_ending_overlay: ColorRect = null
var _impact_feedback: PanelContainer
var _impact_feedback_label: Label
var _impact_feedback_time: float = 0.0

var _static_tween: Tween = null
var _forensic_display_timer: float = 0.0
var _forensic_hold_duration: float = 0.0

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
	_create_horn_button()
	_create_turbo_button()
	_create_impact_feedback()
	_connect_radio_manager()
	_update_initial_display()
	_update_turbo_display()
	if dispatch_panel:
		dispatch_panel.visible = false
		dispatch_panel.modulate.a = 0.0
	if fade_overlay:
		fade_overlay.visible = false
		fade_overlay.modulate.a = 0.0
	if interaction_panel:
		interaction_panel.visible = false
	if pause_overlay:
		pause_overlay.visible = false
	if resume_button:
		resume_button.pressed.connect(resume_game)
	if restart_button:
		restart_button.pressed.connect(restart_patrol)
	if quit_menu_button:
		quit_menu_button.pressed.connect(quit_to_menu)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()

func toggle_pause() -> void:
	if _true_ending_overlay and _true_ending_overlay.visible:
		return
	if not pause_overlay:
		return
	if get_tree().paused:
		resume_game()
	else:
		pause_game()

func pause_game() -> void:
	get_tree().paused = true
	if pause_overlay:
		pause_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume_game() -> void:
	get_tree().paused = false
	if pause_overlay:
		pause_overlay.visible = false

func restart_patrol() -> void:
	get_tree().paused = false
	if pause_overlay:
		pause_overlay.visible = false
	if _true_ending_overlay:
		_true_ending_overlay.visible = false
	var root := get_tree().current_scene
	if root:
		var lrm := root.get_node_or_null("LoopResetManager")
		if lrm and lrm.has_method("start_timeline_reboot"):
			lrm.start_timeline_reboot("REINICIO MANUAL DEL CORTEJO")
			return
	if target_van:
		target_van.reset_loop_state()

func quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

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

	# Handle roadside abandoned car forensic log display and fade
	_process_forensic_log(delta)
	_process_impact_feedback(delta)

	# Direct sync fallback to ensure 100% visual responsiveness
	_sync_van_state()
	_update_turbo_display()

	# Synchronize retro rear-view mirror camera to vehicle orientation
	_update_rear_mirror()

func _update_rear_mirror() -> void:
	if not rear_mirror_camera or not is_instance_valid(rear_mirror_camera):
		return
	if not target_van or not is_instance_valid(target_van):
		return
	var mount: Marker3D = target_van.get_node_or_null("RearMirrorMount") as Marker3D
	if mount and is_instance_valid(mount):
		rear_mirror_camera.global_transform = mount.global_transform
	else:
		var van_basis := target_van.global_transform.basis
		rear_mirror_camera.global_position = target_van.global_position + (van_basis * Vector3(0.0, 1.95, 2.22))
		rear_mirror_camera.global_transform.basis = van_basis * Basis(Vector3.UP, PI)

func _process_forensic_log(delta: float) -> void:
	if not forensic_panel or not forensic_panel.visible:
		return
	if _forensic_hold_duration > 0.0:
		_forensic_display_timer += delta
		if _forensic_display_timer >= _forensic_hold_duration:
			forensic_panel.modulate.a = move_toward(forensic_panel.modulate.a, 0.0, 1.2 * delta)
			if forensic_panel.modulate.a <= 0.01:
				forensic_panel.visible = false
				_forensic_hold_duration = 0.0

## Displays an atmospheric forensic police log card on the HUD for duration seconds.
func show_forensic_log(log_text: String, duration: float = 6.0, header: String = "† ARCHIVO FORENSE // EVIDENCIA RECUPERADA †") -> void:
	if not forensic_panel or not forensic_text:
		return
	if forensic_header:
		forensic_header.text = header
	forensic_text.text = log_text
	forensic_panel.visible = true
	forensic_panel.modulate.a = 1.0
	_forensic_display_timer = 0.0
	_forensic_hold_duration = duration

func _process_interaction_timer(delta: float) -> void:
	if _success_message_timer > 0.0:
		_success_message_timer -= delta
		if _success_message_timer <= 0.0:
			_success_message_timer = 0.0
			if interaction_panel:
				interaction_panel.visible = false

## Displays the scavenge interaction prompt and current progress ratio (0.0 to 1.0).
func show_scavenge_prompt(prompt_text: String = "MANTÉN [E] PARA REPOSTAR / REPARAR", progress_ratio: float = 0.0) -> void:
	if not interaction_panel:
		return
	if _success_message_timer > 0.0:
		return
	interaction_panel.visible = true
	if interaction_prompt_label:
		interaction_prompt_label.text = prompt_text
		interaction_prompt_label.add_theme_color_override("font_color", COLOR_ANALOG_AMBER)
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
func show_scavenge_success(message: String = "[ † SUMINISTROS ASEGURADOS: +35 COMBUSTIBLE | MOTOR REPARADO † ]", duration: float = 2.5) -> void:
	if not interaction_panel:
		return
	interaction_panel.visible = true
	if interaction_prompt_label:
		interaction_prompt_label.text = message
		interaction_prompt_label.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
	if scavenge_progress_bar:
		scavenge_progress_bar.visible = false
	_success_message_timer = duration

## Displays monospace timeline reboot failure message over the fade overlay.
func show_reboot_message(show: bool, text: String = "† EL CORTEJO NO HA TERMINADO... REINICIANDO BUCLE EN KM 85.0 †") -> void:
	if reboot_label:
		reboot_label.text = text
		reboot_label.visible = show

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
	if reboot_label:
		reboot_label.visible = false
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
	if not target_van.turbo_state_changed.is_connected(_on_turbo_state_changed):
		target_van.turbo_state_changed.connect(_on_turbo_state_changed)
	if not target_van.headlights_mode_changed.is_connected(_on_headlights_mode_changed):
		target_van.headlights_mode_changed.connect(_on_headlights_mode_changed)
	if not target_van.relics_updated.is_connected(_on_relics_updated):
		target_van.relics_updated.connect(_on_relics_updated)
	if not target_van.impact_reported.is_connected(_on_impact_reported):
		target_van.impact_reported.connect(_on_impact_reported)

func _connect_radio_manager() -> void:
	if RadioManager.instance:
		if not RadioManager.instance.dispatch_received.is_connected(_on_dispatch_received):
			RadioManager.instance.dispatch_received.connect(_on_dispatch_received)
		if not RadioManager.instance.static_burst_triggered.is_connected(_on_static_burst_triggered):
			RadioManager.instance.static_burst_triggered.connect(_on_static_burst_triggered)

func _update_initial_display() -> void:
	if target_van:
		_sync_van_state()
	else:
		_on_speed_updated(0.0)
		_on_fuel_changed(100.0, 100.0)
		_on_distance_updated(0.0, 85.0)
		_on_drift_state_changed(false)
		_on_headlights_mode_changed(false)
		_on_relics_updated(0, 3)

func _sync_van_state() -> void:
	if not target_van:
		return
	_on_speed_updated(target_van.current_speed_kmh)
	_on_fuel_changed(target_van.current_fuel, target_van.max_fuel)
	_on_engine_health_changed(target_van.current_engine_health, target_van.max_engine_health)
	_on_distance_updated(target_van.distance_traveled_meters, target_van.current_kilometer)
	_on_drift_state_changed(target_van.is_actively_drifting)
	_on_headlights_mode_changed(target_van.is_high_beams_active)
	_on_relics_updated(target_van.relics_collected, target_van.REQUIRED_RELICS)

func _on_relics_updated(collected: int, required: int) -> void:
	if not relics_label:
		return
	if collected >= required:
		relics_label.text = "† 3 / 3 ACTAS REUNIDAS — SELLO ROTO EN KM 77.0 †"
		relics_label.add_theme_color_override("font_color", COLOR_BLOOD_RED)
	else:
		relics_label.text = "† ACTAS DE 1989 (RELIQUIAS): %d / %d †" % [collected, required]
		relics_label.add_theme_color_override("font_color", COLOR_ANALOG_AMBER)

func _process_status_warnings(delta: float) -> void:
	if not target_van or not low_fuel_warning:
		return

	if target_van.current_engine_health <= 0.0:
		low_fuel_warning.visible = true
		low_fuel_warning.text = "[ FALLO CRÍTICO DEL MOTOR ]"
		low_fuel_warning.modulate = COLOR_BLOOD_RED
	elif target_van.current_fuel <= 0.0:
		low_fuel_warning.visible = true
		low_fuel_warning.text = "[ SIN COMBUSTIBLE - MOTOR CALADO ]"
		low_fuel_warning.modulate = COLOR_BLOOD_RED
	elif target_van.current_fuel < 20.0:
		_blink_timer += delta
		if _blink_timer >= 0.35:
			_blink_timer = 0.0
			_blink_visible = !_blink_visible
			low_fuel_warning.visible = _blink_visible
		low_fuel_warning.text = "[ ! RESERVA DE COMBUSTIBLE ! ]"
		low_fuel_warning.modulate = COLOR_ANALOG_AMBER
	elif target_van.current_engine_health < 30.0:
		_blink_timer += delta
		if _blink_timer >= 0.35:
			_blink_timer = 0.0
			_blink_visible = !_blink_visible
			low_fuel_warning.visible = _blink_visible
		low_fuel_warning.text = "[ ! MOTOR DAÑADO ! ]"
		low_fuel_warning.modulate = COLOR_BLOOD_RED
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

	# Trigger radio squelch transmission burst (1.8s duration)
	_play_static_burst(1.8)

	# Contextual palette: Glitch Blood Red for critical/anomaly dispatches, Bone & Amber for routine dispatches
	var is_critical: bool = false
	var upper := text.to_upper()
	for kw in ["10-33", "10-0", "10-50", "ALERTA", "CRÍTIC", "COLAPSO", "IMPACTO", "PROCESIÓN", "CORRUPT", "BUCLE", "CARMESÍ", "SELLO"]:
		if upper.contains(kw):
			is_critical = true
			break

	if is_critical:
		if dispatch_header:
			dispatch_header.text = "▲ ALERTA // FRECUENCIA SEPULCRAL INTERVENIDA"
			dispatch_header.add_theme_color_override("font_color", COLOR_BLOOD_RED)
		dispatch_label.add_theme_color_override("font_color", COLOR_BLOOD_RED)
	else:
		if dispatch_header:
			dispatch_header.text = "● RX // RADIO PARROQUIAL FREC 142.8 MHz"
			dispatch_header.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
		dispatch_label.add_theme_color_override("font_color", COLOR_ANALOG_AMBER)

	var panel_style := dispatch_panel.get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		var dup_style := panel_style.duplicate() as StyleBoxFlat
		if is_critical:
			dup_style.border_color = COLOR_BLOOD_RED
			dup_style.bg_color = Color(0.06, 0.015, 0.015, 0.92)
		else:
			dup_style.border_color = Color(0.52, 0.38, 0.32, 0.85)
			dup_style.bg_color = Color(0.028, 0.022, 0.036, 0.88)
		dispatch_panel.add_theme_stylebox_override("panel", dup_style)

func _on_static_burst_triggered(_intensity: float, _decay: float) -> void:
	_play_static_burst(1.6)

## Plays a 1.5 to 2.0 second authentic radio static squelch/transmission burst at -12.0 dB
func _play_static_burst(burst_duration: float = 1.8) -> void:
	if not static_audio:
		static_audio = get_node_or_null("%StaticAudio") as AudioStreamPlayer
		if not static_audio:
			static_audio = get_node_or_null("StaticAudio") as AudioStreamPlayer
	if not static_audio:
		return

	if _static_tween and _static_tween.is_valid():
		_static_tween.kill()

	static_audio.volume_db = -12.0
	static_audio.play()

	_static_tween = create_tween()
	var hold_time: float = maxf(0.2, burst_duration - 0.5)
	_static_tween.tween_interval(hold_time)
	_static_tween.tween_property(static_audio, "volume_db", -40.0, 0.5)
	_static_tween.tween_callback(static_audio.stop)

func _on_speed_updated(speed_kmh: float) -> void:
	if speed_value_label:
		speed_value_label.text = "%03d" % int(round(speed_kmh))

func _create_impact_feedback() -> void:
	_impact_feedback = PanelContainer.new()
	_impact_feedback.name = "ImpactFeedback"
	_impact_feedback.set_anchors_preset(Control.PRESET_CENTER)
	_impact_feedback.position = Vector2(-185.0, 124.0)
	_impact_feedback.size = Vector2(370.0, 54.0)
	_impact_feedback.custom_minimum_size = Vector2(370.0, 54.0)
	_impact_feedback.visible = false
	_impact_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.018, 0.022, 0.92)
	panel_style.border_color = COLOR_ANALOG_AMBER
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(2)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	_impact_feedback.add_theme_stylebox_override("panel", panel_style)
	_impact_feedback_label = Label.new()
	_impact_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_impact_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_impact_feedback_label.add_theme_font_size_override("font_size", 13)
	_impact_feedback_label.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
	_impact_feedback.add_child(_impact_feedback_label)
	add_child(_impact_feedback)

func _on_impact_reported(speed_kmh: float, damage: float, engine_percent: float) -> void:
	if not _impact_feedback or not _impact_feedback_label:
		return
	var heavy := speed_kmh >= 50.0
	if damage > 0.1:
		var prefix := "† COLISIÓN GRAVE" if heavy else "† IMPACTO"
		_impact_feedback_label.text = "%s  ·  %d KM/H  ·  MOTOR -%.0f%% †" % [prefix, roundi(speed_kmh), damage]
	else:
		_impact_feedback_label.text = "† ROCE  ·  %d KM/H  ·  SIN DAÑO MECÁNICO †" % roundi(speed_kmh)
	var feedback_color := COLOR_BLOOD_RED if engine_percent < 30.0 or heavy else (COLOR_ANALOG_AMBER if speed_kmh >= 30.0 else COLOR_PHOSPHOR_GREEN)
	_impact_feedback_label.add_theme_color_override("font_color", feedback_color)
	_impact_feedback.visible = true
	_impact_feedback.modulate.a = 1.0
	_impact_feedback_time = 2.0
	var style := _impact_feedback.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.border_color = COLOR_BLOOD_RED if heavy else COLOR_ANALOG_AMBER

func _process_impact_feedback(delta: float) -> void:
	if not _impact_feedback or not _impact_feedback.visible:
		return
	_impact_feedback_time -= delta
	if _impact_feedback_time <= 0.45:
		_impact_feedback.modulate.a = clampf(_impact_feedback_time / 0.45, 0.0, 1.0)
	if _impact_feedback_time <= 0.0:
		_impact_feedback.visible = false

func _on_fuel_changed(current: float, max_val: float) -> void:
	var percent: float = (current / max_val) * 100.0 if max_val > 0.0 else 0.0
	if fuel_bar:
		fuel_bar.max_value = max_val
		fuel_bar.value = current
	if fuel_percent_label:
		fuel_percent_label.text = "%3.0f%%" % percent

func _on_engine_health_changed(current: float, max_val: float) -> void:
	var percent := current / max_val * 100.0 if max_val > 0.0 else 0.0
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = current
	if health_percent_label:
		health_percent_label.text = "%3.0f%%" % percent
	if health_bar:
		var fill_color := Color(0.78, 0.74, 0.66, 1.0) if percent >= 60.0 else (COLOR_ANALOG_AMBER if percent >= 30.0 else COLOR_BLOOD_RED)
		if not _health_fill_style:
			_health_fill_style = StyleBoxFlat.new()
			_health_fill_style.set_corner_radius_all(1)
			_health_fill_style.content_margin_left = 2.0
			_health_fill_style.content_margin_right = 2.0
			_health_fill_style.content_margin_top = 1.0
			_health_fill_style.content_margin_bottom = 1.0
		health_bar.add_theme_stylebox_override("fill", _health_fill_style)
		_health_fill_style.bg_color = fill_color
	_process_status_warnings(0.0)

func _on_turbo_state_changed(_active: bool, _seconds_left: float, _cooldown_left: float) -> void:
	_update_turbo_display()

func _update_turbo_display() -> void:
	if not turbo_button:
		return
	if not target_van:
		turbo_button.text = "† TURBO  [SHIFT]"
		turbo_button.disabled = true
		return
	if target_van.is_turbo_active:
		turbo_button.text = "† TURBO ACTIVO  %.1fs" % target_van._turbo_seconds_left
		turbo_button.disabled = true
	elif target_van.can_activate_turbo():
		turbo_button.text = "† TURBO  [SHIFT]"
		turbo_button.disabled = false
	else:
		turbo_button.text = "† ENFRIANDO  %.0fs" % target_van._turbo_cooldown_left
		turbo_button.disabled = true

func _on_distance_updated(_meters: float, current_km: float) -> void:
	if route_label:
		route_label.text = "† RUTA 77  ❖  KM %4.1f ──> 77.0 †" % current_km

func _on_drift_state_changed(is_active: bool) -> void:
	if drift_badge:
		drift_badge.text = "[ DERRAPE ]"
		if is_active:
			drift_badge.modulate = COLOR_ANALOG_AMBER
		else:
			drift_badge.modulate = Color(0.45, 0.42, 0.46, 0.35)

## Updates the headlight beam indicator on the HUD.
func update_beam_indicator(high: bool) -> void:
	if not headlight_badge:
		return
	if high:
		headlight_badge.text = "† LUCES ALTAS [F/H]"
		headlight_badge.modulate = COLOR_BLOOD_RED
		headlight_badge.add_theme_color_override("font_color", COLOR_BLOOD_RED)
	else:
		headlight_badge.text = "❖ LUCES BAJAS [F/H]"
		headlight_badge.modulate = COLOR_PHOSPHOR_GREEN
		headlight_badge.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)

func _create_horn_button() -> void:
	if not bottom_right:
		return
	horn_button = Button.new()
	horn_button.name = "HornButton"
	horn_button.custom_minimum_size = Vector2(190.0, 34.0)
	horn_button.text = "[ X ]  CLAXON"
	horn_button.tooltip_text = "Sonar el claxon (X)"
	horn_button.focus_mode = Control.FOCUS_NONE
	horn_button.add_theme_font_size_override("font_size", 13)
	horn_button.add_theme_color_override("font_color", COLOR_ANALOG_AMBER)
	horn_button.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.52))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.025, 0.02, 0.032, 0.92)
	normal.border_color = Color(0.68, 0.48, 0.24, 0.78)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	horn_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.09, 0.05, 0.03, 0.96)
	hover.border_color = Color(0.96, 0.62, 0.18, 1.0)
	horn_button.add_theme_stylebox_override("hover", hover)
	horn_button.add_theme_stylebox_override("pressed", hover)
	horn_button.button_down.connect(_on_horn_button_down)
	horn_button.button_up.connect(_on_horn_button_up)
	bottom_right.add_child(horn_button)

func _on_horn_button_down() -> void:
	if not target_van:
		_find_van()
	if target_van:
		target_van.start_horn(true)

func _on_horn_button_up() -> void:
	if target_van:
		target_van.release_horn()

func _create_turbo_button() -> void:
	if not bottom_right:
		return
	turbo_button = Button.new()
	turbo_button.name = "TurboButton"
	turbo_button.custom_minimum_size = Vector2(190.0, 34.0)
	turbo_button.tooltip_text = "Impulso temporal de aceleración (Shift)"
	turbo_button.focus_mode = Control.FOCUS_NONE
	turbo_button.add_theme_font_size_override("font_size", 12)
	turbo_button.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
	turbo_button.add_theme_color_override("font_disabled_color", Color(0.48, 0.45, 0.44, 0.85))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.025, 0.02, 0.032, 0.92)
	normal.border_color = Color(0.55, 0.42, 0.38, 0.78)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	turbo_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.03, 0.04, 0.96)
	hover.border_color = Color(0.95, 0.22, 0.22, 1.0)
	turbo_button.add_theme_stylebox_override("hover", hover)
	turbo_button.add_theme_stylebox_override("pressed", hover)
	turbo_button.pressed.connect(_on_turbo_button_pressed)
	bottom_right.add_child(turbo_button)

func _on_turbo_button_pressed() -> void:
	if not target_van:
		_find_van()
	if target_van:
		target_van.activate_turbo()

func _on_headlights_mode_changed(is_high: bool) -> void:
	update_beam_indicator(is_high)

## Displays the True Ending modal when the player reaches KM 77.0 with all 3 Forbidden Relics.
func show_true_ending_screen(loops_taken: int = 1) -> void:
	if not _true_ending_overlay:
		_true_ending_overlay = ColorRect.new()
		_true_ending_overlay.name = "TrueEndingOverlay"
		_true_ending_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
		_true_ending_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_true_ending_overlay.color = Color(0.03, 0.015, 0.02, 0.94)
		add_child(_true_ending_overlay)

		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		_true_ending_overlay.add_child(center)

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(560, 340)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.022, 0.03, 0.96)
		style.border_color = COLOR_ANALOG_AMBER
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		style.content_margin_left = 28.0
		style.content_margin_right = 28.0
		style.content_margin_top = 24.0
		style.content_margin_bottom = 24.0
		panel.add_theme_stylebox_override("panel", style)
		center.add_child(panel)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 14)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(vbox)

		var title := Label.new()
		title.text = "† EL DESPERTAR DE LA RUTA 77 — FINAL VERDADERO †"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", COLOR_ANALOG_AMBER)
		vbox.add_child(title)

		var body := Label.new()
		body.name = "EpilogueBody"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_theme_font_size_override("font_size", 13)
		body.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
		vbox.add_child(body)

		var btn_restart := Button.new()
		btn_restart.custom_minimum_size = Vector2(0, 38)
		btn_restart.text = "[ † INICIAR UN NUEVO CORTEJO (KM 85.0) † ]"
		btn_restart.add_theme_font_size_override("font_size", 13)
		btn_restart.add_theme_color_override("font_color", COLOR_ANALOG_AMBER)
		btn_restart.pressed.connect(_on_true_ending_new_run)
		vbox.add_child(btn_restart)

		var btn_menu := Button.new()
		btn_menu.custom_minimum_size = Vector2(0, 38)
		btn_menu.text = "[ SALIR AL MENÚ PRINCIPAL ]"
		btn_menu.add_theme_font_size_override("font_size", 13)
		btn_menu.add_theme_color_override("font_color", COLOR_PHOSPHOR_GREEN)
		btn_menu.pressed.connect(quit_to_menu)
		vbox.add_child(btn_menu)

	var epilogue_label := _true_ending_overlay.find_child("EpilogueBody", true, false) as Label
	if epilogue_label:
		epilogue_label.text = (
			"Con las 3 Actas Prohibidas de 1989 reunidas en el salpicadero, el Furgón Parroquial N.º 77 "
			+ "cruza el hito del Kilómetro 77.0 sin regresar al pasado.\n\n"
			+ "El séptimo ataúd de roble negro cede su sello de plomo. La neblina carmesí se disipa sobre el barranco "
			+ "del 16 de octubre de 1989 y las campanas de la Parroquia 77 doblan por última vez.\n\n"
			+ "† Ciclos de Vigilia completados antes de romper el bucle: %d †" % maxi(1, loops_taken)
		)

	_true_ending_overlay.visible = true
	_true_ending_overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_true_ending_overlay, "modulate:a", 1.0, 1.4)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_true_ending_new_run() -> void:
	if _true_ending_overlay:
		_true_ending_overlay.visible = false
	if target_van:
		target_van.relics_collected = 0
		target_van.km77_breach_count = 0
		target_van.is_true_ending_active = false
		target_van.relics_updated.emit(0, target_van.REQUIRED_RELICS)
	restart_patrol()
