class_name Van
extends CharacterBody3D

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

# Headlight and camera state
var left_headlight_broken: bool = false
var right_headlight_broken: bool = false
var _chase_camera: Camera3D = null

@onready var visual_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var headlight_left: SpotLight3D = get_node_or_null("HeadlightLeft") as SpotLight3D
@onready var headlight_right: SpotLight3D = _find_headlight_right()

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

func _physics_process(delta: float) -> void:
	is_drifting = Input.is_action_pressed("handbrake")

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

	# 10. Visual chassis roll animation linked to smoothed steering angle
	_process_visual_roll(delta, forward_speed_state)

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

## Tracks forward distance traveled and updates road kilometer progress.
func _process_odometer(delta: float) -> void:
	if forward_speed_state > 0.1:
		distance_traveled_meters += forward_speed_state * delta
		current_kilometer = maxf(target_kilometer, starting_kilometer - (distance_traveled_meters / 1000.0))
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
