class_name OncomingVehicle
extends CharacterBody3D

const RadioManager = preload("res://radio_manager.gd")

signal vehicle_approaching
signal vehicle_passed
signal player_collided

@export_group("Oncoming Handling")
## Travel speed in meters per second (approx 122 km/h).
@export var speed: float = 34.0
## Distance in meters behind the player after which this vehicle despawns.
@export var despawn_distance_behind: float = 35.0
## Proximity distance in meters ahead of the player that triggers radio alert.
@export var approach_alert_distance: float = 65.0

# Waypoints along the left lane in sequence of movement
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var target_player: Node3D = null
var has_signaled_approach: bool = false
var has_signaled_passed: bool = false

# Shared cached materials
static var _body_material: StandardMaterial3D
static var _headlight_lens_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	add_to_group("heavy_obstacle")
	add_to_group("oncoming_vehicle")
	_build_visuals_and_collision()
	_find_player()
	if not waypoints.is_empty():
		global_position = waypoints[current_waypoint_index]

static func _get_body_material() -> StandardMaterial3D:
	if not _body_material:
		_body_material = StandardMaterial3D.new()
		# Sinister charred pitch-black silhouette
		_body_material.albedo_color = Color(0.05, 0.05, 0.06, 1.0)
		_body_material.roughness = 0.85
		_body_material.metallic = 0.35
	return _body_material

static func _get_headlight_lens_mat() -> StandardMaterial3D:
	if not _headlight_lens_mat:
		_headlight_lens_mat = StandardMaterial3D.new()
		_headlight_lens_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		_headlight_lens_mat.emission_enabled = true
		_headlight_lens_mat.emission = Color(0.95, 0.98, 1.0, 1.0)
		_headlight_lens_mat.emission_energy_multiplier = 4.5
	return _headlight_lens_mat

func _build_visuals_and_collision() -> void:
	# 1. Main chassis primitive (BoxMesh & BoxShape3D identical in dimension to player Van)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.0, 1.5, 4.0)
	body_mesh.material = _get_body_material()

	var body_inst := MeshInstance3D.new()
	body_inst.name = "BodyMesh"
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0.0, 0.75, 0.0)
	add_child(body_inst)

	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(2.0, 1.5, 4.0)

	var col_inst := CollisionShape3D.new()
	col_inst.name = "CollisionShape3D"
	col_inst.shape = col_shape
	col_inst.position = Vector3(0.0, 0.75, 0.0)
	add_child(col_inst)

	# 2. Glowing Headlight Lenses
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.32, 0.22, 0.06)
	lens_mesh.material = _get_headlight_lens_mat()

	var left_lens := MeshInstance3D.new()
	left_lens.name = "LensLeft"
	left_lens.mesh = lens_mesh
	left_lens.position = Vector3(-0.8, 0.65, -2.02)
	add_child(left_lens)

	var right_lens := MeshInstance3D.new()
	right_lens.name = "LensRight"
	right_lens.mesh = lens_mesh
	right_lens.position = Vector3(0.8, 0.65, -2.02)
	add_child(right_lens)

	# 3. High-Intensity High Beams (SpotLight3D)
	var left_light := SpotLight3D.new()
	left_light.name = "HeadlightLeft"
	left_light.position = Vector3(-0.8, 0.65, -2.1)
	left_light.light_color = Color(0.95, 0.98, 1.0, 1.0)
	left_light.light_energy = 16.0
	left_light.spot_range = 65.0
	left_light.spot_angle = 34.0
	left_light.spot_attenuation = 1.1
	add_child(left_light)

	var right_light := SpotLight3D.new()
	right_light.name = "HeadlightRight"
	right_light.position = Vector3(0.8, 0.65, -2.1)
	right_light.light_color = Color(0.95, 0.98, 1.0, 1.0)
	right_light.light_energy = 16.0
	right_light.spot_range = 65.0
	right_light.spot_angle = 34.0
	right_light.spot_attenuation = 1.1
	add_child(right_light)

func setup_waypoints(points: Array[Vector3], player_node: Node3D = null) -> void:
	waypoints = points
	current_waypoint_index = 0
	target_player = player_node
	if not waypoints.is_empty():
		position = waypoints[0]
		if is_inside_tree():
			global_position = waypoints[0]
		if waypoints.size() > 1:
			var initial_dir := (waypoints[1] - waypoints[0]).normalized()
			if initial_dir.length_squared() > 0.01:
				var initial_yaw := atan2(-initial_dir.x, -initial_dir.z)
				rotation.y = initial_yaw

func _find_player() -> void:
	if target_player:
		return
	var tree := get_tree()
	if not tree:
		return
	var nodes := tree.get_nodes_in_group("player")
	if not nodes.is_empty():
		target_player = nodes[0] as Node3D
		return
	var root := tree.current_scene
	if root:
		target_player = root.get_node_or_null("Van") as Node3D

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if not target_player:
		_find_player()

	if waypoints.is_empty():
		queue_free()
		return

	# 1. Waypoint path following
	if current_waypoint_index < waypoints.size():
		var target_pt := waypoints[current_waypoint_index]
		var to_target := target_pt - global_position
		to_target.y = 0.0

		if to_target.length() < 3.2:
			current_waypoint_index += 1
			if current_waypoint_index >= waypoints.size():
				queue_free()
				return
			target_pt = waypoints[current_waypoint_index]
			to_target = target_pt - global_position
			to_target.y = 0.0

		var move_dir := to_target.normalized()
		if move_dir.length_squared() > 0.01:
			var target_yaw := atan2(-move_dir.x, -move_dir.z)
			rotation.y = rotate_toward(rotation.y, target_yaw, 8.0 * delta)

		velocity = -transform.basis.z * speed
		velocity.y = -1.0
		move_and_slide()

		# Check collision with player
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var collider := col.get_collider()
			if collider and (collider.is_in_group("player") or collider is Van):
				player_collided.emit()
				_notify_radio_collision()
				queue_free()
				return
	else:
		queue_free()
		return

	# 2. Player proximity and despawn progression
	if target_player and is_instance_valid(target_player):
		var to_vehicle := global_position - target_player.global_position
		var player_fwd := -target_player.global_transform.basis.z
		var forward_rel := to_vehicle.dot(player_fwd)

		# Alert radio when headlights pierce into view
		if not has_signaled_approach and forward_rel < approach_alert_distance and forward_rel > 0.0:
			has_signaled_approach = true
			vehicle_approaching.emit()
			_notify_radio_approach()

		# Mark passed when vehicle goes behind the player
		if not has_signaled_passed and forward_rel < -2.0:
			has_signaled_passed = true
			vehicle_passed.emit()

		# Despawn once well behind the player
		if forward_rel < -despawn_distance_behind:
			queue_free()

func _notify_radio_approach() -> void:
	if RadioManager.instance:
		RadioManager.instance.report_doppelganger_encounter()

func _notify_radio_collision() -> void:
	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[RADIO 10-0] ...HEAVY 10-50 HEAD-ON COLLISION REPORTED ON KM 77 SECTOR... SIGNAL LOST...",
			7.0,
			true,
			0.95
		)
