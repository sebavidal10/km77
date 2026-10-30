class_name PostProcess
extends CanvasLayer

@export_group("Retro Shader Settings")
## Target pixelation resolution. Defaults to 960x540 to keep the retro look while making road details easier to read.
@export var target_resolution: Vector2 = Vector2(960.0, 540.0):
	set(val):
		target_resolution = val
		_update_uniform("target_resolution", val)

## Number of quantization levels per color channel (PSX/16-bit aesthetic).
@export var color_depth: float = 48.0:
	set(val):
		color_depth = val
		_update_uniform("color_depth", val)

## Intensity of 8x8 Bayer matrix ordered dithering.
@export var dither_intensity: float = 0.16:
	set(val):
		dither_intensity = val
		_update_uniform("dither_intensity", val)

## Intensity of analog noise/grain.
@export var grain_intensity: float = 0.006:
	set(val):
		grain_intensity = val
		_update_uniform("grain_intensity", val)

## Intensity of CRT scanlines.
@export var scanline_intensity: float = 0.01:
	set(val):
		scanline_intensity = val
		_update_uniform("scanline_intensity", val)

## Base chromatic aberration lens distortion.
@export var base_chromatic_aberration: float = 0.0008:
	set(val):
		base_chromatic_aberration = val
		_update_uniform("chromatic_aberration", val)

## Color saturation multiplier used before the noir conversion.
@export var saturation: float = 1.15:
	set(val):
		saturation = val
		_update_uniform("saturation", val)

## Desaturates the rendered world into the game's noir palette (0 = original, 1 = grayscale).
@export_range(0.0, 1.0, 0.05) var noir_strength: float = 1.0:
	set(val):
		noir_strength = clampf(val, 0.0, 1.0)
		_update_uniform("noir_strength", noir_strength)

@onready var color_rect: ColorRect = $PostProcessOverlay

var _current_glitch_intensity: float = 0.0
var _approach_glitch: float = 0.0
var _paradox_spike_timer: float = 0.0
var _glitch_decay_rate: float = 3.0
var _shader_mat: ShaderMaterial = null

func _ready() -> void:
	# Ensure this CanvasLayer renders behind the HUD (layer 1 vs HUD layer 10)
	layer = 1

	if color_rect and color_rect.material is ShaderMaterial:
		_shader_mat = color_rect.material as ShaderMaterial

	_apply_all_uniforms()
	_connect_vehicle_events()
	_connect_radio_events()

func _process(delta: float) -> void:
	if _paradox_spike_timer > 0.0:
		_paradox_spike_timer -= delta
		if _paradox_spike_timer <= 0.0:
			_paradox_spike_timer = 0.0
			_approach_glitch = 0.0

	if _current_glitch_intensity > 0.001:
		_current_glitch_intensity = move_toward(_current_glitch_intensity, 0.0, _glitch_decay_rate * delta)
	elif not is_equal_approx(_current_glitch_intensity, 0.0):
		_current_glitch_intensity = 0.0

	var effective_glitch: float = 1.0 if _paradox_spike_timer > 0.0 else maxf(_current_glitch_intensity, _approach_glitch)
	effective_glitch = clampf(effective_glitch, 0.0, 1.0)

	_update_uniform("glitch_intensity", effective_glitch)
	_update_uniform("static_glitch_intensity", effective_glitch)
	var ca := base_chromatic_aberration + (effective_glitch * 0.012)
	_update_uniform("chromatic_aberration", ca)

## Triggers a momentary glitch and static burst on screen.
func trigger_glitch(intensity: float = 0.6, decay_speed: float = 2.5) -> void:
	_current_glitch_intensity = clampf(maxf(_current_glitch_intensity, intensity), 0.0, 1.0)
	_glitch_decay_rate = maxf(0.5, decay_speed)
	_update_uniform("static_glitch_intensity", _current_glitch_intensity)
	_update_uniform("glitch_intensity", _current_glitch_intensity)

func _update_uniform(param_name: String, value: Variant) -> void:
	if not _shader_mat and color_rect and color_rect.material is ShaderMaterial:
		_shader_mat = color_rect.material as ShaderMaterial
	if _shader_mat:
		_shader_mat.set_shader_parameter(param_name, value)

func _apply_all_uniforms() -> void:
	_update_uniform("target_resolution", target_resolution)
	_update_uniform("color_depth", color_depth)
	_update_uniform("dither_intensity", dither_intensity)
	_update_uniform("grain_intensity", grain_intensity)
	_update_uniform("scanline_intensity", scanline_intensity)
	_update_uniform("chromatic_aberration", base_chromatic_aberration)
	_update_uniform("static_glitch_intensity", 0.0)
	_update_uniform("glitch_intensity", 0.0)
	_update_uniform("saturation", saturation)
	_update_uniform("noir_strength", noir_strength)

func _connect_vehicle_events() -> void:
	var tree := get_tree()
	if not tree:
		return
	var nodes := tree.get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Van:
		_on_van_found(nodes[0] as Van)
	else:
		tree.create_timer(0.2).timeout.connect(func():
			var retry_nodes := get_tree().get_nodes_in_group("player")
			if not retry_nodes.is_empty() and retry_nodes[0] is Van:
				_on_van_found(retry_nodes[0] as Van)
		)

func _on_van_found(van: Van) -> void:
	if not van.collision_impact.is_connected(_on_collision_impact):
		van.collision_impact.connect(_on_collision_impact)
	if not van.distance_updated.is_connected(_on_distance_updated):
		van.distance_updated.connect(_on_distance_updated)
	if not van.paradox_anomaly_triggered.is_connected(_on_paradox_anomaly):
		van.paradox_anomaly_triggered.connect(_on_paradox_anomaly)
	if not van.loop_reset_triggered.is_connected(_on_loop_reset):
		van.loop_reset_triggered.connect(_on_loop_reset)

func _on_distance_updated(_meters: float, current_km: float) -> void:
	# Map remaining distance: when descending from 79.5 toward 77.0, progressively scale glitch from 0.0 to 1.0
	if current_km <= 79.5 and current_km >= 77.0:
		_approach_glitch = clampf((79.5 - current_km) / (79.5 - 77.0), 0.0, 1.0)
	elif current_km > 79.5:
		_approach_glitch = 0.0

func _on_paradox_anomaly() -> void:
	# Violent distortion spike for 0.5s upon breaching KM 77 loop paradox
	_paradox_spike_timer = 0.5
	trigger_glitch(1.0, 2.0)
	_approach_glitch = 0.0

func _on_loop_reset() -> void:
	_approach_glitch = 0.0
	_paradox_spike_timer = 0.0

func _on_collision_impact(trauma: float) -> void:
	# Convert physical crash trauma into visual VHS tear glitch
	var glitch_amount := clampf(trauma * 0.75, 0.25, 0.95)
	trigger_glitch(glitch_amount, 2.2)

func _connect_radio_events() -> void:
	var tree := get_tree()
	if not tree:
		return
	var root := tree.current_scene
	if root:
		var radio_candidate := root.get_node_or_null("RadioManager")
		if radio_candidate and radio_candidate.has_signal("static_burst_triggered"):
			if not radio_candidate.static_burst_triggered.is_connected(_on_radio_static_burst):
				radio_candidate.static_burst_triggered.connect(_on_radio_static_burst)
			return

	tree.create_timer(0.2).timeout.connect(func():
		var scene := get_tree().current_scene if get_tree() else null
		if scene:
			var radio := scene.get_node_or_null("RadioManager")
			if radio and radio.has_signal("static_burst_triggered"):
				if not radio.static_burst_triggered.is_connected(_on_radio_static_burst):
					radio.static_burst_triggered.connect(_on_radio_static_burst)
	)

func _on_radio_static_burst(intensity: float, decay_speed: float) -> void:
	trigger_glitch(intensity, decay_speed)
