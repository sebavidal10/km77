class_name ChaseCamera
extends Camera3D

@export var target_node: Node3D
@export var follow_speed: float = 8.0
@export var rotation_speed: float = 6.0
@export var max_shake_offset: float = 0.5
@export var shake_decay: float = 3.6

var _shake_intensity: float = 0.0

func _ready() -> void:
	add_to_group("chase_camera")

## Adds trauma for camera shake during high-speed collisions.
func apply_shake(amount: float) -> void:
	_shake_intensity = clampf(_shake_intensity + amount, 0.0, 1.5)

func _physics_process(delta: float) -> void:
	if not target_node:
		return

	# 1. Smoothly follow the CameraTarget position
	global_position = global_position.lerp(target_node.global_position, follow_speed * delta)

	# 2. Orient camera towards vehicle heading and upcoming road
	var van_node := target_node.get_parent() as Node3D
	if van_node:
		var look_target: Vector3 = van_node.global_position + (Vector3.UP * 0.85) - (van_node.global_transform.basis.z * 7.5)
		var target_transform: Transform3D = transform.looking_at(look_target, Vector3.UP)
		transform.basis = transform.basis.slerp(target_transform.basis, rotation_speed * delta)

	# 3. Apply collision impact camera shake
	if _shake_intensity > 0.001:
		_shake_intensity = move_toward(_shake_intensity, 0.0, shake_decay * delta)
		var shake_sq := _shake_intensity * _shake_intensity
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.6, 0.6),
			randf_range(-1.0, 1.0)
		) * (shake_sq * max_shake_offset)
		global_position += offset
