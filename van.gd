extends CharacterBody3D

@export var max_speed: float = 35.0
@export var acceleration: float = 20.0
@export var braking: float = 25.0
@export var steer_speed: float = 2.4
@export var drift_friction: float = 0.88
@export var normal_friction: float = 0.98

var current_speed: float = 0.0
var drift_factor: float = 1.0

func _physics_process(delta: float) -> void:
	# 1. Acceleration and braking
	var throttle := Input.get_axis("brake", "accelerate")
	if throttle > 0.0:
		current_speed = move_toward(current_speed, max_speed, acceleration * delta)
	elif throttle < 0.0:
		current_speed = move_toward(current_speed, -max_speed * 0.4, braking * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, 10.0 * delta)

	# 2. Steering and handbrake drift
	var steer := Input.get_axis("steer_right", "steer_left")
	var is_drifting := Input.is_action_pressed("handbrake")

	drift_factor = drift_friction if is_drifting else normal_friction

	if abs(current_speed) > 0.5:
		var turn_mult := 1.4 if is_drifting else 1.0
		rotate_y(steer * steer_speed * turn_mult * delta * sign(current_speed))

	# 3. Apply velocity with lateral inertia
	var forward_dir := -transform.basis.z
	var target_velocity := forward_dir * current_speed

	velocity.x = lerp(velocity.x, target_velocity.x, (1.0 - drift_factor) + delta * 2.0)
	velocity.z = lerp(velocity.z, target_velocity.z, (1.0 - drift_factor) + delta * 2.0)

	if not is_on_floor():
		velocity.y -= 9.8 * delta

	move_and_slide()
