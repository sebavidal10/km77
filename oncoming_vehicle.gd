class_name OncomingVehicle
extends CharacterBody3D

signal vehicle_approaching
signal vehicle_passed
signal player_collided

@export_group("Oncoming Handling")
## Travel speed in meters per second (approx 122 km/h).
@export var speed: float = 34.0
## Distance in meters behind the player after which this vehicle despawns.
@export var despawn_distance_behind: float = 35.0
## Proximity distance in meters ahead of the player that triggers radio alert.
@export var approach_alert_distance: float = 130.0

# Waypoints along the left lane in sequence of movement
var waypoints: Array[Vector3] = []
var current_waypoint_index: int = 0
var target_player: Node3D = null
var has_signaled_approach: bool = false
var has_signaled_close_pass: bool = false
var has_signaled_passed: bool = false

# Shared cached materials
static var _headlight_lens_mat: StandardMaterial3D
static var _tire_material: StandardMaterial3D
static var _trim_material: StandardMaterial3D
static var _lamp_material: StandardMaterial3D
static var _taillamp_material: StandardMaterial3D
var _uses_forest_truck: bool = false
var _uses_hearse: bool = false

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	add_to_group("heavy_obstacle")
	add_to_group("oncoming_vehicle")
	_build_visuals_and_collision()
	_find_player()
	if not waypoints.is_empty():
		global_position = waypoints[current_waypoint_index]

static func _get_headlight_lens_mat() -> StandardMaterial3D:
	if not _headlight_lens_mat:
		_headlight_lens_mat = StandardMaterial3D.new()
		_headlight_lens_mat.albedo_color = Color(1.0, 0.78, 0.36, 1.0)
		_headlight_lens_mat.emission_enabled = true
		_headlight_lens_mat.emission = Color(1.0, 0.63, 0.20, 1.0)
		_headlight_lens_mat.emission_energy_multiplier = 3.0
	return _headlight_lens_mat

static func _get_trim_material() -> StandardMaterial3D:
	if not _trim_material:
		_trim_material = StandardMaterial3D.new()
		_trim_material.albedo_color = Color(0.025, 0.025, 0.028, 1.0)
		_trim_material.roughness = 0.76
		_trim_material.metallic = 0.25
	return _trim_material

static func _get_lamp_material() -> StandardMaterial3D:
	if not _lamp_material:
		_lamp_material = StandardMaterial3D.new()
		_lamp_material.albedo_color = Color(0.9, 0.76, 0.42, 1.0)
		_lamp_material.roughness = 0.32
		_lamp_material.emission_enabled = true
		_lamp_material.emission = Color(1.0, 0.61, 0.18, 1.0)
		_lamp_material.emission_energy_multiplier = 2.2
	return _lamp_material

static func _get_taillamp_material() -> StandardMaterial3D:
	if not _taillamp_material:
		_taillamp_material = StandardMaterial3D.new()
		_taillamp_material.albedo_color = Color(0.52, 0.025, 0.025, 1.0)
		_taillamp_material.roughness = 0.38
		_taillamp_material.emission_enabled = true
		_taillamp_material.emission = Color(0.9, 0.025, 0.018, 1.0)
		_taillamp_material.emission_energy_multiplier = 1.35
	return _taillamp_material

func _build_visuals_and_collision() -> void:
	# Mix of Gothic funeral hearses, classic sedans, and occasional forest-service trucks.
	var roll := randf()
	_uses_forest_truck = roll < 0.15
	_uses_hearse = not _uses_forest_truck and roll < 0.62
	if _uses_forest_truck:
		var truck_scene := load("res://models/route77_forest_truck.glb") as PackedScene
		if truck_scene:
			var truck_visual := truck_scene.instantiate()
			truck_visual.name = "BlenderForestTruck"
			add_child(truck_visual)
		else:
			_uses_forest_truck = false
	if not _uses_forest_truck:
		_add_lofted_sedan_shell()

	# Recessed low-poly tires and simple steel hubcaps.
	if not _tire_material:
		_tire_material = StandardMaterial3D.new()
		_tire_material.albedo_color = Color(0.018, 0.018, 0.018, 1.0)
		_tire_material.roughness = 0.96
	if not _uses_forest_truck:
		var front_z := -1.35 if _uses_hearse else -1.28
		var rear_z := 1.55 if _uses_hearse else 1.28
		for wheel_pos in [Vector3(-0.98, 0.36, front_z), Vector3(0.98, 0.36, front_z), Vector3(-0.98, 0.36, rear_z), Vector3(0.98, 0.36, rear_z)]:
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.34
			wheel_mesh.bottom_radius = 0.34
			wheel_mesh.height = 0.22
			wheel_mesh.radial_segments = 8
			wheel_mesh.material = _tire_material
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.rotation.z = PI * 0.5
			wheel.position = wheel_pos
			add_child(wheel)
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.16
			hub_mesh.bottom_radius = 0.16
			hub_mesh.height = 0.24
			hub_mesh.radial_segments = 8
			hub_mesh.material = _get_trim_material()
			var hub := MeshInstance3D.new()
			hub.mesh = hub_mesh
			hub.rotation.z = PI * 0.5
			hub.position = Vector3(wheel_pos.x * 1.12, wheel_pos.y, wheel_pos.z)
			add_child(hub)

	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(2.3, 2.35, 5.55) if _uses_forest_truck else (Vector3(2.0, 1.9, 4.95) if _uses_hearse else Vector3(2.0, 1.9, 4.35))

	var col_inst := CollisionShape3D.new()
	col_inst.name = "CollisionShape3D"
	col_inst.shape = col_shape
	col_inst.position = Vector3(0.0, 1.18, 0.0) if _uses_forest_truck else Vector3(0.0, 0.95, 0.0)
	add_child(col_inst)

	var head_z := -2.68 if _uses_forest_truck else (-2.38 if _uses_hearse else -2.20)
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.32, 0.22, 0.06)
	lens_mesh.material = _get_headlight_lens_mat()

	var left_lens := MeshInstance3D.new()
	left_lens.name = "LensLeft"
	left_lens.mesh = lens_mesh
	left_lens.position = Vector3(-0.78, 0.93, head_z) if _uses_forest_truck else Vector3(-0.64, 0.70, head_z)
	add_child(left_lens)

	var right_lens := MeshInstance3D.new()
	right_lens.name = "LensRight"
	right_lens.mesh = lens_mesh
	right_lens.position = Vector3(0.78, 0.93, head_z) if _uses_forest_truck else Vector3(0.64, 0.70, head_z)
	add_child(right_lens)

	# 3. High-Intensity High Beams (SpotLight3D)
	var left_light := SpotLight3D.new()
	left_light.name = "HeadlightLeft"
	left_light.position = left_lens.position
	left_light.light_color = Color(1.0, 0.73, 0.36, 1.0)
	left_light.light_energy = 16.0
	left_light.spot_range = 65.0
	left_light.spot_angle = 34.0
	left_light.spot_attenuation = 1.1
	add_child(left_light)

	var right_light := SpotLight3D.new()
	right_light.name = "HeadlightRight"
	right_light.position = right_lens.position
	right_light.light_color = Color(1.0, 0.73, 0.36, 1.0)
	right_light.light_energy = 16.0
	right_light.spot_range = 65.0
	right_light.spot_angle = 34.0
	right_light.spot_attenuation = 1.1
	add_child(right_light)

	if not _uses_forest_truck:
		var tail_z := 2.60 if _uses_hearse else 2.13
		_add_box("FrontIndicatorLeft", Vector3(0.14, 0.10, 0.05), Vector3(-0.82, 0.63, head_z + 0.02), _get_lamp_material())
		_add_box("FrontIndicatorRight", Vector3(0.14, 0.10, 0.05), Vector3(0.82, 0.63, head_z + 0.02), _get_lamp_material())
		_add_box("RearLampLeft", Vector3(0.18, 0.26, 0.05), Vector3(-0.74, 0.76, tail_z), _get_taillamp_material())
		_add_box("RearLampRight", Vector3(0.18, 0.26, 0.05), Vector3(0.74, 0.76, tail_z), _get_taillamp_material())
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision and collision.shape is BoxShape3D:
		(collision.shape as BoxShape3D).size = Vector3(2.3, 2.35, 5.55) if _uses_forest_truck else (Vector3(2.0, 1.9, 4.95) if _uses_hearse else Vector3(2.0, 1.9, 4.35))
		collision.position = Vector3(0.0, 1.18, 0.0) if _uses_forest_truck else Vector3(0.0, 0.95, 0.0)

func _add_lofted_sedan_shell() -> void:
	if _uses_hearse:
		var hearse_scene := load("res://models/route77_hearse.glb") as PackedScene
		if hearse_scene:
			var hearse_visual := hearse_scene.instantiate()
			hearse_visual.name = "SculptedBody"
			add_child(hearse_visual)
			return
		_uses_hearse = false
	var sedan_scene := load("res://models/route77_sedan.glb") as PackedScene
	if sedan_scene:
		var sedan_visual := sedan_scene.instantiate()
		sedan_visual.name = "SculptedBody"
		add_child(sedan_visual)

func _add_box(node_name: String, box_size: Vector3, box_position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = box_position
	add_child(instance)
	return instance

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

		# Deliver the close-pass warning after the earlier anomaly report has landed.
		if not has_signaled_close_pass and forward_rel <= 18.0 and forward_rel > 0.0:
			has_signaled_close_pass = true
			_notify_radio_close_pass()

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

func _notify_radio_close_pass() -> void:
	var high_beams_active := target_player is Van and (target_player as Van).is_high_beams_active
	if high_beams_active:
		# Spectral retaliation: headlights flare blood-crimson and pull the player's steering
		var left_l := get_node_or_null("HeadlightLeft") as SpotLight3D
		var right_l := get_node_or_null("HeadlightRight") as SpotLight3D
		if left_l:
			left_l.light_color = Color(1.0, 0.06, 0.06, 1.0)
			left_l.light_energy = 42.0
		if right_l:
			right_l.light_color = Color(1.0, 0.06, 0.06, 1.0)
			right_l.light_energy = 42.0
		if target_player is Van:
			(target_player as Van).apply_doppelganger_high_beam_curse(-1.0 if randf() < 0.5 else 1.0)
	if RadioManager.instance:
		RadioManager.instance.report_doppelganger_close_pass(high_beams_active)

func _notify_radio_collision() -> void:
	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[RADIO 10-0] ...COLISIÓN FRONTAL CONTRA EL CORTEJO FÚNEBRE EN EL SECTOR 77... SEÑAL PERDIDA...",
			7.0,
			true,
			0.95
		)
