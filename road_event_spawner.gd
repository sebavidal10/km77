class_name RoadEventSpawner
extends Node

const FlickerLight = preload("res://flicker_light.gd")
const RoadSegment = preload("res://road_segment.gd")

@export_group("Obstacle Probabilities")
## Chance (0.0 to 1.0) to spawn a wrecked/crashed vehicle on a chunk.
@export var crashed_car_probability: float = 0.30
## Chance (0.0 to 1.0) to spawn a cluster of traffic cones / debris on a chunk.
@export var debris_probability: float = 0.35

@export_group("Roadside Anomalies Probabilities")
## Chance (0.0 to 1.0) to spawn a rustic lamppost on a chunk.
@export var lamppost_probability: float = 0.50
## Chance (0.0 to 1.0) to spawn a mysterious dark silhouette on a chunk.
@export var silhouette_probability: float = 0.25
## Starting kilometer marker descending toward 77.
@export var starting_kilometer: int = 85
## How many chunks between each kilometer marker milestone.
@export var chunks_per_milestone: int = 2

# Internal state
var current_kilometer: int = 85
var milestone_counter: int = 0

# Shared cached materials for performance
static var _rust_metal_mat: StandardMaterial3D
static var _cabin_glass_mat: StandardMaterial3D
static var _hazard_orange_mat: StandardMaterial3D
static var _cone_white_mat: StandardMaterial3D
static var _rubble_mat: StandardMaterial3D
static var _wood_post_mat: StandardMaterial3D
static var _lantern_emission_mat: StandardMaterial3D
static var _silhouette_mat: StandardMaterial3D
static var _milestone_concrete_mat: StandardMaterial3D
static var _milestone_red_mat: StandardMaterial3D

func _ready() -> void:
	current_kilometer = starting_kilometer
	milestone_counter = 0

static func _get_rust_material() -> StandardMaterial3D:
	if not _rust_metal_mat:
		_rust_metal_mat = StandardMaterial3D.new()
		_rust_metal_mat.albedo_color = Color(0.24, 0.16, 0.13, 1.0) # Corroded metal
		_rust_metal_mat.roughness = 0.85
		_rust_metal_mat.metallic = 0.35
	return _rust_metal_mat

static func _get_cabin_glass_mat() -> StandardMaterial3D:
	if not _cabin_glass_mat:
		_cabin_glass_mat = StandardMaterial3D.new()
		_cabin_glass_mat.albedo_color = Color(0.1, 0.12, 0.14, 1.0) # Shattered dark glass
		_cabin_glass_mat.roughness = 0.5
		_cabin_glass_mat.metallic = 0.2
	return _cabin_glass_mat

static func _get_hazard_orange_mat() -> StandardMaterial3D:
	if not _hazard_orange_mat:
		_hazard_orange_mat = StandardMaterial3D.new()
		_hazard_orange_mat.albedo_color = Color(0.85, 0.35, 0.08, 1.0) # Weathered safety orange
		_hazard_orange_mat.roughness = 0.7
	return _hazard_orange_mat

static func _get_cone_white_mat() -> StandardMaterial3D:
	if not _cone_white_mat:
		_cone_white_mat = StandardMaterial3D.new()
		_cone_white_mat.albedo_color = Color(0.88, 0.88, 0.85, 1.0) # Reflective band
		_cone_white_mat.roughness = 0.6
	return _cone_white_mat

static func _get_rubble_mat() -> StandardMaterial3D:
	if not _rubble_mat:
		_rubble_mat = StandardMaterial3D.new()
		_rubble_mat.albedo_color = Color(0.18, 0.17, 0.16, 1.0) # Broken asphalt / concrete
		_rubble_mat.roughness = 0.95
	return _rubble_mat

static func _get_wood_post_mat() -> StandardMaterial3D:
	if not _wood_post_mat:
		_wood_post_mat = StandardMaterial3D.new()
		_wood_post_mat.albedo_color = Color(0.16, 0.15, 0.14, 1.0) # Aged dark wood / iron
		_wood_post_mat.roughness = 0.9
	return _wood_post_mat

static func _get_lantern_emission_mat() -> StandardMaterial3D:
	if not _lantern_emission_mat:
		_lantern_emission_mat = StandardMaterial3D.new()
		_lantern_emission_mat.albedo_color = Color(1.0, 0.82, 0.45, 1.0)
		_lantern_emission_mat.emission_enabled = true
		_lantern_emission_mat.emission = Color(1.0, 0.82, 0.45, 1.0)
		_lantern_emission_mat.emission_energy_multiplier = 2.0
	return _lantern_emission_mat

static func _get_silhouette_mat() -> StandardMaterial3D:
	if not _silhouette_mat:
		_silhouette_mat = StandardMaterial3D.new()
		_silhouette_mat.albedo_color = Color(0.015, 0.015, 0.015, 1.0) # Pitch shadow
		_silhouette_mat.roughness = 1.0
		_silhouette_mat.metallic = 0.0
	return _silhouette_mat

static func _get_milestone_concrete_mat() -> StandardMaterial3D:
	if not _milestone_concrete_mat:
		_milestone_concrete_mat = StandardMaterial3D.new()
		_milestone_concrete_mat.albedo_color = Color(0.65, 0.64, 0.62, 1.0) # Concrete post
		_milestone_concrete_mat.roughness = 0.95
	return _milestone_concrete_mat

static func _get_milestone_red_mat() -> StandardMaterial3D:
	if not _milestone_red_mat:
		_milestone_red_mat = StandardMaterial3D.new()
		_milestone_red_mat.albedo_color = Color(0.72, 0.16, 0.14, 1.0) # Faded red cap
		_milestone_red_mat.roughness = 0.8
	return _milestone_red_mat

## Populates a newly spawned RoadSegment with obstacles, roadside props, and milestone markers.
func spawn_events_for_segment(segment: RoadSegment, chunk_index: int, rng: RandomNumberGenerator) -> void:
	if not segment:
		return

	# Don't spawn hazardous obstacles on the first 2 chunks (initial player runway)
	var allow_obstacles: bool = chunk_index > 2
	var slice_count: int = segment.get_slice_count()
	if slice_count < 3:
		return

	# Track occupied slices to avoid overlapping obstacles
	var occupied_slices: Array[int] = []

	# 1. Abandoned / Crashed Vehicle Obstacle
	if allow_obstacles and rng.randf() < crashed_car_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		occupied_slices.append(slice_idx)
		_spawn_crashed_vehicle(segment, slice_idx, rng)

	# 2. Debris / Traffic Cones & Barrels
	if allow_obstacles and rng.randf() < debris_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(slice_idx):
			occupied_slices.append(slice_idx)
			_spawn_debris_cluster(segment, slice_idx, rng)

	# 3. Rustic Lampposts with Erratic Flicker
	if rng.randf() < lamppost_probability:
		var slice_idx: int = rng.randi_range(0, slice_count - 1)
		_spawn_lamppost(segment, slice_idx, rng)

	# 4. Mysterious Roadside Silhouettes
	if rng.randf() < silhouette_probability:
		var slice_idx: int = rng.randi_range(0, slice_count - 1)
		_spawn_silhouette(segment, slice_idx, rng)

	# 5. Milestone Marker (Countdown toward Kilómetro 77)
	milestone_counter += 1
	if milestone_counter >= chunks_per_milestone and current_kilometer >= 77:
		milestone_counter = 0
		var slice_idx: int = slice_count / 2
		_spawn_milestone_marker(segment, slice_idx, current_kilometer)
		current_kilometer -= 1

## Spawns an abandoned/crashed car blocking one lane with heavy collision.
func _spawn_crashed_vehicle(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	# Pick either left lane (-3.8m) or right lane (+3.8m).
	# With 16m road width, this leaves a generous 10m clear passage for drifting.
	var is_left_lane: bool = rng.randf() < 0.5
	var lateral_x: float = -3.8 if is_left_lane else 3.8
	lateral_x += rng.randf_range(-0.6, 0.6)

	var yaw_angle: float = rng.randf_range(deg_to_rad(20.0), deg_to_rad(45.0))
	if rng.randf() < 0.5:
		yaw_angle = -yaw_angle

	var wreck_body := StaticBody3D.new()
	wreck_body.name = "CrashedVehicle_%d" % slice_idx
	wreck_body.add_to_group("heavy_obstacle")
	wreck_body.collision_layer = 1
	wreck_body.collision_mask = 1

	# Chassis mesh (BoxMesh)
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(2.2, 1.3, 4.3)
	chassis_mesh.material = _get_rust_material()

	var chassis_inst := MeshInstance3D.new()
	chassis_inst.mesh = chassis_mesh
	chassis_inst.position = Vector3(0.0, 0.65, 0.0)
	wreck_body.add_child(chassis_inst)

	# Cabin roof mesh (BoxMesh)
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.9, 0.8, 2.3)
	cabin_mesh.material = _get_cabin_glass_mat()

	var cabin_inst := MeshInstance3D.new()
	cabin_inst.mesh = cabin_mesh
	cabin_inst.position = Vector3(0.0, 1.6, -0.2)
	wreck_body.add_child(cabin_inst)

	# Collision shape (BoxShape3D)
	var wreck_col := CollisionShape3D.new()
	var wreck_shape := BoxShape3D.new()
	wreck_shape.size = Vector3(2.2, 1.6, 4.4)
	wreck_col.shape = wreck_shape
	wreck_col.position = Vector3(0.0, 0.8, 0.0)
	wreck_body.add_child(wreck_col)

	# Place relative to slice transform (top of road is at Y = 0.5)
	var local_offset := Vector3(lateral_x, 0.5, 0.0)
	var local_basis := Basis(Vector3.UP, yaw_angle)
	wreck_body.transform = slice_tr * Transform3D(local_basis, local_offset)

	segment.add_child(wreck_body)

## Spawns a cluster of physics-driven debris and traffic cones that scatter upon impact.
func _spawn_debris_cluster(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var cluster_count: int = rng.randi_range(2, 4)
	var base_x: float = rng.randf_range(-4.5, 4.5)

	for i in range(cluster_count):
		var item_type := rng.randi_range(0, 1) # 0 = Traffic Cone, 1 = Debris Crate
		var offset_x: float = base_x + rng.randf_range(-1.2, 1.2)
		var offset_z: float = rng.randf_range(-2.0, 2.0)

		var rigid_body := RigidBody3D.new()
		rigid_body.name = "Debris_%d_%d" % [slice_idx, i]
		rigid_body.collision_layer = 1
		rigid_body.collision_mask = 1
		rigid_body.mass = 8.0 if item_type == 0 else 14.0
		rigid_body.angular_damp = 2.0
		rigid_body.linear_damp = 1.0

		var col_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()

		if item_type == 0:
			# Traffic Cone (Box primitive base with white band)
			box_shape.size = Vector3(0.55, 0.75, 0.55)
			col_shape.shape = box_shape
			col_shape.position = Vector3(0.0, 0.375, 0.0)
			rigid_body.add_child(col_shape)

			var cone_mesh := BoxMesh.new()
			cone_mesh.size = Vector3(0.55, 0.75, 0.55)
			cone_mesh.material = _get_hazard_orange_mat()

			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = cone_mesh
			mesh_inst.position = Vector3(0.0, 0.375, 0.0)
			rigid_body.add_child(mesh_inst)

			var stripe_mesh := BoxMesh.new()
			stripe_mesh.size = Vector3(0.57, 0.18, 0.57)
			stripe_mesh.material = _get_cone_white_mat()

			var stripe_inst := MeshInstance3D.new()
			stripe_inst.mesh = stripe_mesh
			stripe_inst.position = Vector3(0.0, 0.45, 0.0)
			rigid_body.add_child(stripe_inst)
		else:
			# Debris Block / Rubble
			var size := Vector3(rng.randf_range(0.5, 0.8), rng.randf_range(0.4, 0.6), rng.randf_range(0.5, 0.8))
			box_shape.size = size
			col_shape.shape = box_shape
			col_shape.position = Vector3(0.0, size.y * 0.5, 0.0)
			rigid_body.add_child(col_shape)

			var debris_mesh := BoxMesh.new()
			debris_mesh.size = size
			debris_mesh.material = _get_rubble_mat()

			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = debris_mesh
			mesh_inst.position = Vector3(0.0, size.y * 0.5, 0.0)
			rigid_body.add_child(mesh_inst)

		var local_offset := Vector3(offset_x, 0.5, offset_z)
		rigid_body.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
		segment.add_child(rigid_body)

## Spawns a tall rustic lamppost with an eerie OmniLight3D and flicker logic.
func _spawn_lamppost(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left_verge: bool = rng.randf() < 0.5
	# Place just outside the guardrail (guardrail inner is 8.0m, thickness 1.0m, post at 8.9m)
	var verge_x: float = -8.9 if on_left_verge else 8.9

	var lamppost_root := Node3D.new()
	lamppost_root.name = "Lamppost_%d" % slice_idx

	# Vertical timber/iron post
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.3, 5.8, 0.3)
	post_mesh.material = _get_wood_post_mat()

	var post_inst := MeshInstance3D.new()
	post_inst.mesh = post_mesh
	post_inst.position = Vector3(0.0, 2.9, 0.0)
	lamppost_root.add_child(post_inst)

	# Horizontal arm extending over guardrail toward road
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.3, 0.18, 0.18)
	arm_mesh.material = _get_wood_post_mat()

	var arm_inst := MeshInstance3D.new()
	arm_inst.mesh = arm_mesh
	var arm_offset_x: float = 0.5 if on_left_verge else -0.5
	arm_inst.position = Vector3(arm_offset_x, 5.5, 0.0)
	lamppost_root.add_child(arm_inst)

	# Lantern fixture box
	var lantern_mesh := BoxMesh.new()
	lantern_mesh.size = Vector3(0.35, 0.45, 0.35)
	lantern_mesh.material = _get_lantern_emission_mat()

	var lantern_inst := MeshInstance3D.new()
	lantern_inst.mesh = lantern_mesh
	var lantern_x: float = 1.0 if on_left_verge else -1.0
	lantern_inst.position = Vector3(lantern_x, 5.3, 0.0)
	lamppost_root.add_child(lantern_inst)

	# OmniLight3D with FlickerLight controller
	var light := FlickerLight.new()
	light.name = "FlickerLight"
	light.position = Vector3(lantern_x, 5.0, 0.0)
	light.light_color = Color(1.0, 0.78, 0.45, 1.0) # Sodium-vapor amber
	light.base_energy = 2.4
	light.omni_range = 16.0
	light.omni_attenuation = 1.3
	light.is_flickering = rng.randf() < 0.65 # 65% chance of flickering lamppost
	lamppost_root.add_child(light)

	var local_offset := Vector3(verge_x, 0.0, 0.0)
	lamppost_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(lamppost_root)

## Spawns a tall, slender dark vertical box standing silently on the shoulder.
func _spawn_silhouette(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left_verge: bool = rng.randf() < 0.5
	var verge_x: float = -8.7 if on_left_verge else 8.7
	verge_x += rng.randf_range(-0.2, 0.4) * (-1.0 if on_left_verge else 1.0)

	var silhouette_root := Node3D.new()
	silhouette_root.name = "Silhouette_%d" % slice_idx

	# Body box
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.42, 2.2, 0.32)
	body_mesh.material = _get_silhouette_mat()

	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0.0, 1.1, 0.0)
	silhouette_root.add_child(body_inst)

	# Head box
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.3, 0.32, 0.3)
	head_mesh.material = _get_silhouette_mat()

	var head_inst := MeshInstance3D.new()
	head_inst.mesh = head_mesh
	head_inst.position = Vector3(0.0, 2.35, 0.0)
	silhouette_root.add_child(head_inst)

	var local_offset := Vector3(verge_x, 0.5, 0.0)
	silhouette_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(silhouette_root)

## Spawns a roadside milestone marker counting down toward Kilómetro 77.
func _spawn_milestone_marker(segment: RoadSegment, slice_idx: int, km_value: int) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var verge_x: float = 8.6 # Right shoulder milestone

	var marker_root := Node3D.new()
	marker_root.name = "MilestoneMarker_KM%d" % km_value

	# Concrete base post
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.5, 0.9, 0.35)
	base_mesh.material = _get_milestone_concrete_mat()

	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(0.0, 0.45, 0.0)
	marker_root.add_child(base_inst)

	# Red top stripe
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.52, 0.18, 0.37)
	cap_mesh.material = _get_milestone_red_mat()

	var cap_inst := MeshInstance3D.new()
	cap_inst.mesh = cap_mesh
	cap_inst.position = Vector3(0.0, 0.85, 0.0)
	marker_root.add_child(cap_inst)

	# Text label displaying "KM 77"
	var label := Label3D.new()
	label.name = "Label3D"
	label.text = "KM\n%d" % km_value
	label.font_size = 44
	label.outline_size = 6
	label.modulate = Color(0.12, 0.12, 0.12, 1.0)
	label.outline_modulate = Color(0.9, 0.9, 0.9, 1.0)
	label.position = Vector3(0.0, 0.45, -0.19) # Front face towards oncoming vehicles
	label.rotation.y = 0.0
	marker_root.add_child(label)

	var local_offset := Vector3(verge_x, 0.5, 0.0)
	marker_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(marker_root)
