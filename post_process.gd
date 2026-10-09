class_name PostProcess
extends CanvasLayer

const Van = preload("res://van.gd")

@export_group("Retro Shader Settings")
## Target pixelation resolution. Defaults to 480x270 for authentic PSX ratio.
@export var target_resolution: Vector2 = Vector2(480.0, 270.0):
	set(val):
		target_resolution = val
		_update_uniform("target_resolution", val)

## Number of quantization levels per color channel (PSX/16-bit aesthetic).
@export var color_depth: float = 32.0:
	set(val):
		color_depth = val
		_update_uniform("color_depth", val)

## Intensity of 8x8 Bayer matrix ordered dithering.
@export var dither_intensity: float = 0.85:
	set(val):
		dither_intensity = val
		_update_uniform("dither_intensity", val)

## Intensity of analog noise/grain.
@export var grain_intensity: float = 0.035:
	set(val):
		grain_intensity = val
		_update_uniform("grain_intensity", val)

## Intensity of CRT scanlines.
@export var scanline_intensity: float = 0.06:
	set(val):
		scanline_intensity = val
		_update_uniform("scanline_intensity", val)

## Base chromatic aberration lens distortion.
@export var base_chromatic_aberration: float = 0.0015:
	set(val):
		base_chromatic_aberration = val
		_update_uniform("chromatic_aberration", val)

@onready var color_rect: ColorRect = $PostProcessOverlay

var _current_glitch_intensity: float = 0.0
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
	if _current_glitch_intensity > 0.001:
		_current_glitch_intensity = move_toward(_current_glitch_intensity, 0.0, _glitch_decay_rate * delta)
		_update_uniform("static_glitch_intensity", _current_glitch_intensity)
		var ca := base_chromatic_aberration + (_current_glitch_intensity * 0.008)
		_update_uniform("chromatic_aberration", ca)
	elif not is_equal_approx(_current_glitch_intensity, 0.0):
		_current_glitch_intensity = 0.0
		_update_uniform("static_glitch_intensity", 0.0)
		_update_uniform("chromatic_aberration", base_chromatic_aberration)

## Triggers a momentary glitch and static burst on screen.
func trigger_glitch(intensity: float = 0.6, decay_speed: float = 2.5) -> void:
	_current_glitch_intensity = clampf(maxf(_current_glitch_intensity, intensity), 0.0, 1.0)
	_glitch_decay_rate = maxf(0.5, decay_speed)
	_update_uniform("static_glitch_intensity", _current_glitch_intensity)

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
