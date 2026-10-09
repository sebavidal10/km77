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
## Steering wheel turn speed in radians/s towards player input.
@export var steer_speed: float = 3.2
## Steering wheel auto-center speed in radians/s when steering input is released.
@export var steer_return_speed: float = 4.8
## Maximum front wheel steering angle in radians (approx 32 degrees).
@export var max_steer_angle: float = deg_to_rad(32.0)
## High-speed steering ratio (reduces max steer angle at top speed to avoid uncontrollable spins).
@export var high_speed_steer_ratio: float = 0.35
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

@export_group("Reverse & Coasting")
## Maximum reverse speed in m/s (approx 36 km/h).
@export var reverse_max_speed: float = 10.0
## Acceleration rate when reversing.
@export var reverse_acceleration: float = 5.0
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

@export_group("Visual Chassis Roll")
## Enables subtle body roll on the MeshInstance3D to convey weight shift during turns and drifts.
@export var enable_body_roll: bool = true
## Maximum roll angle in degrees during hard cornering.
@export var max_body_roll_deg: float = 3.8
## Speed of roll smoothing.
@export var body_roll_speed: float = 8.5

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

@onready var visual_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var headlight_left: SpotLight3D = get_node_or_null("HeadlightLeft") as SpotLight3D
@onready var headlight_right: SpotLight3D = _find_headlight_right()
@onready var taillight_left: MeshInstance3D = get_node_or_null("TaillightLeft") as MeshInstance3D
@onready var taillight_right: MeshInstance3D = get_node_or_null("TaillightRight") as MeshInstance3D
@onready var brake_omni_light: OmniLight3D = get_node_or_null("BrakeLight") as OmniLight3D

var _taillight_mat: StandardMaterial3D = null

func _find_headlight_right() -> SpotLight3D:
	var light := get_node_or_null("HeadlightRight") as SpotLight3D
	if not light:
		light = get_node_or_null("HeadlighRight") as SpotLight3D
	return light

func _ready() -> void:
	add_to_group("player")
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

func _physics_process(delta: float) -> void:
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

	# 5. Recompose horizontal velocity vector
	var target_h_vel := (forward_dir * fwd_speed) + (right_dir * lat_speed)
	velocity.x = target_h_vel.x
	velocity.z = target_h_vel.z

	# 6. Apply gravity and solid ground contact
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	# 7. Record post-collision forward speed for telemetry and roll calculations
	var post_h_vel := Vector3(velocity.x, 0.0, velocity.z)
	forward_speed_state = post_h_vel.dot(forward_dir)

	# 8. Handle obstacle impact deceleration and debris knockback impulses
	_process_collisions(forward_dir, delta)

	# 9. Update telemetry: fuel, odometer, speed km/h, and drift state
	_process_fuel(delta)
	_process_odometer(delta)
	_process_telemetry()

	# 10. Process visual anomalies and glitches (Fog pulse & headlight strobing)
	_process_visual_effects(delta)

	# 11. Visual chassis roll animation linked to smoothed steering angle
	_process_visual_roll(delta, forward_speed_state)

## Starts the vehicle shutdown and blackout sequence.
func _start_collapse() -> void:
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
		if _taillight_mat:
			_taillight_mat.emission_energy_multiplier = move_toward(_taillight_mat.emission_energy_multiplier, 0.0, 3.5 * delta)
		if brake_omni_light:
			brake_omni_light.light_energy = move_toward(brake_omni_light.light_energy, 0.0, 3.5 * delta)

		_collapse_timer += delta
		if _collapse_timer >= 2.2:
			_collapse_stage = 2
			_collapse_timer = 0.0
			if headlight_left:
				headlight_left.visible = false
			if headlight_right:
				headlight_right.visible = false
			if brake_omni_light:
				brake_omni_light.visible = false
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
	if headlight_left:
		headlight_left.visible = true
		headlight_left.light_energy = 10.0
	if headlight_right:
		headlight_right.visible = true
		headlight_right.light_energy = 10.0
	left_headlight_broken = false
	right_headlight_broken = false

	if _taillight_mat:
		_taillight_mat.emission_energy_multiplier = 0.8
	if brake_omni_light:
		brake_omni_light.visible = true
		brake_omni_light.light_energy = 0.25

	# 5. Clear stall state
	is_stalled = false
	_collapse_stage = 0

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
			# Damage calculation based on impact velocity
			var damage: float = (impact_speed - impact_speed_threshold) * collision_damage_factor
			if collider.is_in_group("heavy_obstacle"):
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

	if left_headlight_broken and headlight_left:
		left_headlight_broken = false
		headlight_left.visible = true
		headlight_left.light_energy = 10.0
	if right_headlight_broken and headlight_right:
		right_headlight_broken = false
		headlight_right.visible = true
		headlight_right.light_energy = 10.0

## Triggers erratic headlight strobing and camera shake when lingering dangerously in the dark.
func trigger_threat_glitch() -> void:
	_is_flickering_glitch = true
	_glitch_timer = 2.4
	_glitch_toggle_timer = 0.0
	_apply_camera_shake(0.85)

func _apply_camera_shake(trauma: float) -> void:
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
	var dynamic_max_angle: float = base_max_angle * lerpf(1.0, high_speed_steer_ratio, speed_ratio)

	# 2. Smooth steering accumulator: progressive turn in and natural self-centering
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

	# 4. Turn rate calculation based on bicycle geometry (v / L) and steering angle
	var turn_factor := clampf(motion_speed / wheelbase, 0.0, 7.0)
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
		if fwd_speed > 0.5:
			# Service braking from forward motion: realistic stopping distance
			fwd_speed = move_toward(fwd_speed, 0.0, braking_force * delta)
		elif current_fuel <= 0.0:
			# Engine stalled out of fuel: cannot reverse
			fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)
		else:
			# Reversing with heavy vehicle torque
			fwd_speed = move_toward(fwd_speed, -reverse_max_speed, reverse_acceleration * delta)
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
	var throttle_ratio := clampf(throttle, 0.0, 1.0)
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
	current_grip = move_toward(current_grip, target_grip, grip_recovery_speed * delta)
	return lerpf(lat_speed, 0.0, 1.0 - exp(-current_grip * delta))

## Applies subtle body roll to MeshInstance3D to convey weight transfer.
func _process_visual_roll(delta: float, fwd_speed: float) -> void:
	if not enable_body_roll or not visual_mesh:
		return

	var base_max_angle: float = deg_to_rad(max_steer_angle) if max_steer_angle > 1.5 else max_steer_angle
	var steer_ratio: float = clampf(current_steer_angle / maxf(base_max_angle, 0.001), -1.0, 1.0)
	var speed_ratio: float = clampf(absf(fwd_speed) / max_speed, 0.0, 1.0)
	var drift_extra: float = 1.35 if is_drifting else 1.0

	var target_roll: float = -steer_ratio * deg_to_rad(max_body_roll_deg) * speed_ratio * drift_extra
	visual_mesh.rotation.z = lerpf(visual_mesh.rotation.z, target_roll, body_roll_speed * delta)
