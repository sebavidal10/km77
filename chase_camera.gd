class_name ChaseCamera
extends Camera3D

@export var target_node: Node3D
@export var follow_speed: float = 8.0
@export var rotation_speed: float = 6.0
@export var max_shake_offset: float = 0.5
@export var shake_decay: float = 3.6

@export_group("Dynamic Speed Dynamics")
## Base camera FOV at 0 km/h.
@export var base_fov: float = 65.0
## Widened camera FOV at highway cruising speeds (~110 km/h).
@export var max_fov: float = 70.0
## Smooth interpolation rate for FOV widening.
@export var fov_lerp_speed: float = 3.5
## Maximum high-frequency micro-shake offset distance at top speed.
@export var max_micro_shake_offset: float = 0.038

var _shake_intensity: float = 0.0
var _micro_shake_timer: float = 0.0

func _ready() -> void:
	add_to_group("chase_camera")
	fov = base_fov
	_ensure_target()
	if target_node:
		global_position = target_node.global_position
		var van_node := target_node.get_parent() as Node3D
		if van_node:
			var look_target: Vector3 = van_node.global_position + (Vector3.UP * 0.4) - (van_node.global_transform.basis.z * 4.0)
			transform = transform.looking_at(look_target, Vector3.UP)

func _ensure_target() -> void:
	if target_node and is_instance_valid(target_node):
		return
	var tree := get_tree()
	if tree:
		var vans := tree.get_nodes_in_group("player")
		if not vans.is_empty():
			target_node = vans[0].get_node_or_null("CameraTarget") as Node3D

## Adds trauma for camera shake during high-speed collisions.
func apply_shake(amount: float) -> void:
	_shake_intensity = clampf(_shake_intensity + amount, 0.0, 1.5)

func _physics_process(delta: float) -> void:
	if not target_node or not is_instance_valid(target_node):
		_ensure_target()
		if not target_node:
			return

	# 1. Smoothly follow the CameraTarget position
	global_position = global_position.lerp(target_node.global_position, follow_speed * delta)

	# 2. Orient camera towards vehicle heading and highway ahead with slight downward pitch over van roof
	var van_node := target_node.get_parent() as Node3D
	var speed_kmh: float = 0.0
	if van_node:
		if van_node is Van:
			speed_kmh = (van_node as Van).current_speed_kmh
		elif "current_speed_kmh" in van_node:
			speed_kmh = float(van_node.current_speed_kmh)
		elif "velocity" in van_node:
			var v: Vector3 = van_node.velocity
			speed_kmh = Vector3(v.x, 0.0, v.z).length() * 3.6

		# Look target adjusted to achieve comfortable downward pitch (~19° to 20°) looking over the roof toward the road ahead
		var look_target: Vector3 = van_node.global_position + (Vector3.UP * 0.4) - (van_node.global_transform.basis.z * 4.0)
		var target_transform: Transform3D = transform.looking_at(look_target, Vector3.UP)
		transform.basis = transform.basis.slerp(target_transform.basis, rotation_speed * delta)

	# 3. Dynamic FOV: smoothly widen camera FOV from 70° (at 0 km/h) to 78° (at 110 km/h) using lerp()
	var speed_ratio: float = clampf(speed_kmh / 110.0, 0.0, 1.0)
	var target_fov: float = lerpf(base_fov, max_fov, speed_ratio)
	fov = lerpf(fov, target_fov, fov_lerp_speed * delta)

	# 4. Subtle high-frequency micro-shake proportional to velocity (cruising above 80 km/h up to 110 km/h)
	if speed_kmh > 25.0:
		var micro_ratio: float = clampf((speed_kmh - 25.0) / 85.0, 0.0, 1.0)
		var micro_factor: float = pow(micro_ratio, 1.25)
		_micro_shake_timer += delta * 52.0
		var micro_offset := Vector3(
			sin(_micro_shake_timer * 1.3) * 0.5 + randf_range(-0.5, 0.5),
			sin(_micro_shake_timer * 2.1) * 0.7 + randf_range(-0.3, 0.3),
			cos(_micro_shake_timer * 1.7) * 0.5 + randf_range(-0.5, 0.5)
		) * (micro_factor * max_micro_shake_offset)
		global_position += micro_offset

	# 5. Apply collision impact camera shake
	if _shake_intensity > 0.001:
		_shake_intensity = move_toward(_shake_intensity, 0.0, shake_decay * delta)
		var shake_sq := _shake_intensity * _shake_intensity
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.6, 0.6),
			randf_range(-1.0, 1.0)
		) * (shake_sq * max_shake_offset)
		global_position += offset
