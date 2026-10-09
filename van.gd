class_name Van
extends CharacterBody3D

# Telemetry signals
signal fuel_changed(current_fuel: float, max_fuel: float)
signal fuel_depleted
signal distance_updated(distance_traveled_meters: float, current_kilometer: float)
signal speed_updated(speed_kmh: float)
signal drift_state_changed(is_drifting_active: bool)

@export_group("Engine & Speed")
## Maximum forward speed in meters per second (approx 137 km/h).
@export var max_speed: float = 38.0
## Forward acceleration rate toward max_speed.
@export var acceleration: float = 24.0
## Deceleration rate when applying brakes.
@export var braking: float = 32.0
## Maximum reverse speed.
@export var reverse_max_speed: float = 14.0
## Acceleration rate when reversing.
@export var reverse_acceleration: float = 16.0
## Passive coasting slowdown rate when neither throttle nor brake is pressed.
@export var coast_deceleration: float = 8.0

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

@export_group("Steering & Oversteer")
## Base turning rate in radians per second during normal driving.
@export var steer_speed: float = 2.6
## Multiplier applied to steering speed while handbrake is pressed (promotes aggressive oversteer).
@export var drift_oversteer_multiplier: float = 1.75
## Extra steering authority when countersteering into the slide to catch and balance the drift.
@export var countersteer_boost: float = 1.3
## Minimum speed (m/s) required to turn the vehicle.
@export var min_steer_speed: float = 0.5

@export_group("Drift & Lateral Grip")
## Lateral grip rate when driving normally (higher = car sticks firmly to heading).
@export var normal_lateral_grip: float = 16.0
## Lateral grip rate while handbraking (lower = vehicle slides sideways with inertia).
@export var drift_lateral_grip: float = 2.2
## Longitudinal speed scrubbed per second due to tire friction while sliding sideways.
@export var drift_drag: float = 3.5
## Speed at which tire grip recovers when handbrake is released.
@export var grip_recovery_speed: float = 12.0
## Backward compatibility aliases for friction factor.
@export var drift_friction: float = 0.88
@export var normal_friction: float = 0.98

@export_group("Visual Chassis Roll")
## Enables subtle body roll on the MeshInstance3D to convey weight shift during drifts.
@export var enable_body_roll: bool = true
## Maximum roll angle in degrees during hard cornering.
@export var max_body_roll_deg: float = 3.5
## Speed of roll smoothing.
@export var body_roll_speed: float = 10.0

@export_group("Environment & Gravity")
## Downward gravity acceleration.
@export var gravity: float = 22.0

# Runtime state
var current_grip: float = 16.0
var is_drifting: bool = false
var forward_speed_state: float = 0.0
var current_speed_kmh: float = 0.0
var distance_traveled_meters: float = 0.0
var current_kilometer: float = 85.0
var is_actively_drifting: bool = false
var _was_drifting: bool = false

@onready var visual_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

func _ready() -> void:
	add_to_group("player")
	current_kilometer = starting_kilometer
	fuel_changed.emit(current_fuel, max_fuel)
	distance_updated.emit(distance_traveled_meters, current_kilometer)
	speed_updated.emit(0.0)
	drift_state_changed.emit(false)

func _physics_process(delta: float) -> void:
	is_drifting = Input.is_action_pressed("handbrake")

	# 1. Steering & vehicle yaw rotation
	_process_steering(delta)

	# 2. Decompose existing horizontal velocity along new heading
	var forward_dir := -transform.basis.z
	var right_dir := transform.basis.x
	var current_h_vel := Vector3(velocity.x, 0.0, velocity.z)

	var fwd_speed := current_h_vel.dot(forward_dir)
	var lat_speed := current_h_vel.dot(right_dir)

	# 3. Acceleration, braking, and coasting
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

	# 7. Record post-collision forward speed for steering and roll calculations
	var post_h_vel := Vector3(velocity.x, 0.0, velocity.z)
	forward_speed_state = post_h_vel.dot(forward_dir)

	# 8. Handle obstacle impact deceleration and debris knockback impulses
	_process_collisions(forward_dir, delta)

	# 9. Update telemetry: fuel, odometer, speed km/h, and drift state
	_process_fuel(delta)
	_process_odometer(delta)
	_process_telemetry()

	# 10. Visual chassis roll animation
	_process_visual_roll(delta, forward_speed_state)

## Handles physical impacts with heavy obstacles (heavy deceleration) and pushes debris RigidBodies.
func _process_collisions(forward_dir: Vector3, _delta: float) -> void:
	var slide_count := get_slide_collision_count()
	for i in range(slide_count):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if not collider:
			continue

		# 1. Collision with heavy obstacles (e.g. wrecked vehicles)
		if collider.is_in_group("heavy_obstacle"):
			# Severely scrub forward momentum upon direct impact
			if forward_speed_state > 2.0:
				velocity = velocity * 0.25
				forward_speed_state *= 0.25

		# 2. Collision with lightweight dynamic debris (RigidBody3D)
		if collider is RigidBody3D:
			var push_dir: Vector3 = -collision.get_normal()
			push_dir.y = 0.0
			push_dir = push_dir.normalized()
			var speed_magnitude := clampf(abs(forward_speed_state), 8.0, max_speed)
			var impulse: Vector3 = (push_dir * speed_magnitude * 10.0) + (Vector3.UP * 4.5)
			collider.apply_central_impulse(impulse)
			var torque := Vector3(randf_range(-6.0, 6.0), randf_range(6.0, 12.0), randf_range(-6.0, 6.0))
			collider.apply_torque_impulse(torque)

## Handles steering yaw with drift oversteer and countersteer responsiveness.
func _process_steering(delta: float) -> void:
	var steer_input := Input.get_axis("steer_right", "steer_left")
	var forward_dir := -transform.basis.z
	var right_dir := transform.basis.x
	var current_h_vel := Vector3(velocity.x, 0.0, velocity.z)

	var fwd_speed := current_h_vel.dot(forward_dir)
	var lat_speed := current_h_vel.dot(right_dir)

	if abs(fwd_speed) > min_steer_speed or abs(lat_speed) > min_steer_speed:
		var effective_steer := steer_speed

		if is_drifting:
			effective_steer *= drift_oversteer_multiplier

			# Countersteering detection: sliding right (lat_speed > 0) while steering left (steer_input > 0)
			# or sliding left (lat_speed < 0) while steering right (steer_input < 0)
			var is_countersteering: bool = (lat_speed > 0.5 and steer_input > 0.0) or \
										   (lat_speed < -0.5 and steer_input < 0.0)
			if is_countersteering:
				effective_steer *= countersteer_boost

		var direction_sign: float = signf(fwd_speed) if abs(fwd_speed) > 0.1 else 1.0
		var turn_angle: float = steer_input * effective_steer * delta * direction_sign
		rotate_y(turn_angle)

## Updates forward/reverse speed based on throttle, fuel availability, and handbrake scrub.
func _process_longitudinal(fwd_speed: float, delta: float) -> float:
	var throttle := Input.get_axis("brake", "accelerate")

	if throttle > 0.0:
		if current_fuel <= 0.0:
			# Engine stalled out of fuel: coast to stop
			fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)
		elif fwd_speed < 0.0:
			fwd_speed = move_toward(fwd_speed, 0.0, braking * delta)
		else:
			fwd_speed = move_toward(fwd_speed, max_speed, acceleration * delta)
	elif throttle < 0.0:
		if fwd_speed > 0.5:
			fwd_speed = move_toward(fwd_speed, 0.0, braking * delta)
		elif current_fuel <= 0.0:
			# Engine stalled out of fuel: cannot reverse
			fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)
		else:
			fwd_speed = move_toward(fwd_speed, -reverse_max_speed, reverse_acceleration * delta)
	else:
		fwd_speed = move_toward(fwd_speed, 0.0, coast_deceleration * delta)

	# Tire friction scrub during high-angle drift
	if is_drifting and abs(fwd_speed) > 1.0:
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
	var target_grip: float = drift_lateral_grip if is_drifting else normal_lateral_grip
	current_grip = move_toward(current_grip, target_grip, grip_recovery_speed * delta)
	return lerp(lat_speed, 0.0, 1.0 - exp(-current_grip * delta))

## Applies subtle body roll to MeshInstance3D to convey weight transfer.
func _process_visual_roll(delta: float, fwd_speed: float) -> void:
	if not enable_body_roll or not visual_mesh:
		return

	var steer_input := Input.get_axis("steer_right", "steer_left")
	var speed_ratio := clampf(abs(fwd_speed) / max_speed, 0.0, 1.0)
	var drift_extra: float = 1.4 if is_drifting else 1.0

	var target_roll: float = -steer_input * deg_to_rad(max_body_roll_deg) * speed_ratio * drift_extra
	visual_mesh.rotation.z = lerp(visual_mesh.rotation.z, target_roll, body_roll_speed * delta)
