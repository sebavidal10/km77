extends Camera3D

@export var target_node: Node3D
@export var follow_speed: float = 8.0
@export var rotation_speed: float = 6.0

func _physics_process(delta: float) -> void:
	if not target_node:
		return

	# 1. Seguir la posición del CameraTarget suavemente
	global_position = global_position.lerp(target_node.global_position, follow_speed * delta)

	# 2. Orientar la cámara suavemente hacia el auto
	var van_node := target_node.get_parent() as Node3D
	if van_node:
		var look_target: Vector3 = van_node.global_position + Vector3.UP * 1.0
		var target_transform: Transform3D = transform.looking_at(look_target, Vector3.UP)
		transform.basis = transform.basis.slerp(target_transform.basis, rotation_speed * delta)
