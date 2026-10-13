class_name Hitchhiker
extends Node3D

enum State {
	IDLE_TRACKING,
	LOWERING_ARM,
	STEP_1,
	STEP_PAUSE,
	STEP_2,
	DISSOLVING,
	VANISHED
}

@export_group("Tracking")
## Maximum distance within which the hitchhiker turns to look at the player's vehicle.
@export var tracking_range: float = 35.0
## Smooth rotational speed (radians per second) when tracking the passing vehicle.
@export var turn_speed: float = 4.2
## Proximity radius in meters to consider the vehicle adjacent to the figure.
@export var proximity_dist: float = 7.0
## Speed threshold in km/h below which the player is considered stopped or crawling.
@export var stop_speed_kmh: float = 5.0
## Slipstream wind wake flutter damping speed.
@export var flutter_decay_speed: float = 1.8

var target_node: Node3D
var visual_root: Node3D
var head_node: Node3D
var torso_node: Node3D
var right_arm_node: Node3D
var coat_lower_node: Node3D
var collision_body: CollisionObject3D

var _state: State = State.IDLE_TRACKING
var _state_timer: float = 0.0
var _step_progress: float = 0.0
var _reported_proximity: bool = false

# Slipstream flutter state
var _is_fluttering: bool = false
var _flutter_timer: float = 0.0
var _flutter_intensity: float = 0.0
var _slipstream_triggered: bool = false

func _ready() -> void:
	visual_root = get_node_or_null("VisualRoot") as Node3D
	head_node = get_node_or_null("VisualRoot/Torso/Head") as Node3D
	if not head_node:
		head_node = get_node_or_null("Head") as Node3D
	torso_node = get_node_or_null("VisualRoot/Torso") as Node3D
	if not torso_node:
		torso_node = get_node_or_null("Torso") as Node3D
	right_arm_node = get_node_or_null("VisualRoot/Torso/RightArm") as Node3D
	if not right_arm_node:
		right_arm_node = get_node_or_null("RightArm") as Node3D
	coat_lower_node = get_node_or_null("VisualRoot/CoatLower") as Node3D
	if not coat_lower_node:
		coat_lower_node = get_node_or_null("CoatLower") as Node3D
	collision_body = get_node_or_null("HitchhikerCollision") as CollisionObject3D

	_find_player()

func _process(delta: float) -> void:
	if _state == State.VANISHED:
		return

	if not target_node:
		_find_player()
		if not target_node:
			return

	var to_target := target_node.global_position - global_position
	var dist := to_target.length()
	var to_vehicle_h := Vector3(to_target.x, 0.0, to_target.z)
	var target_yaw := atan2(-to_vehicle_h.x, -to_vehicle_h.z) if to_vehicle_h.length_squared() > 0.01 else rotation.y

	# Check vehicle speed
	var is_stopped_or_slow: bool = false
	var speed_kmh: float = 0.0
	if target_node is Van:
		var van := target_node as Van
		speed_kmh = van.current_speed_kmh
		is_stopped_or_slow = van.current_speed_kmh < stop_speed_kmh or van.velocity.length() < 1.4
	elif target_node is CharacterBody3D:
		var cb := target_node as CharacterBody3D
		speed_kmh = cb.velocity.length() * 3.6
		is_stopped_or_slow = speed_kmh < stop_speed_kmh

	# 1. Slipstream wind wake check on high-speed vehicle pass (> 30 km/h within 12m)
	_handle_slipstream_check(dist, speed_kmh, delta)

	# 2. Check if headlights have turned away during reactive phases
	if _state != State.IDLE_TRACKING:
		if not _are_headlights_illuminating_me():
			_instant_vanish()
			return

	# 3. State machine handling
	match _state:
		State.IDLE_TRACKING:
			_process_idle_tracking(dist, to_target, target_yaw, is_stopped_or_slow, delta)
		State.LOWERING_ARM:
			_process_lowering_arm(target_yaw, delta)
		State.STEP_1:
			_process_step(target_yaw, delta, State.STEP_PAUSE)
		State.STEP_PAUSE:
			_process_step_pause(target_yaw, delta)
		State.STEP_2:
			_process_step(target_yaw, delta, State.DISSOLVING)
		State.DISSOLVING:
			_process_dissolving(delta)

## Handles vehicle tracking and stopping detection
func _process_idle_tracking(dist: float, to_target: Vector3, target_yaw: float, is_stopped_or_slow: bool, delta: float) -> void:
	if dist <= tracking_range:
		# Ambient radio lore trigger
		if not _reported_proximity and dist <= 20.0:
			_reported_proximity = true
			if RadioManager.instance:
				RadioManager.instance.report_silhouette_proximity(global_position)

		# Check if the player stopped beside the hitchhiker (< 5 km/h within 7m)
		if dist <= proximity_dist and is_stopped_or_slow:
			_state = State.LOWERING_ARM
			_state_timer = 0.0
			if collision_body:
				collision_body.collision_layer = 0
				collision_body.collision_mask = 0
			return

		# Smooth tracking rotation to follow headlights as vehicle passes
		rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
		if head_node:
			var head_target_yaw := wrapf(target_yaw - rotation.y, -PI, PI)
			head_node.rotation.y = lerp_angle(head_node.rotation.y, head_target_yaw, turn_speed * 1.5 * delta)
			var h_dist := Vector2(to_target.x, to_target.z).length()
			var pitch: float = clampf(atan2(to_target.y, h_dist), -0.3, 0.3)
			head_node.rotation.x = lerp_angle(head_node.rotation.x, pitch, 4.0 * delta)

## Slowly lowers outstretched thumb/arm to the body side over 0.8s
func _process_lowering_arm(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 8.0 * delta)
	if head_node:
		head_node.rotation = head_node.rotation.lerp(Vector3.ZERO, 6.0 * delta)

	_state_timer += delta
	var progress := clampf(_state_timer / 0.8, 0.0, 1.0)
	if right_arm_node:
		# Outstretched hitchhiking arm drops down along side of coat
		right_arm_node.rotation.z = lerp_angle(0.0, deg_to_rad(-72.0), progress)
		right_arm_node.rotation.x = lerp_angle(0.0, deg_to_rad(8.0), progress)

	if _state_timer >= 0.8:
		_state = State.STEP_1
		_state_timer = 0.0
		_step_progress = 0.0

## Advances forward one rigid mechanical step toward passenger door
func _process_step(target_yaw: float, delta: float, next_state: State) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 8.0 * delta)
	_state_timer += delta
	var step_duration: float = 0.55
	_step_progress = clampf(_state_timer / step_duration, 0.0, 1.0)

	# Translate forward towards vehicle cabin
	if target_node:
		var dir_to_van := (target_node.global_position - global_position).normalized()
		dir_to_van.y = 0.0
		var step_speed := 0.6 / step_duration
		global_position += dir_to_van * step_speed * delta

	# Vertical step bobbing motion
	if visual_root:
		visual_root.position.y = sin(_step_progress * PI) * 0.07

	if _state_timer >= step_duration:
		if visual_root:
			visual_root.position.y = 0.0
		_state = next_state
		_state_timer = 0.0
		if _state == State.DISSOLVING:
			_start_dissolve()

## Brief freeze between steps staring into vehicle cabin
func _process_step_pause(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 8.0 * delta)
	_state_timer += delta
	if _state_timer >= 0.25:
		_state = State.STEP_2
		_state_timer = 0.0
		_step_progress = 0.0

## Checks whether van headlights are pointing towards the hitchhiker
func _are_headlights_illuminating_me() -> bool:
	if not target_node:
		return false
	var van_fwd: Vector3 = -target_node.global_transform.basis.z
	var van_to_me: Vector3 = (global_position - target_node.global_position).normalized()
	# Angle threshold: cos(80 deg) ~ 0.17
	var dot := van_fwd.dot(van_to_me)
	return dot > 0.15

## Instantly vanishes if vehicle headlights point away or turn off
func _instant_vanish() -> void:
	if _state == State.VANISHED:
		return
	_state = State.VANISHED
	queue_free()

## Triggers slipstream wind fluttering when van roars past at speed
func _handle_slipstream_check(dist: float, speed_kmh: float, delta: float) -> void:
	if speed_kmh > 30.0 and dist <= 12.0 and not _slipstream_triggered:
		_slipstream_triggered = true
		_is_fluttering = true
		_flutter_intensity = 1.0
		_flutter_timer = 0.0

	# Reset slipstream trigger once far away
	if dist > 25.0:
		_slipstream_triggered = false

	if _is_fluttering:
		_flutter_timer += delta
		var flutter_z := sin(_flutter_timer * 34.0) * _flutter_intensity * deg_to_rad(14.0)
		var flutter_x := sin(_flutter_timer * 22.0) * _flutter_intensity * deg_to_rad(8.0)
		if coat_lower_node:
			coat_lower_node.rotation.z = flutter_z
			coat_lower_node.rotation.x = flutter_x
		_flutter_intensity = maxf(0.0, _flutter_intensity - delta * flutter_decay_speed)
		if _flutter_intensity <= 0.001:
			_is_fluttering = false
			if coat_lower_node:
				coat_lower_node.rotation = Vector3.ZERO

## Begins VHS video static glitch dissolve sequence
func _start_dissolve() -> void:
	if RadioManager.instance:
		RadioManager.instance.static_burst_triggered.emit(0.85, 2.0)

	# Enable alpha transparency across all descendant meshes and fade to zero
	for mi in _collect_mesh_instances(self):
		var base_mat: StandardMaterial3D = mi.material_override as StandardMaterial3D if mi.material_override else mi.mesh.material as StandardMaterial3D
		if base_mat:
			var dup := base_mat.duplicate() as StandardMaterial3D
			dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = dup
			var tween := create_tween()
			tween.tween_property(dup, "albedo_color:a", 0.0, 0.65)

## Applies jitter and scaling noise during dissolve before freeing node
func _process_dissolving(delta: float) -> void:
	_state_timer += delta
	if visual_root:
		visual_root.position.x = randf_range(-0.06, 0.06)
		visual_root.position.z = randf_range(-0.06, 0.06)
		visual_root.scale.x = 1.0 + randf_range(-0.15, 0.15)
		visual_root.scale.y = maxf(0.01, 1.0 - (_state_timer / 0.7) * 0.95)

	if _state_timer >= 0.7:
		_state = State.VANISHED
		queue_free()

func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_collect_mesh_instances(child))
	return result

func _find_player() -> void:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		target_node = nodes[0] as Node3D
		return
	var root := get_tree().current_scene
	if root:
		var van := root.get_node_or_null("Van") as Node3D
		if van:
			target_node = van
