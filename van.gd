class_name Van
extends CharacterBody3D

const RadioManager = preload("res://radio_manager.gd")
const RoadManager = preload("res://road_manager.gd")
const HUD = preload("res://hud.gd")
const ChaseCamera = preload("res://chase_camera.gd")

# Telemetry signals
signal fuel_changed(current_fuel: float, max_fuel: float)
signal fuel_depleted
signal distance_updated(distance_traveled_meters: float, current_kilometer: float)
signal speed_updated(speed_kmh: float)
signal drift_state_changed(is_drifting_active: bool)
signal engine_health_changed(current: float, max_val: float)
signal engine_critical
signal headlight_damaged(light_name: String)
signal headlights_mode_changed(is_high_beams: bool)
signal collision_impact(intensity: float)
signal vehicle_collapsed
signal loop_reset_triggered
signal paradox_anomaly_triggered

@export_group("Handling Tuning")
## Maximum forward speed in meters per second (30.5 m/s = approx 110 km/h).
@export var max_speed: float = 30.5
## Base forward acceleration rate in m/s^2 (weighted by launch inertia and aerodynamic drag).
@export var acceleration_rate: float = 7.5
## Deceleration rate applied when pressing the service brake (m/s^2).
@export var braking_force: float = 14.0
## Steering wheel turn speed in radians/s towards player input (smooth progressive rate).
@export var steer_speed: float = 1.8
## Steering wheel auto-center speed in radians/s when steering input is released.
@export var steer_return_speed: float = 2.6
## Maximum front wheel steering angle in radians (approx 28 degrees).
@export var max_steer_angle: float = deg_to_rad(28.0)
## High-speed steering ratio (reduces max steer angle at top speed to avoid violent snaps).
@export var high_speed_steer_ratio: float = 0.20
## Base vehicle wheelbase in meters used for bicycle steering geometry.
@export var wheelbase: float = 3.3

@export_group("Drift & Lateral Grip")
## Normal lateral tire grip (higher = vehicle sticks firmly to heading).
@export var lateral_grip: float = 16.0
## Lateral tire grip while handbraking (lower = vehicle slides sideways with inertia).
@export var drift_lateral_grip: float = 2.4
## Multiplier applied to steering responsiveness while handbraking (promotes oversteer).
@export var drift_oversteer_multiplier: float = 1.6
## Extra steering authority when countersteering into the slide to catch and balance the drift.
@export var countersteer_boost: float = 1.3
## Longitudinal speed scrubbed per second due to tire friction while sliding sideways.
@export var drift_drag: float = 3.5
## Speed at which tire grip recovers when handbrake is released.
@export var grip_recovery_speed: float = 12.0
## Minimum speed (m/s) required to turn the vehicle.
@export var min_steer_speed: float = 0.5
## Backward compatibility aliases for friction factor.
@export var drift_friction: float = 0.88
@export var normal_friction: float = 0.98

@export_group("Durability & Damage")
## Maximum condition/health of the vehicle engine.
@export var max_engine_health: float = 100.0
## Current engine condition/health.
@export var current_engine_health: float = 100.0
## Minimum forward collision speed (m/s) required to trigger damage and heavy deceleration.
@export var impact_speed_threshold: float = 5.0
## Multiplier translating impact speed into engine health damage.
@export var collision_damage_factor: float = 1.8
## Trauma intensity multiplier passed to chase camera shake.
@export var camera_shake_intensity: float = 0.85
## Probability of breaking a headlight on high-speed impacts (> 14 m/s).
@export var headlight_break_chance_heavy: float = 0.50
## Probability of breaking a headlight on medium impacts (5-14 m/s).
@export var headlight_break_chance_light: float = 0.25

@export_group("Headlight Beams")
## Whether high beams are currently active.
@export var is_high_beams_active: bool = false
## Low beam spot range (meters).
@export var low_beam_range: float = 65.0
## Low beam cone angle (degrees).
@export var low_beam_angle: float = 58.0
## Low beam intensity energy.
@export var low_beam_energy: float = 8.5
## Low beam downward pitch in degrees (illuminates road surface).
@export var low_beam_pitch_deg: float = 0.0
## High beam spot range (meters).
@export var high_beam_range: float = 130.0
## High beam cone angle (degrees).
@export var high_beam_angle: float = 38.0
## High beam intensity energy.
@export var high_beam_energy: float = 16.0
## High beam downward pitch in degrees (pierces far down highway).
@export var high_beam_pitch_deg: float = 0.0

@export_group("Reverse & Coasting")
## Maximum reverse speed in m/s (approx 45 km/h).
@export var reverse_max_speed: float = 12.5
## Acceleration rate when reversing.
@export var reverse_acceleration: float = 14.0
## Passive coasting slowdown rate when neither throttle nor brake is pressed.
@export var coast_deceleration: float = 3.5

@export_group("Fuel Economy")
## Maximum fuel capacity in units/liters.
@export var max_fuel: float = 100.0
## Current fuel level.
@export var current_fuel: float = 100.0
## Base fuel consumed per second when engine is idling/active.
@export var fuel_consumption_idle: float = 0.12
## Additional fuel consumed per second under full acceleration throttle.
@export var fuel_consumption_throttle: float = 0.75

@export_group("Trip & Navigation")
## Starting kilometer marker (counts down toward target_kilometer).
@export var starting_kilometer: float = 85.0
## Destination kilometer goal.
@export var target_kilometer: float = 77.0

@export_group("Suspension Dynamics")
## Enables suspension dynamics: body pitch, centrifugal roll, and idle vibration shiver.
@export var enable_suspension_dynamics: bool = true
## Maximum roll angle in degrees during hard cornering.
@export var max_body_roll_deg: float = 4.2
## Speed of roll smoothing.
@export var body_roll_speed: float = 8.5
## Maximum pitch angle in degrees during hard acceleration or braking.
@export var max_body_pitch_deg: float = 3.6
## Speed of pitch smoothing.
@export var body_pitch_speed: float = 7.5
## Sensitivity factor translating acceleration (m/s^2) to pitch angle.
@export var pitch_acceleration_factor: float = 0.024
## Frequency multiplier for engine idle vibration shiver.
@export var idle_shiver_frequency: float = 25.0
## Maximum vertical displacement in meters for idle shiver.
@export var idle_shiver_amplitude: float = 0.0035

# Backward compatibility alias
var enable_body_roll: bool:
	get: return enable_suspension_dynamics
	set(val): enable_suspension_dynamics = val

@export_group("Environment & Gravity")
## Downward gravity acceleration.
@export var gravity: float = 22.0

# Backward compatibility property accessors
var acceleration: float:
	get: return acceleration_rate
	set(val): acceleration_rate = val

var braking: float:
	get: return braking_force
	set(val): braking_force = val

var normal_lateral_grip: float:
	get: return lateral_grip
	set(val): lateral_grip = val

# Runtime state
var current_steer_angle: float = 0.0
var current_grip: float = 16.0
var is_drifting: bool = false
var forward_speed_state: float = 0.0
var current_speed_kmh: float = 0.0
var distance_traveled_meters: float = 0.0
var current_kilometer: float = 85.0
var is_actively_drifting: bool = false
var _was_drifting: bool = false

# Roadside ditch / Mud zone state
var in_mud_zone: bool = false
var _mud_zones_count: int = 0
var in_shoulder_zone: bool = false
var _shoulder_zones_count: int = 0

# Off-road wheel mud & dirt particles
var _mud_particles_left: GPUParticles3D
var _mud_particles_right: GPUParticles3D

# Durability & Headlight state
var left_headlight_broken: bool = false
var right_headlight_broken: bool = false
var _chase_camera: Camera3D = null

# Collapse / stall state
var is_stalled: bool = false
var _collapse_stage: int = 0 # 0 = normal, 1 = fading lights & blacking out, 2 = 3s silence pause
var _collapse_timer: float = 0.0

# KM 77 Paradox Anomaly state
var _is_fog_anomaly: bool = false
var _fog_anomaly_timer: float = 0.0
var _world_env: WorldEnvironment = null
var _orig_fog_light_color := Color(0.04, 0.045, 0.055, 1.0)
var _orig_volumetric_fog_albedo := Color(0.05, 0.055, 0.065, 1.0)
var _anomaly_fog_color := Color(0.38, 0.05, 0.08, 1.0) # Deep ominous crimson void

var _is_flickering_glitch: bool = false
var _glitch_timer: float = 0.0
var _glitch_toggle_timer: float = 0.0

@onready var visual_root: Node3D = get_node_or_null("VisualRoot") as Node3D
@onready var visual_mesh: MeshInstance3D = _find_visual_mesh()
@onready var headlight_left: SpotLight3D = _find_headlight_left()
@onready var headlight_right: SpotLight3D = _find_headlight_right()
@onready var headlight_ground_fill: SpotLight3D = _find_headlight_ground_fill()
@onready var headlight_left_mesh: MeshInstance3D = get_node_or_null("VisualRoot/HeadlightLeftMesh") as MeshInstance3D
@onready var headlight_right_mesh: MeshInstance3D = get_node_or_null("VisualRoot/HeadlightRightMesh") as MeshInstance3D
@onready var taillight_left: MeshInstance3D = _find_taillight_left()
@onready var taillight_right: MeshInstance3D = _find_taillight_right()
@onready var brake_omni_light: OmniLight3D = get_node_or_null("BrakeLight") as OmniLight3D
@onready var reverse_omni_light: OmniLight3D = get_node_or_null("ReverseLight") as OmniLight3D
@onready var license_plate_light: OmniLight3D = get_node_or_null("LicensePlateLight") as OmniLight3D
@onready var reverse_light_left: MeshInstance3D = _find_reverse_light_left()
@onready var reverse_light_right: MeshInstance3D = _find_reverse_light_right()

@onready var wheel_fl: Node3D = get_node_or_null("VisualRoot/WheelFL") as Node3D
@onready var wheel_fr: Node3D = get_node_or_null("VisualRoot/WheelFR") as Node3D
@onready var wheel_rl: Node3D = get_node_or_null("VisualRoot/WheelRL") as Node3D
@onready var wheel_rr: Node3D = get_node_or_null("VisualRoot/WheelRR") as Node3D
@onready var wheel_roll_fl: Node3D = get_node_or_null("VisualRoot/WheelFL/WheelRoll") as Node3D
@onready var wheel_roll_fr: Node3D = get_node_or_null("VisualRoot/WheelFR/WheelRoll") as Node3D
@onready var wheel_roll_rl: Node3D = get_node_or_null("VisualRoot/WheelRL/WheelRoll") as Node3D
@onready var wheel_roll_rr: Node3D = get_node_or_null("VisualRoot/WheelRR/WheelRoll") as Node3D

var _headlight_mat: StandardMaterial3D = null
var _taillight_mat: StandardMaterial3D = null
var _reverse_light_mat: StandardMaterial3D = null

var _prev_forward_speed: float = 0.0
var _current_pitch: float = 0.0
var _current_roll: float = 0.0
var _idle_shiver_time: float = 0.0
var _idle_shiver_offset: float = 0.0
var _base_visual_root_y: float = 0.0

func _find_visual_mesh() -> MeshInstance3D:
	var m := get_node_or_null("VisualRoot/CabMesh") as MeshInstance3D
	if not m:
		m = get_node_or_null("MeshInstance3D") as MeshInstance3D
	return m

func _find_headlight_left() -> SpotLight3D:
	var light := get_node_or_null("HeadlightLeft") as SpotLight3D
	if not light and visual_root:
		light = visual_root.get_node_or_null("HeadlightLeft") as SpotLight3D
	if not light:
		light = find_child("HeadlightLeft", true, false) as SpotLight3D
	return light

func _find_headlight_right() -> SpotLight3D:
	var light := get_node_or_null("HeadlightRight") as SpotLight3D
	if not light:
		light = get_node_or_null("HeadlighRight") as SpotLight3D
	if not light and visual_root:
		light = visual_root.get_node_or_null("HeadlightRight") as SpotLight3D
	if not light:
		light = find_child("HeadlightRight", true, false) as SpotLight3D
	return light

func _find_headlight_ground_fill() -> SpotLight3D:
	var light := get_node_or_null("HeadlightGroundFill") as SpotLight3D
	if not light and visual_root:
		light = visual_root.get_node_or_null("HeadlightGroundFill") as SpotLight3D
	if not light:
		light = find_child("HeadlightGroundFill", true, false) as SpotLight3D
	return light

func _find_taillight_left() -> MeshInstance3D:
	var m := get_node_or_null("VisualRoot/TaillightLeftMesh") as MeshInstance3D
	if not m:
		m = get_node_or_null("TaillightLeft") as MeshInstance3D
	return m

func _find_taillight_right() -> MeshInstance3D:
	var m := get_node_or_null("VisualRoot/TaillightRightMesh") as MeshInstance3D
	if not m:
		m = get_node_or_null("TaillightRight") as MeshInstance3D
	return m

func _find_reverse_light_left() -> MeshInstance3D:
	return get_node_or_null("VisualRoot/ReverseLightLeftMesh") as MeshInstance3D

func _find_reverse_light_right() -> MeshInstance3D:
	return get_node_or_null("VisualRoot/ReverseLightRightMesh") as MeshInstance3D

func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 1
	if visual_root:
		_base_visual_root_y = visual_root.position.y
	_ensure_high_beams_action()
	var tree := get_tree()
	if tree and tree.current_scene:
		_world_env = tree.current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_apply_headlight_mode_instant()
	headlights_mode_changed.emit(is_high_beams_active)

	current_kilometer = starting_kilometer
	fuel_changed.emit(current_fuel, max_fuel)
	engine_health_changed.emit(current_engine_health, max_engine_health)
	distance_updated.emit(distance_traveled_meters, current_kilometer)
	speed_updated.emit(0.0)
	drift_state_changed.emit(false)

	# Setup dynamic taillight material instance
	if taillight_left and taillight_left.mesh and taillight_left.mesh.material is StandardMaterial3D:
		_taillight_mat = taillight_left.mesh.material.duplicate() as StandardMaterial3D
		taillight_left.material_override = _taillight_mat
		if taillight_right:
			taillight_right.material_override = _taillight_mat

	# Setup dynamic reverse light material instance
	if reverse_light_left and reverse_light_left.mesh and reverse_light_left.mesh.material is StandardMaterial3D:
		_reverse_light_mat = reverse_light_left.mesh.material.duplicate() as StandardMaterial3D
		reverse_light_left.material_override = _reverse_light_mat
		if reverse_light_right:
			reverse_light_right.material_override = _reverse_light_mat

	# Setup dynamic headlight lens material instance
	if headlight_left_mesh and headlight_left_mesh.mesh and headlight_left_mesh.mesh.material is StandardMaterial3D:
		_headlight_mat = headlight_left_mesh.mesh.material.duplicate() as StandardMaterial3D
		headlight_left_mesh.material_override = _headlight_mat
		if headlight_right_mesh:
			headlight_right_mesh.material_override = _headlight_mat

	# Ensure van body is weathered commercial white (#E0E0E0) for legacy mesh if unassigned
	if visual_mesh and visual_mesh.get_surface_override_material(0) == null and (visual_mesh.mesh == null or visual_mesh.mesh.material == null):
		var white_mat := StandardMaterial3D.new()
		white_mat.albedo_color = Color(0.88, 0.88, 0.88, 1.0)
		white_mat.roughness = 0.82
		white_mat.metallic = 0.05
		visual_mesh.set_surface_override_material(0, white_mat)

	_create_mud_particles()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_high_beams") and not event.is_echo():
		toggle_high_beams()

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_high_beams"):
		toggle_high_beams()

	is_drifting = Input.is_action_pressed("handbrake")

	# Check stall condition (fuel depleted or engine destroyed)
	if not is_stalled and (current_fuel <= 0.0 or current_engine_health <= 0.0):
		_start_collapse()

	if is_stalled:
		_process_collapse(delta)

	# 1. Progressive steering with speed-sensitive limits & auto-centering
	_process_steering(delta)

	# 2. Decompose existing horizontal velocity along new heading
	var forward_dir := -transform.basis.z
	var right_dir := transform.basis.x
	var current_h_vel := Vector3(velocity.x, 0.0, velocity.z)

	var fwd_speed := current_h_vel.dot(forward_dir)
	var lat_speed := current_h_vel.dot(right_dir)

	# 3. Acceleration, braking, and coasting with realistic van inertia
	fwd_speed = _process_longitudinal(fwd_speed, delta)

	# 4. Lateral grip damping & inertia preservation
	lat_speed = _process_lateral(lat_speed, delta)

	# 4b. Mud & loose shoulder surface drag when driving off-road
	if in_mud_zone:
		fwd_speed = move_toward(fwd_speed, 0.0, 16.0 * delta)
		lat_speed = move_toward(lat_speed, 0.0, 14.0 * delta)
	elif in_shoulder_zone:
		fwd_speed = move_toward(fwd_speed, 0.0, 5.0 * delta)
		lat_speed = move_toward(lat_speed, 0.0, 3.5 * delta)

	# 5. Recompose horizontal velocity vector
	var target_h_vel := (forward_dir * fwd_speed) + (right_dir * lat_speed)
	velocity.x = target_h_vel.x
	velocity.z = target_h_vel.z

	# 6. Apply gravity and solid ground contact
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	# 7. Record post-collision forward speed for telemetry and roll calculations
	var post_h_vel := Vector3(velocity.x, 0.0, velocity.z)
	forward_speed_state = post_h_vel.dot(forward_dir)

	# 8. Handle obstacle impact deceleration and debris knockback impulses
	_process_collisions(forward_dir, delta)

	# 8b. Off-road mud & gravel spray from spinning rear tires
	var should_emit_mud: bool = is_on_floor() and (in_shoulder_zone or in_mud_zone) and absf(forward_speed_state) > 1.2
	if _mud_particles_left and _mud_particles_left.emitting != should_emit_mud:
		_mud_particles_left.emitting = should_emit_mud
	if _mud_particles_right and _mud_particles_right.emitting != should_emit_mud:
		_mud_particles_right.emitting = should_emit_mud

	# 9. Update telemetry: fuel, odometer, speed km/h, and drift state
	_process_fuel(delta)
	_process_odometer(delta)
	_process_telemetry()

	# 10. Process visual anomalies, headlight strobing, and reactive taillights/reverse lights
	_process_visual_effects(delta)

	# 11. Functional rotating and steering wheels
	_process_wheel_transformations(delta)

	# 12. Visual suspension dynamics: longitudinal pitch, centrifugal roll, and idle shiver
	_process_suspension_dynamics(delta, forward_speed_state)

## Starts the vehicle shutdown and blackout sequence.
func _start_collapse() -> void:
	var root := get_tree().current_scene if get_tree() else null
	if root:
		var lrm := root.get_node_or_null("LoopResetManager")
		if lrm and lrm.has_method("start_timeline_reboot"):
			lrm.start_timeline_reboot("CRITICAL VEHICLE SHUTDOWN")
			return

	is_stalled = true
	_collapse_stage = 1
	_collapse_timer = 0.0
	vehicle_collapsed.emit()

	var hud := _find_hud()
	if hud:
		hud.fade_to_black(2.0)

	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[RADIO CRITICAL] ...vehicle telemetry flatlined... carrier signal cutting out...",
			3.5,
			true
		)

## Drives headlight fade, blackout pause, and loop reset.
func _process_collapse(delta: float) -> void:
	if _collapse_stage == 1:
		# Gradually extinguish surviving headlights and taillights
		if headlight_left and not left_headlight_broken:
			headlight_left.light_energy = move_toward(headlight_left.light_energy, 0.0, 6.0 * delta)
		if headlight_right and not right_headlight_broken:
			headlight_right.light_energy = move_toward(headlight_right.light_energy, 0.0, 6.0 * delta)
		if headlight_ground_fill:
			headlight_ground_fill.light_energy = move_toward(headlight_ground_fill.light_energy, 0.0, 6.0 * delta)
		if _taillight_mat:
			_taillight_mat.emission_energy_multiplier = move_toward(_taillight_mat.emission_energy_multiplier, 0.0, 3.5 * delta)
		if brake_omni_light:
			brake_omni_light.light_energy = move_toward(brake_omni_light.light_energy, 0.0, 3.5 * delta)
		if _reverse_light_mat:
			_reverse_light_mat.emission_energy_multiplier = move_toward(_reverse_light_mat.emission_energy_multiplier, 0.0, 3.5 * delta)
		if reverse_omni_light:
			reverse_omni_light.light_energy = move_toward(reverse_omni_light.light_energy, 0.0, 3.5 * delta)
		if license_plate_light:
			license_plate_light.light_energy = move_toward(license_plate_light.light_energy, 0.0, 3.5 * delta)

		_collapse_timer += delta
		if _collapse_timer >= 2.2:
			_collapse_stage = 2
			_collapse_timer = 0.0
			if headlight_left:
				headlight_left.visible = false
			if headlight_right:
				headlight_right.visible = false
			if headlight_ground_fill:
				headlight_ground_fill.visible = false
			if brake_omni_light:
				brake_omni_light.visible = false
			if reverse_omni_light:
				reverse_omni_light.visible = false
			if license_plate_light:
				license_plate_light.visible = false
	elif _collapse_stage == 2:
		# Silence and static in the pitch dark
		_collapse_timer += delta
		if _collapse_timer >= 3.0:
			_collapse_stage = 0
			_collapse_timer = 0.0
			reset_loop_state()

## Resets vehicle position, restores partial fuel/health, rebuilds road, and awakens in the loop.
func reset_loop_state() -> void:
	# 1. Reposition vehicle in right lane facing forward
	global_position = Vector3(3.5, 1.5, 0.0)
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	forward_speed_state = 0.0
	current_steer_angle = 0.0

	# 2. Rebuild the procedural road from origin
	var rm := _find_road_manager()
	if rm:
		rm.reset_road()

	# 3. Restore partial fuel and engine health
	current_fuel = max_fuel * 0.65
	current_engine_health = max_engine_health * 0.75
	fuel_changed.emit(current_fuel, max_fuel)
	engine_health_changed.emit(current_engine_health, max_engine_health)

	# 4. Restore headlights and taillights
	is_high_beams_active = false
	left_headlight_broken = false
	right_headlight_broken = false
	if headlight_left:
		headlight_left.visible = true
	if headlight_right:
		headlight_right.visible = true
	if headlight_ground_fill:
		headlight_ground_fill.visible = true
		headlight_ground_fill.light_energy = 7.5
	_apply_headlight_mode_instant()
	headlights_mode_changed.emit(is_high_beams_active)

	if _taillight_mat:
		_taillight_mat.emission_energy_multiplier = 0.8
	if brake_omni_light:
		brake_omni_light.visible = true
		brake_omni_light.light_energy = 0.35
	if _reverse_light_mat:
		_reverse_light_mat.emission_energy_multiplier = 0.0
	if reverse_omni_light:
		reverse_omni_light.visible = true
		reverse_omni_light.light_energy = 0.0
	if license_plate_light:
		license_plate_light.visible = true
		license_plate_light.light_energy = 0.6

	_wheel_roll_angle = 0.0
	_process_wheel_transformations(0.0)

	_current_pitch = 0.0
	_current_roll = 0.0
	_idle_shiver_offset = 0.0
	_idle_shiver_time = 0.0
	_prev_forward_speed = 0.0
	var target_suspension_node: Node3D = visual_root if visual_root else visual_mesh
	if target_suspension_node:
		target_suspension_node.rotation = Vector3.ZERO
		target_suspension_node.position.y = _base_visual_root_y

	# 5. Clear stall, mud drag, and shoulder state
	is_stalled = false
	_collapse_stage = 0
	in_mud_zone = false
	_mud_zones_count = 0
	in_shoulder_zone = false
	_shoulder_zones_count = 0
	if _mud_particles_left:
		_mud_particles_left.emitting = false
	if _mud_particles_right:
		_mud_particles_right.emitting = false

	# 6. Reset odometer back to starting marker
	starting_kilometer = 85.0
	distance_traveled_meters = 0.0
	current_kilometer = 85.0
	distance_updated.emit(distance_traveled_meters, current_kilometer)

	# 7. Reset narrative milestones
	if RadioManager.instance:
		RadioManager.instance.reset_milestones()

	# 8. Fade screen in from black
	var hud := _find_hud()
	if hud:
		hud.fade_from_black(2.5)

	# 9. Broadcast loop reset wake-up radio message
	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[DISPATCH 10-0] ...Unit 77, carrier restored at Milepost 85... did you black out at the wheel? Confirm status.",
			7.5,
			true
		)

	loop_reset_triggered.emit()

## Triggers the paradoxical loop reset when the vehicle reaches Kilómetro 77.
func _trigger_km77_paradox() -> void:
	# 1. Reset odometer back to 85.0 without interrupting driving or forward momentum!
	starting_kilometer = 85.0
	distance_traveled_meters = 0.0
	current_kilometer = 85.0
	distance_updated.emit(distance_traveled_meters, current_kilometer)

	# 2. Reset radio milestones and emit cryptic recursive broadcast
	if RadioManager.instance:
		RadioManager.instance.reset_milestones()
		RadioManager.instance.broadcast_dispatch(
			"[RADIO CORRUPT] <<! TEMPORAL RECURSION DETECTED !>> ...MILEPOST 77 BREACHED... LOOP VECTOR RE-INDEXED TO KM 85...",
			8.0,
			true
		)

	# 3. Trigger headlight strobe glitch
	_is_flickering_glitch = true
	_glitch_timer = 1.6
	_glitch_toggle_timer = 0.0

	# 4. Trigger atmospheric fog color shift anomaly
	_trigger_fog_anomaly()

	paradox_anomaly_triggered.emit()

func _trigger_fog_anomaly() -> void:
	var tree := get_tree()
	if tree and tree.current_scene:
		_world_env = tree.current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_env and _world_env.environment:
		_is_fog_anomaly = true
		_fog_anomaly_timer = 2.5
		_world_env.environment.fog_light_color = _anomaly_fog_color
		_world_env.environment.volumetric_fog_albedo = _anomaly_fog_color

func _process_visual_effects(delta: float) -> void:
	# Anomaly fog color pulse decay
	if _is_fog_anomaly:
		_fog_anomaly_timer = move_toward(_fog_anomaly_timer, 0.0, delta)
		var progress: float = _fog_anomaly_timer / 2.5
		if _world_env and _world_env.environment:
			_world_env.environment.fog_light_color = _orig_fog_light_color.lerp(_anomaly_fog_color, progress)
			_world_env.environment.volumetric_fog_albedo = _orig_volumetric_fog_albedo.lerp(_anomaly_fog_color, progress)
		if _fog_anomaly_timer <= 0.0:
			_is_fog_anomaly = false

	# Headlight glitch strobing
	if _is_flickering_glitch:
		_glitch_timer -= delta
		_glitch_toggle_timer += delta
		if _glitch_toggle_timer >= 0.08:
			_glitch_toggle_timer = 0.0
			if headlight_left and not left_headlight_broken:
				headlight_left.visible = not headlight_left.visible
			if headlight_right and not right_headlight_broken:
				headlight_right.visible = not headlight_right.visible

		if _glitch_timer <= 0.0:
			_is_flickering_glitch = false
			if headlight_left and not left_headlight_broken:
				headlight_left.visible = true
			if headlight_right and not right_headlight_broken:
				headlight_right.visible = true

	# Dynamic rear tail & reactive brake lights
	if not is_stalled:
		var is_braking: bool = (Input.is_action_pressed("brake") and forward_speed_state > 0.2) or Input.is_action_pressed("handbrake")
		var target_emission: float = 4.5 if is_braking else 0.8
		var target_omni: float = 3.5 if is_braking else 0.25
		if _taillight_mat:
			_taillight_mat.emission_energy_multiplier = move_toward(
				_taillight_mat.emission_energy_multiplier,
				target_emission,
				14.0 * delta
			)
		if brake_omni_light:
			brake_omni_light.light_energy = move_toward(
				brake_omni_light.light_energy,
				target_omni,
				12.0 * delta
			)

		# Active reverse lights: bright white rear light and illumination when reversing
		var throttle := Input.get_axis("brake", "accelerate")
		var is_reversing: bool = (forward_speed_state < -0.1) or (throttle < -0.05 and forward_speed_state <= 0.4)
		var target_reverse_emission: float = 3.5 if is_reversing else 0.0
		var target_reverse_omni: float = 2.0 if is_reversing else 0.0
		if _reverse_light_mat:
			_reverse_light_mat.emission_energy_multiplier = move_toward(
				_reverse_light_mat.emission_energy_multiplier,
				target_reverse_emission,
				14.0 * delta
			)
		if reverse_omni_light:
			reverse_omni_light.light_energy = move_toward(
				reverse_omni_light.light_energy,
				target_reverse_omni,
				12.0 * delta
			)

	# Process headlight low/high beam transition & fog backscatter
	_process_headlight_beams(delta)

var _wheel_roll_angle: float = 0.0
@export var wheel_radius: float = 0.35

func _ensure_wheel_nodes() -> void:
	if not wheel_fl:
		wheel_fl = get_node_or_null("VisualRoot/WheelFL") as Node3D
	if not wheel_fr:
		wheel_fr = get_node_or_null("VisualRoot/WheelFR") as Node3D
	if not wheel_rl:
		wheel_rl = get_node_or_null("VisualRoot/WheelRL") as Node3D
	if not wheel_rr:
		wheel_rr = get_node_or_null("VisualRoot/WheelRR") as Node3D
	if not wheel_roll_fl:
		wheel_roll_fl = get_node_or_null("VisualRoot/WheelFL/WheelRoll") as Node3D
	if not wheel_roll_fr:
		wheel_roll_fr = get_node_or_null("VisualRoot/WheelFR/WheelRoll") as Node3D
	if not wheel_roll_rl:
		wheel_roll_rl = get_node_or_null("VisualRoot/WheelRL/WheelRoll") as Node3D
	if not wheel_roll_rr:
		wheel_roll_rr = get_node_or_null("VisualRoot/WheelRR/WheelRoll") as Node3D

## Animates functional wheel rolling and front steering angles.
func _process_wheel_transformations(delta: float) -> void:
	_ensure_wheel_nodes()

	if delta > 0.0:
		var delta_roll: float = -(forward_speed_state / wheel_radius) * delta
		_wheel_roll_angle = wrapf(_wheel_roll_angle + delta_roll, -PI, PI)

	# Steer front wheels around local Y
	if wheel_fl:
		wheel_fl.rotation.y = current_steer_angle
	if wheel_fr:
		wheel_fr.rotation.y = current_steer_angle

	# Roll all 4 wheels around local X
	if wheel_roll_fl:
		wheel_roll_fl.rotation.x = _wheel_roll_angle
	if wheel_roll_fr:
		wheel_roll_fr.rotation.x = _wheel_roll_angle
	if wheel_roll_rl:
		wheel_roll_rl.rotation.x = _wheel_roll_angle
	if wheel_roll_rr:
		wheel_roll_rr.rotation.x = _wheel_roll_angle

func _ensure_high_beams_action() -> void:
	if not InputMap.has_action("toggle_high_beams"):
		InputMap.add_action("toggle_high_beams")
	for k in [KEY_F, KEY_H, KEY_L]:
		var has_key := false
		for ev in InputMap.action_get_events("toggle_high_beams"):
			if ev is InputEventKey and (ev.physical_keycode == k or ev.keycode == k):
				has_key = true
				break
		if not has_key:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event("toggle_high_beams", ev)

## Toggles between low beam and high beam headlights.
func toggle_high_beams() -> void:
	is_high_beams_active = not is_high_beams_active
	headlights_mode_changed.emit(is_high_beams_active)

## Instantly sets headlight parameters to current beam mode without smoothing.
func _apply_headlight_mode_instant() -> void:
	var target_range: float = high_beam_range if is_high_beams_active else low_beam_range
	var target_angle: float = high_beam_angle if is_high_beams_active else low_beam_angle
	var target_energy: float = high_beam_energy if is_high_beams_active else low_beam_energy
	var target_pitch: float = deg_to_rad(high_beam_pitch_deg if is_high_beams_active else low_beam_pitch_deg)
	var target_mesh_emission: float = 6.5 if is_high_beams_active else 3.2
	var target_fog_energy: float = 5.5 if is_high_beams_active else 3.8
	var target_fill_energy: float = 10.5 if is_high_beams_active else 7.5

	if headlight_left and not left_headlight_broken:
		headlight_left.rotation = Vector3(target_pitch, 0.0, 0.0)
		headlight_left.spot_range = target_range
		headlight_left.spot_angle = target_angle
		headlight_left.light_energy = target_energy
		headlight_left.volumetric_fog_energy = target_fog_energy
	if headlight_right and not right_headlight_broken:
		headlight_right.rotation = Vector3(target_pitch, 0.0, 0.0)
		headlight_right.spot_range = target_range
		headlight_right.spot_angle = target_angle
		headlight_right.light_energy = target_energy
		headlight_right.volumetric_fog_energy = target_fog_energy
	if headlight_ground_fill:
		headlight_ground_fill.rotation = Vector3.ZERO
		headlight_ground_fill.light_energy = target_fill_energy
		headlight_ground_fill.volumetric_fog_energy = 2.0
	if _headlight_mat:
		_headlight_mat.emission_energy_multiplier = target_mesh_emission

## Smoothly interpolates beam range, angle, intensity, pitch angle, and fog backscatter.
func _process_headlight_beams(delta: float) -> void:
	if not _world_env:
		var tree := get_tree()
		if tree and tree.current_scene:
			_world_env = tree.current_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment

	var target_range: float = high_beam_range if is_high_beams_active else low_beam_range
	var target_angle: float = high_beam_angle if is_high_beams_active else low_beam_angle
	var target_energy: float = high_beam_energy if is_high_beams_active else low_beam_energy
	var target_pitch: float = deg_to_rad(high_beam_pitch_deg if is_high_beams_active else low_beam_pitch_deg)
	var target_mesh_emission: float = 6.5 if is_high_beams_active else 3.2
	var target_fog_energy: float = 5.5 if is_high_beams_active else 3.8
	var target_fill_energy: float = 10.5 if is_high_beams_active else 7.5

	if not is_stalled:
		if headlight_left and not left_headlight_broken:
			headlight_left.rotation.x = move_toward(headlight_left.rotation.x, target_pitch, 8.0 * delta)
			headlight_left.rotation.y = 0.0
			headlight_left.rotation.z = 0.0
			headlight_left.spot_range = move_toward(headlight_left.spot_range, target_range, 90.0 * delta)
			headlight_left.spot_angle = move_toward(headlight_left.spot_angle, target_angle, 45.0 * delta)
			headlight_left.volumetric_fog_energy = target_fog_energy
			if not _is_flickering_glitch:
				headlight_left.light_energy = move_toward(headlight_left.light_energy, target_energy, 18.0 * delta)
		if headlight_right and not right_headlight_broken:
			headlight_right.rotation.x = move_toward(headlight_right.rotation.x, target_pitch, 8.0 * delta)
			headlight_right.rotation.y = 0.0
			headlight_right.rotation.z = 0.0
			headlight_right.spot_range = move_toward(headlight_right.spot_range, target_range, 90.0 * delta)
			headlight_right.spot_angle = move_toward(headlight_right.spot_angle, target_angle, 45.0 * delta)
			headlight_right.volumetric_fog_energy = target_fog_energy
			if not _is_flickering_glitch:
				headlight_right.light_energy = move_toward(headlight_right.light_energy, target_energy, 18.0 * delta)

		if headlight_ground_fill:
			headlight_ground_fill.rotation = Vector3.ZERO
			headlight_ground_fill.light_energy = move_toward(headlight_ground_fill.light_energy, target_fill_energy, 14.0 * delta)

		if _headlight_mat:
			_headlight_mat.emission_energy_multiplier = move_toward(
				_headlight_mat.emission_energy_multiplier,
				target_mesh_emission,
				14.0 * delta
			)

	# Volumetric fog backscatter effect: high beams illuminate atmospheric fog layers
	if _world_env and _world_env.environment and not _is_fog_anomaly:
		var target_density: float = 0.055 if is_high_beams_active else 0.040
		_world_env.environment.volumetric_fog_density = move_toward(
			_world_env.environment.volumetric_fog_density,
			target_density,
			0.03 * delta
		)

## Handles physical impacts with obstacles and vehicles: damage, speed scrub, shake, and headlight failure.
func _process_collisions(forward_dir: Vector3, _delta: float) -> void:
	var slide_count := get_slide_collision_count()
	for i in range(slide_count):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if not collider:
			continue

		var col_normal := collision.get_normal()
		var frontal_alignment := maxf(0.0, -forward_dir.dot(col_normal))
		var impact_speed := absf(forward_speed_state) * frontal_alignment

		# 1. Collision with solid barriers, heavy obstacles, or vehicles
		var is_heavy: bool = collider.is_in_group("heavy_obstacle") or collider is StaticBody3D or collider is CharacterBody3D

		if is_heavy and impact_speed > impact_speed_threshold:
			apply_collision_damage(impact_speed, collider.is_in_group("heavy_obstacle"))

		# 2. Collision with lightweight dynamic debris (RigidBody3D)
		if collider is RigidBody3D:
			var push_dir: Vector3 = -col_normal
			push_dir.y = 0.0
			push_dir = push_dir.normalized()
			var speed_magnitude := clampf(abs(forward_speed_state), 8.0, max_speed)
			var impulse: Vector3 = (push_dir * speed_magnitude * 10.0) + (Vector3.UP * 4.5)
			collider.apply_central_impulse(impulse)
			var torque := Vector3(randf_range(-6.0, 6.0), randf_range(6.0, 12.0), randf_range(-6.0, 6.0))
			collider.apply_torque_impulse(torque)

## Applies collision damage, momentum scrub, camera trauma, and headlight failure.
func apply_collision_damage(impact_speed: float, is_heavy_obstacle: bool = true) -> void:
	if impact_speed <= impact_speed_threshold:
		return

	# Damage calculation based on impact velocity
	var damage: float = (impact_speed - impact_speed_threshold) * collision_damage_factor
	if is_heavy_obstacle:
		damage *= 1.5
	current_engine_health = maxf(0.0, current_engine_health - damage)
	engine_health_changed.emit(current_engine_health, max_engine_health)

	# Severely scrub forward momentum upon direct impact
	velocity *= 0.35
	forward_speed_state *= 0.35

	# Trigger camera trauma on ChaseCamera
	var shake_trauma := clampf((impact_speed / max_speed) * camera_shake_intensity, 0.25, 1.4)
	collision_impact.emit(shake_trauma)
	_apply_camera_shake(shake_trauma)

	# Probabilistic headlight damage
	var roll_chance := headlight_break_chance_heavy if impact_speed > 14.0 else headlight_break_chance_light
	if randf() < roll_chance:
		_damage_random_headlight()

	# Check critical engine condition
	if current_engine_health <= 0.0:
		engine_critical.emit()

func _damage_random_headlight() -> void:
	var available: Array[SpotLight3D] = []
	if headlight_left and not left_headlight_broken:
		available.append(headlight_left)
	if headlight_right and not right_headlight_broken:
		available.append(headlight_right)

	if available.is_empty():
		return

	var victim: SpotLight3D = available[randi() % available.size()]
	if victim == headlight_left:
		left_headlight_broken = true
	else:
		right_headlight_broken = true

	# Disable light with flicker blackout
	victim.light_energy = 0.0
	victim.visible = false
	headlight_damaged.emit(victim.name)

## Restores fuel to the vehicle, clamping to max_fuel.
func add_fuel(amount: float) -> void:
	current_fuel = minf(max_fuel, current_fuel + amount)
	if is_stalled and current_fuel > 0.0 and current_engine_health > 0.0:
		is_stalled = false
	fuel_changed.emit(current_fuel, max_fuel)

## Restores engine health and repairs all broken headlights.
func repair_vehicle(health_amount: float = 40.0) -> void:
	current_engine_health = minf(max_engine_health, current_engine_health + health_amount)
	if is_stalled and current_fuel > 0.0 and current_engine_health > 0.0:
		is_stalled = false
	engine_health_changed.emit(current_engine_health, max_engine_health)

	var current_energy: float = high_beam_energy if is_high_beams_active else low_beam_energy
	if left_headlight_broken and headlight_left:
		left_headlight_broken = false
		headlight_left.visible = true
		headlight_left.light_energy = current_energy
	if right_headlight_broken and headlight_right:
		right_headlight_broken = false
		headlight_right.visible = true
		headlight_right.light_energy = current_energy

## Called when entering a roadside ditch mud zone.
func enter_mud_zone() -> void:
	_mud_zones_count += 1
	in_mud_zone = _mud_zones_count > 0
	if absf(forward_speed_state) > 10.0:
		# Undercarriage thump / impact from plunging into roadside ditch
		var bump_trauma := clampf((absf(forward_speed_state) / max_speed) * 0.85, 0.35, 1.0)
		collision_impact.emit(bump_trauma)
		_apply_camera_shake(bump_trauma)
		var ditch_damage: float = (absf(forward_speed_state) - 10.0) * 1.0
		current_engine_health = maxf(0.0, current_engine_health - ditch_damage)
		engine_health_changed.emit(current_engine_health, max_engine_health)

## Called when exiting a roadside ditch mud zone.
func exit_mud_zone() -> void:
	_mud_zones_count = maxi(0, _mud_zones_count - 1)
	in_mud_zone = _mud_zones_count > 0

## Called when entering a gravel/dirt shoulder zone.
func enter_shoulder_zone() -> void:
	_shoulder_zones_count += 1
	in_shoulder_zone = _shoulder_zones_count > 0

## Called when exiting a gravel/dirt shoulder zone.
func exit_shoulder_zone() -> void:
	_shoulder_zones_count = maxi(0, _shoulder_zones_count - 1)
	in_shoulder_zone = _shoulder_zones_count > 0

## Creates physical dirt and mud fragment particle emitters at the rear wheels.
func _create_mud_particles() -> void:
	var dirt_mesh := BoxMesh.new()
	dirt_mesh.size = Vector3(0.09, 0.07, 0.09)
	var dirt_mat := StandardMaterial3D.new()
	dirt_mat.albedo_color = Color(0.22, 0.17, 0.12, 1.0)
	dirt_mat.roughness = 0.95
	dirt_mesh.material = dirt_mat

	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0.0, 0.6, 1.0)
	proc_mat.spread = 28.0
	proc_mat.initial_velocity_min = 6.0
	proc_mat.initial_velocity_max = 14.0
	proc_mat.gravity = Vector3(0.0, -18.0, 0.0)
	proc_mat.scale_min = 0.6
	proc_mat.scale_max = 1.3
	proc_mat.color = Color(0.24, 0.18, 0.12, 0.95)

	# Left rear wheel emitter
	_mud_particles_left = GPUParticles3D.new()
	_mud_particles_left.name = "MudParticlesLeft"
	_mud_particles_left.amount = 32
	_mud_particles_left.lifetime = 0.4
	_mud_particles_left.local_coords = false
	_mud_particles_left.draw_pass_1 = dirt_mesh
	_mud_particles_left.process_material = proc_mat
	_mud_particles_left.position = Vector3(-0.95, 0.3, 1.8)
	_mud_particles_left.emitting = false
	add_child(_mud_particles_left)

	# Right rear wheel emitter
	_mud_particles_right = GPUParticles3D.new()
	_mud_particles_right.name = "MudParticlesRight"
	_mud_particles_right.amount = 32
	_mud_particles_right.lifetime = 0.4
	_mud_particles_right.local_coords = false
	_mud_particles_right.draw_pass_1 = dirt_mesh
	_mud_particles_right.process_material = proc_mat
	_mud_particles_right.position = Vector3(0.95, 0.3, 1.8)
	_mud_particles_right.emitting = false
	add_child(_mud_particles_right)

## Triggers erratic headlight strobing and camera shake when lingering dangerously in the dark.
func trigger_threat_glitch() -> void:
	_is_flickering_glitch = true
	_glitch_timer = 2.4
	_glitch_toggle_timer = 0.0
	_apply_camera_shake(0.85)

func _apply_camera_shake(trauma: float) -> void:
	if not is_inside_tree():
		return
	if not _chase_camera or not is_instance_valid(_chase_camera):
		var tree := get_tree()
		if tree:
			var cam_nodes := tree.get_nodes_in_group("chase_camera")
			if not cam_nodes.is_empty():
				_chase_camera = cam_nodes[0] as Camera3D
			elif get_viewport() and get_viewport().get_camera_3d():
				_chase_camera = get_viewport().get_camera_3d()
	if _chase_camera and _chase_camera.has_method("apply_shake"):
		_chase_camera.apply_shake(trauma)

func _find_hud() -> HUD:
	var tree := get_tree()
	if not tree:
		return null
	var nodes := tree.get_nodes_in_group("hud")
	if not nodes.is_empty() and nodes[0] is HUD:
		return nodes[0] as HUD
	if tree.current_scene:
		var hud_candidate := tree.current_scene.get_node_or_null("HUD") as HUD
		if hud_candidate:
			return hud_candidate
	return null

func _find_road_manager() -> RoadManager:
	var tree := get_tree()
	if not tree:
		return null
	if tree.current_scene:
		var rm := tree.current_scene.get_node_or_null("RoadManager") as RoadManager
		if rm:
			return rm
	return null

## Handles smooth progressive steering with speed-sensitive angle limits and drift oversteer.
func _process_steering(delta: float) -> void:
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var forward_dir := -transform.basis.z
	var right_dir := transform.basis.x
	var current_h_vel := Vector3(velocity.x, 0.0, velocity.z)

	var fwd_speed := current_h_vel.dot(forward_dir)
	var lat_speed := current_h_vel.dot(right_dir)
	var abs_fwd_speed := absf(fwd_speed)

	# 1. Speed-sensitive steering: scale down max steer angle at high speeds to prevent violent snap spins
	var speed_ratio: float = clampf(abs_fwd_speed / max_speed, 0.0, 1.0)
	var base_max_angle: float = deg_to_rad(max_steer_angle) if max_steer_angle > 1.5 else max_steer_angle
	# Nonlinear progressive curve: high stability at highway speed, nimble at parking/low speeds
	var speed_steer_factor: float = lerpf(1.0, high_speed_steer_ratio, pow(speed_ratio, 0.75))
	var dynamic_max_angle: float = base_max_angle * speed_steer_factor

	# 2. Smooth steering accumulator: progressive turn in with heavy van inertia and natural return
	var target_steer_angle: float = steer_input * dynamic_max_angle
	if absf(steer_input) > 0.01:
		current_steer_angle = move_toward(current_steer_angle, target_steer_angle, steer_speed * delta)
	else:
		current_steer_angle = move_toward(current_steer_angle, 0.0, steer_return_speed * delta)

	# 3. Minimum motion threshold: vehicles cannot pivot in place when stationary
	var motion_speed := abs_fwd_speed
	if is_drifting:
		# During a drift, lateral inertia allows the chassis to continue swinging
		motion_speed = maxf(motion_speed, absf(lat_speed) * 0.85)

	if motion_speed < min_steer_speed:
		return

	# 4. Turn rate calculation based on bicycle geometry (v / L) with damped high-speed yaw
	var turn_factor := clampf(motion_speed / wheelbase, 0.0, 2.8)
	var effective_oversteer: float = 1.0

	if is_drifting:
		effective_oversteer *= drift_oversteer_multiplier

		# Countersteering detection: sliding right while steering left, or sliding left while steering right
		var is_countersteering: bool = (lat_speed > 0.4 and current_steer_angle > 0.0) or \
									   (lat_speed < -0.4 and current_steer_angle < 0.0)
		if is_countersteering:
			effective_oversteer *= countersteer_boost

	var direction_sign: float = signf(fwd_speed) if abs_fwd_speed > 0.2 else 1.0
	var delta_yaw: float = current_steer_angle * turn_factor * effective_oversteer * direction_sign * delta
	rotate_y(delta_yaw)

## Updates forward/reverse speed based on throttle, heavy engine torque, fuel, and drag curves.
func _process_longitudinal(fwd_speed: float, delta: float) -> float:
	var throttle := Input.get_axis("brake", "accelerate")

	if is_stalled:
		# Engine failed or out of fuel: coast down to stop
		return move_toward(fwd_speed, 0.0, coast_deceleration * delta)

	if throttle > 0.0:
		if current_fuel <= 0.0:
			# Engine stalled out of fuel: coast to stop
			fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)
		elif fwd_speed < -0.5:
			# Traveling in reverse while throttle pressed: apply service brake to halt reverse
			fwd_speed = move_toward(fwd_speed, 0.0, braking_force * delta)
		else:
			# Progressive acceleration curve with heavy inertia:
			# - Heavy launch resistance at low speeds (0-15 km/h)
			var launch_factor: float = lerpf(0.70, 1.0, clampf(fwd_speed / 4.5, 0.0, 1.0))
			# - Drag taper approaching cruising (80-90 km/h) and top speed (~110 km/h)
			var speed_ratio: float = clampf(fwd_speed / max_speed, 0.0, 1.0)
			var drag_taper: float = clampf(1.0 - (speed_ratio * speed_ratio * 0.82), 0.18, 1.0)
			var effective_accel: float = acceleration_rate * launch_factor * drag_taper * throttle
			fwd_speed = move_toward(fwd_speed, max_speed, effective_accel * delta)
	elif throttle < 0.0:
		if fwd_speed > 0.25:
			# Service braking from forward motion: realistic stopping distance
			fwd_speed = move_toward(fwd_speed, 0.0, braking_force * delta)
		elif current_fuel <= 0.0:
			# Engine stalled out of fuel: cannot reverse
			fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)
		else:
			# Reversing with prompt vehicle torque
			var reverse_ratio: float = -throttle
			fwd_speed = move_toward(fwd_speed, -reverse_max_speed, reverse_acceleration * reverse_ratio * delta)
	else:
		# Passive coasting: vehicle inertia carries momentum
		fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)

	# Tire friction scrub during high-angle drift
	if is_drifting and absf(fwd_speed) > 1.0:
		fwd_speed = move_toward(fwd_speed, 0.0, drift_drag * delta)

	return fwd_speed

## Consumes fuel over time based on idle and throttle demand.
func _process_fuel(delta: float) -> void:
	if current_fuel <= 0.0:
		return

	var throttle := Input.get_axis("brake", "accelerate")
	var throttle_ratio := absf(throttle)
	var consumption: float = fuel_consumption_idle + (fuel_consumption_throttle * throttle_ratio)
	current_fuel = maxf(0.0, current_fuel - (consumption * delta))
	fuel_changed.emit(current_fuel, max_fuel)

	if current_fuel <= 0.0:
		fuel_depleted.emit()

## Tracks forward distance traveled and updates road kilometer progress with paradox loop check.
func _process_odometer(delta: float) -> void:
	if forward_speed_state > 0.1:
		distance_traveled_meters += forward_speed_state * delta
		var calculated_km: float = starting_kilometer - (distance_traveled_meters / 1000.0)

		# Check the Kilómetro 77 paradox trigger
		if calculated_km <= target_kilometer:
			_trigger_km77_paradox()
		else:
			current_kilometer = calculated_km
			distance_updated.emit(distance_traveled_meters, current_kilometer)

## Updates speed in km/h and tracks active drift state changes.
func _process_telemetry() -> void:
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	current_speed_kmh = h_vel.length() * 3.6
	speed_updated.emit(current_speed_kmh)

	var right_dir := transform.basis.x
	var lat_speed := absf(h_vel.dot(right_dir))
	var currently_drifting: bool = is_drifting and lat_speed > 1.2
	if currently_drifting != _was_drifting:
		_was_drifting = currently_drifting
		is_actively_drifting = currently_drifting
		drift_state_changed.emit(is_actively_drifting)

## Applies grip damping to lateral sliding velocity.
func _process_lateral(lat_speed: float, delta: float) -> float:
	var target_grip: float = drift_lateral_grip if is_drifting else lateral_grip
	if in_shoulder_zone:
		# Compromised lateral traction on loose gravel / dirt shoulder promotes oversteer & drift
		target_grip *= 0.48
	elif in_mud_zone:
		target_grip *= 0.30
	current_grip = move_toward(current_grip, target_grip, grip_recovery_speed * delta)
	return lerpf(lat_speed, 0.0, 1.0 - exp(-current_grip * delta))

## Applies visual suspension dynamics (pitch, roll, and idle vibration shiver) to VisualRoot.
func _process_suspension_dynamics(delta: float, fwd_speed: float) -> void:
	if not enable_suspension_dynamics:
		return
	if not visual_root:
		visual_root = get_node_or_null("VisualRoot") as Node3D
	var target_node: Node3D = visual_root if visual_root else visual_mesh
	if not target_node:
		return

	# 1. Pitch (longitudinal cabeceo): nose dips under heavy braking, nose lifts under acceleration
	var accel_long: float = 0.0
	if delta > 0.0:
		accel_long = (fwd_speed - _prev_forward_speed) / delta
	_prev_forward_speed = fwd_speed

	var target_pitch: float = clampf(
		accel_long * pitch_acceleration_factor,
		-deg_to_rad(max_body_pitch_deg),
		deg_to_rad(max_body_pitch_deg)
	)
	_current_pitch = lerpf(_current_pitch, target_pitch, body_pitch_speed * delta)

	# 2. Roll (balanceo lateral): body tilts toward outside of curves according to centrifugal force
	var base_max_angle: float = deg_to_rad(max_steer_angle) if max_steer_angle > 1.5 else max_steer_angle
	var steer_ratio: float = clampf(current_steer_angle / maxf(base_max_angle, 0.001), -1.0, 1.0)
	var speed_ratio: float = clampf(absf(fwd_speed) / max_speed, 0.0, 1.0)
	var drift_extra: float = 1.35 if is_drifting else 1.0

	var target_roll: float = -steer_ratio * deg_to_rad(max_body_roll_deg) * speed_ratio * drift_extra
	_current_roll = lerpf(_current_roll, target_roll, body_roll_speed * delta)

	# 3. Idle Shiver: subtle vertical procedural vibration via sin(time * 25.0) when vehicle is stopped (< 1.0 km/h)
	var is_idling: bool = absf(fwd_speed) < 0.28 and not is_stalled and current_fuel > 0.0
	if is_idling:
		_idle_shiver_time += delta * idle_shiver_frequency
		_idle_shiver_offset = sin(_idle_shiver_time) * idle_shiver_amplitude
	else:
		_idle_shiver_offset = move_toward(_idle_shiver_offset, 0.0, 0.05 * delta)

	# 4. Apply interpolated pitch, roll, and idle shiver to VisualRoot (CollisionShape3D remains static)
	target_node.rotation.x = _current_pitch
	target_node.rotation.z = _current_roll
	target_node.position.y = _base_visual_root_y + _idle_shiver_offset

## Backward compatibility alias for _process_suspension_dynamics.
func _process_visual_roll(delta: float, fwd_speed: float) -> void:
	_process_suspension_dynamics(delta, fwd_speed)
