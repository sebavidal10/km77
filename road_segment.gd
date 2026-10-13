class_name RoadSegment
extends Node3D

enum SegmentType {
	STRAIGHT,
	CURVE_LEFT,
	CURVE_RIGHT
}

@export_group("Segment Configuration")
## Type of road segment: straight, curved left, or curved right.
@export var segment_type: SegmentType = SegmentType.STRAIGHT
## Total longitudinal depth/length of the segment in meters.
@export var segment_length: float = 80.0
## Total driveable road width in meters (two 7.0m lanes).
@export var road_width: float = 14.0
## Thickness of the road floor slab.
@export var road_thickness: float = 1.0
## Total turning angle in degrees for curved segments.
@export var curve_angle_deg: float = 22.5
## Number of geometric primitive slices used to construct smooth curves.
@export var slice_count: int = 8

@export_group("Shoulders & Ditches")
## Width in meters of the flat dirt/gravel shoulder on each side of the asphalt.
@export var shoulder_width: float = 2.6
## Depth in meters of the roadside drainage ditch channel.
@export var ditch_depth: float = 0.65
## Width in meters of each sloped bank of the drainage ditch channel.
@export var ditch_slope_width: float = 2.4

@export_group("Guardrails")
## Height of lateral barrier guardrails on outer curves.
@export var barrier_height: float = 3.0
## Thickness of the barrier guardrail boxes.
@export var barrier_thickness: float = 1.0

# Node references
var static_body: StaticBody3D
var exit_marker: Marker3D
var slice_transforms: Array[Transform3D] = []

# Static shared materials to optimize draw calls and shader memory
static var _road_material: StandardMaterial3D
static var _shoulder_material: StandardMaterial3D
static var _ditch_material: StandardMaterial3D
static var _barrier_material: StandardMaterial3D
static var _guardrail_post_mat: StandardMaterial3D
static var _marking_material: StandardMaterial3D
static var _fog_line_material: StandardMaterial3D
static var _reflector_amber_mat: StandardMaterial3D
static var _sign_post_mat: StandardMaterial3D
static var _telegraph_wood_mat: StandardMaterial3D
static var _cable_wire_mat: StandardMaterial3D
static var _insulator_mat: StandardMaterial3D

static func get_road_material() -> StandardMaterial3D:
	if not _road_material:
		_road_material = StandardMaterial3D.new()
		# Wet dark rural asphalt with glossy rain puddle noise
		_road_material.albedo_color = Color(0.125, 0.13, 0.145, 1.0)
		_road_material.roughness = 0.24 # Glossy wet asphalt baseline
		_road_material.metallic = 0.05
		_road_material.metallic_specular = 0.85

		# Procedural puddle noise texture modulates surface roughness
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.04
		noise.fractal_octaves = 3
		var noise_tex := NoiseTexture2D.new()
		noise_tex.width = 256
		noise_tex.height = 256
		noise_tex.seamless = true
		noise_tex.noise = noise
		_road_material.roughness_texture = noise_tex
		_road_material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return _road_material

static func get_shoulder_material() -> StandardMaterial3D:
	if not _shoulder_material:
		_shoulder_material = StandardMaterial3D.new()
		# Compacted gravel and unpaved damp dirt shoulder
		_shoulder_material.albedo_color = Color(0.24, 0.21, 0.18, 1.0)
		_shoulder_material.roughness = 0.82
		_shoulder_material.metallic = 0.02
	return _shoulder_material

static func get_ditch_material() -> StandardMaterial3D:
	if not _ditch_material:
		_ditch_material = StandardMaterial3D.new()
		# Deep muddy roadside ditch soil with damp sheen
		_ditch_material.albedo_color = Color(0.10, 0.09, 0.07, 1.0)
		_ditch_material.roughness = 0.42
		_ditch_material.metallic = 0.04
	return _ditch_material

static func get_barrier_material() -> StandardMaterial3D:
	if not _barrier_material:
		_barrier_material = StandardMaterial3D.new()
		# Galvanized corrugated metallic W-beam guardrail
		_barrier_material.albedo_color = Color(0.44, 0.46, 0.50, 1.0)
		_barrier_material.roughness = 0.32
		_barrier_material.metallic = 0.85
	return _barrier_material

static func get_guardrail_post_material() -> StandardMaterial3D:
	if not _guardrail_post_mat:
		_guardrail_post_mat = StandardMaterial3D.new()
		# Weathered dark steel / timber guardrail post
		_guardrail_post_mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
		_guardrail_post_mat.roughness = 0.85
		_guardrail_post_mat.metallic = 0.35
	return _guardrail_post_mat

static func get_marking_material() -> StandardMaterial3D:
	if not _marking_material:
		_marking_material = StandardMaterial3D.new()
		# High-visibility retro-reflective yellow markings with wet reflection
		_marking_material.albedo_color = Color(1.0, 0.85, 0.05, 1.0)
		_marking_material.roughness = 0.20
		_marking_material.metallic = 0.05
		_marking_material.emission_enabled = true
		_marking_material.emission = Color(1.0, 0.85, 0.05, 1.0)
		_marking_material.emission_energy_multiplier = 0.85
	return _marking_material

static func get_fog_line_material() -> StandardMaterial3D:
	if not _fog_line_material:
		_fog_line_material = StandardMaterial3D.new()
		# Solid white retro-reflective edge fog lines
		_fog_line_material.albedo_color = Color(0.92, 0.92, 0.90, 1.0)
		_fog_line_material.roughness = 0.26
		_fog_line_material.metallic = 0.05
		_fog_line_material.emission_enabled = true
		_fog_line_material.emission = Color(0.85, 0.85, 0.82, 1.0)
		_fog_line_material.emission_energy_multiplier = 0.45
	return _fog_line_material

static func get_reflector_amber_material() -> StandardMaterial3D:
	if not _reflector_amber_mat:
		_reflector_amber_mat = StandardMaterial3D.new()
		# High-visibility retro-reflective amber (#FFA000) for highway curve delineators
		_reflector_amber_mat.albedo_color = Color(1.0, 0.62, 0.0, 1.0)
		_reflector_amber_mat.roughness = 0.25
		_reflector_amber_mat.emission_enabled = true
		_reflector_amber_mat.emission = Color(1.0, 0.6, 0.02, 1.0)
		_reflector_amber_mat.emission_energy_multiplier = 1.35
	return _reflector_amber_mat

static func get_sign_post_material() -> StandardMaterial3D:
	if not _sign_post_mat:
		_sign_post_mat = StandardMaterial3D.new()
		_sign_post_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
		_sign_post_mat.roughness = 0.85
	return _sign_post_mat

static func get_telegraph_wood_material() -> StandardMaterial3D:
	if not _telegraph_wood_mat:
		_telegraph_wood_mat = StandardMaterial3D.new()
		_telegraph_wood_mat.albedo_color = Color(0.18, 0.15, 0.12, 1.0)
		_telegraph_wood_mat.roughness = 0.92
	return _telegraph_wood_mat

static func get_cable_wire_material() -> StandardMaterial3D:
	if not _cable_wire_mat:
		_cable_wire_mat = StandardMaterial3D.new()
		_cable_wire_mat.albedo_color = Color(0.05, 0.05, 0.06, 1.0)
		_cable_wire_mat.roughness = 0.8
	return _cable_wire_mat

static func get_insulator_material() -> StandardMaterial3D:
	if not _insulator_mat:
		_insulator_mat = StandardMaterial3D.new()
		_insulator_mat.albedo_color = Color(0.72, 0.82, 0.78, 1.0)
		_insulator_mat.roughness = 0.1
		_insulator_mat.metallic = 0.25
	return _insulator_mat

func _ready() -> void:
	if not static_body:
		build_segment()

## Builds all road slices, collision shapes, and guardrails from Box primitives.
func build_segment() -> void:
	slice_transforms.clear()
	# Clear any previous child nodes if re-building
	for child in get_children():
		child.queue_free()

	static_body = StaticBody3D.new()
	static_body.name = "StaticBody3D"
	add_child(static_body)

	exit_marker = Marker3D.new()
	exit_marker.name = "ExitTransform"
	add_child(exit_marker)

	# Determine total rotation angle for this chunk
	var total_yaw_rad := 0.0
	match segment_type:
		SegmentType.STRAIGHT:
			total_yaw_rad = 0.0
		SegmentType.CURVE_LEFT:
			total_yaw_rad = deg_to_rad(curve_angle_deg)
		SegmentType.CURVE_RIGHT:
			total_yaw_rad = deg_to_rad(-curve_angle_deg)

	var slices: int = maxi(1, slice_count)
	var slice_length: float = segment_length / float(slices)
	var delta_yaw: float = total_yaw_rad / float(slices)

	# Slight overlap on primitive visual meshes to ensure zero visual gaps between adjacent slices
	var overlap: float = 0.35
	var slice_box_length: float = slice_length + overlap
	var col_box_length: float = slice_length + 0.02
	var barrier_box_length: float = slice_length + overlap * 1.5

	var current_pos := Vector3.ZERO
	var current_yaw := 0.0

	var road_mat := get_road_material()
	var barrier_mat := get_barrier_material()

	for i in range(slices):
		var mid_yaw: float = current_yaw + (delta_yaw * 0.5)
		var mid_fwd := Vector3(-sin(mid_yaw), 0.0, -cos(mid_yaw))
		var slice_center: Vector3 = current_pos + (mid_fwd * (slice_length * 0.5))

		var slice_basis := Basis(Vector3.UP, mid_yaw)
		var slice_transform := Transform3D(slice_basis, slice_center)
		slice_transforms.append(slice_transform)

		# 1. Road surface box (primitive MeshInstance3D & CollisionShape3D)
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(road_width, road_thickness, slice_box_length)
		road_mesh.material = road_mat

		var road_mesh_instance := MeshInstance3D.new()
		road_mesh_instance.name = "RoadMesh_%d" % i
		road_mesh_instance.mesh = road_mesh
		road_mesh_instance.transform = slice_transform
		static_body.add_child(road_mesh_instance)

		var road_shape := BoxShape3D.new()
		road_shape.size = Vector3(road_width, road_thickness, col_box_length)

		var road_col := CollisionShape3D.new()
		road_col.name = "RoadCol_%d" % i
		road_col.shape = road_shape
		road_col.transform = slice_transform
		static_body.add_child(road_col)

		# 2. Center Dividing Line (Two-lane road markings)
		var marking_mat := get_marking_material()
		var marking_y: float = (road_thickness * 0.5) + 0.015 # Slightly above asphalt to avoid z-fighting

		if segment_type == SegmentType.STRAIGHT:
			# Dashed yellow line on straights (e.g. 5.5m dash per 10m slice)
			var dash_length: float = slice_length * 0.55
			var dash_mesh := BoxMesh.new()
			dash_mesh.size = Vector3(0.24, 0.02, dash_length)
			dash_mesh.material = marking_mat

			var dash_instance := MeshInstance3D.new()
			dash_instance.name = "CenterLine_%d" % i
			dash_instance.mesh = dash_mesh
			var dash_local := Vector3(0.0, marking_y, 0.0)
			dash_instance.transform = Transform3D(slice_basis, slice_center + slice_basis * dash_local)
			static_body.add_child(dash_instance)
		else:
			# Double solid yellow lines on curves (highway no-passing zone)
			var stripe_width: float = 0.16
			var stripe_spacing: float = 0.22

			# Left solid stripe
			var stripe_left_mesh := BoxMesh.new()
			stripe_left_mesh.size = Vector3(stripe_width, 0.02, slice_box_length)
			stripe_left_mesh.material = marking_mat

			var stripe_left_inst := MeshInstance3D.new()
			stripe_left_inst.name = "CenterLineLeft_%d" % i
			stripe_left_inst.mesh = stripe_left_mesh
			var left_stripe_local := Vector3(-stripe_spacing * 0.5, marking_y, 0.0)
			stripe_left_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * left_stripe_local)
			static_body.add_child(stripe_left_inst)

			# Right solid stripe
			var stripe_right_mesh := BoxMesh.new()
			stripe_right_mesh.size = Vector3(stripe_width, 0.02, slice_box_length)
			stripe_right_mesh.material = marking_mat

			var stripe_right_inst := MeshInstance3D.new()
			stripe_right_inst.name = "CenterLineRight_%d" % i
			stripe_right_inst.mesh = stripe_right_mesh
			var right_stripe_local := Vector3(stripe_spacing * 0.5, marking_y, 0.0)
			stripe_right_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * right_stripe_local)
			static_body.add_child(stripe_right_inst)

		var half_road: float = road_width * 0.5

		# Solid white retro-reflective edge fog lines (demarcating asphalt edge from shoulder)
		var fog_line_mat := get_fog_line_material()
		var fog_line_offset_x: float = half_road - 0.35
		var fog_line_width: float = 0.20

		# Left fog line
		var fog_left_mesh := BoxMesh.new()
		fog_left_mesh.size = Vector3(fog_line_width, 0.02, slice_box_length)
		fog_left_mesh.material = fog_line_mat

		var fog_left_inst := MeshInstance3D.new()
		fog_left_inst.name = "FogLineLeft_%d" % i
		fog_left_inst.mesh = fog_left_mesh
		var fog_left_local := Vector3(-fog_line_offset_x, marking_y, 0.0)
		fog_left_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * fog_left_local)
		static_body.add_child(fog_left_inst)

		# Right fog line
		var fog_right_mesh := BoxMesh.new()
		fog_right_mesh.size = Vector3(fog_line_width, 0.02, slice_box_length)
		fog_right_mesh.material = fog_line_mat

		var fog_right_inst := MeshInstance3D.new()
		fog_right_inst.name = "FogLineRight_%d" % i
		fog_right_inst.mesh = fog_right_mesh
		var fog_right_local := Vector3(fog_line_offset_x, marking_y, 0.0)
		fog_right_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * fog_right_local)
		static_body.add_child(fog_right_inst)

		# 3. Flat Compacted Dirt/Gravel Shoulders (Bermas) on both sides (flush with road top at Y = +0.5)
		var shoulder_mat := get_shoulder_material()
		var shoulder_center_x: float = half_road + (shoulder_width * 0.5)
		var sh_col_width: float = shoulder_width + 0.4 # Slight overlap with asphalt & ditch to eliminate seams

		# Left Shoulder
		var left_sh_mesh := BoxMesh.new()
		left_sh_mesh.size = Vector3(shoulder_width, road_thickness, slice_box_length)
		left_sh_mesh.material = shoulder_mat

		var left_sh_inst := MeshInstance3D.new()
		left_sh_inst.name = "ShoulderLeftMesh_%d" % i
		left_sh_inst.mesh = left_sh_mesh
		var left_sh_local := Vector3(-shoulder_center_x, 0.0, 0.0)
		left_sh_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * left_sh_local)
		static_body.add_child(left_sh_inst)

		var left_sh_col := CollisionShape3D.new()
		var left_sh_shape := BoxShape3D.new()
		left_sh_shape.size = Vector3(sh_col_width, road_thickness, col_box_length + 0.25)
		left_sh_col.name = "ShoulderLeftCol_%d" % i
		left_sh_col.shape = left_sh_shape
		left_sh_col.transform = Transform3D(slice_basis, slice_center + slice_basis * left_sh_local)
		static_body.add_child(left_sh_col)

		# Right Shoulder
		var right_sh_mesh := BoxMesh.new()
		right_sh_mesh.size = Vector3(shoulder_width, road_thickness, slice_box_length)
		right_sh_mesh.material = shoulder_mat

		var right_sh_inst := MeshInstance3D.new()
		right_sh_inst.name = "ShoulderRightMesh_%d" % i
		right_sh_inst.mesh = right_sh_mesh
		var right_sh_local := Vector3(shoulder_center_x, 0.0, 0.0)
		right_sh_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * right_sh_local)
		static_body.add_child(right_sh_inst)

		var right_sh_col := CollisionShape3D.new()
		var right_sh_shape := BoxShape3D.new()
		right_sh_shape.size = Vector3(sh_col_width, road_thickness, col_box_length + 0.25)
		right_sh_col.name = "ShoulderRightCol_%d" % i
		right_sh_col.shape = right_sh_shape
		right_sh_col.transform = Transform3D(slice_basis, slice_center + slice_basis * right_sh_local)
		static_body.add_child(right_sh_col)

		# Shoulder trigger areas for loose surface & mud particle detection in van.gd
		var sh_area_left := Area3D.new()
		sh_area_left.name = "ShoulderAreaLeft_%d" % i
		sh_area_left.collision_layer = 0
		sh_area_left.collision_mask = 1
		var sh_col_left := CollisionShape3D.new()
		var sh_shape_left := BoxShape3D.new()
		sh_shape_left.size = Vector3(shoulder_width, 1.8, slice_box_length)
		sh_col_left.shape = sh_shape_left
		sh_area_left.add_child(sh_col_left)
		var left_sh_area_local := Vector3(-shoulder_center_x, 0.5, 0.0)
		sh_area_left.transform = Transform3D(slice_basis, slice_center + slice_basis * left_sh_area_local)
		sh_area_left.body_entered.connect(_on_shoulder_area_entered)
		sh_area_left.body_exited.connect(_on_shoulder_area_exited)
		add_child(sh_area_left)

		var sh_area_right := Area3D.new()
		sh_area_right.name = "ShoulderAreaRight_%d" % i
		sh_area_right.collision_layer = 0
		sh_area_right.collision_mask = 1
		var sh_col_right := CollisionShape3D.new()
		var sh_shape_right := BoxShape3D.new()
		sh_shape_right.size = Vector3(shoulder_width, 1.8, slice_box_length)
		sh_col_right.shape = sh_shape_right
		sh_area_right.add_child(sh_col_right)
		var right_sh_area_local := Vector3(shoulder_center_x, 0.5, 0.0)
		sh_area_right.transform = Transform3D(slice_basis, slice_center + slice_basis * right_sh_area_local)
		sh_area_right.body_entered.connect(_on_shoulder_area_entered)
		sh_area_right.body_exited.connect(_on_shoulder_area_exited)
		add_child(sh_area_right)

		# 4. Roadside Ditches (Cunetas) with Smooth Beveled Transition from Shoulder Top (Y = +0.5)
		var ditch_mat := get_ditch_material()
		var ditch_slab_thickness: float = 0.4
		var slope_hypot: float = sqrt(pow(ditch_slope_width, 2.0) + pow(ditch_depth, 2.0)) + 0.35
		var slope_angle: float = atan2(ditch_depth, ditch_slope_width)
		# Align top surface of ditch slope with top surface of road/shoulder (Y = road_thickness * 0.5 = +0.5)
		var surface_top_y: float = road_thickness * 0.5
		var down_center_y: float = surface_top_y - (ditch_depth * 0.5) - (ditch_slab_thickness * 0.5 * cos(slope_angle))

		# Left Ditch
		# Inner down-slope (slopes smoothly down from shoulder edge at Y = +0.5)
		var left_down_center_x: float = -(half_road + shoulder_width + (ditch_slope_width * 0.5))
		var left_down_local := Vector3(left_down_center_x, down_center_y, 0.0)
		var left_down_rot := Basis(Vector3.FORWARD, slope_angle)
		var left_down_tr := Transform3D(slice_basis * left_down_rot, slice_center + slice_basis * left_down_local)

		var left_down_mesh := BoxMesh.new()
		left_down_mesh.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		left_down_mesh.material = ditch_mat
		var left_down_inst := MeshInstance3D.new()
		left_down_inst.name = "DitchLeftDownMesh_%d" % i
		left_down_inst.mesh = left_down_mesh
		left_down_inst.transform = left_down_tr
		static_body.add_child(left_down_inst)

		var left_down_col := CollisionShape3D.new()
		var left_down_shape := BoxShape3D.new()
		left_down_shape.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		left_down_col.name = "DitchLeftDownCol_%d" % i
		left_down_col.shape = left_down_shape
		left_down_col.transform = left_down_tr
		static_body.add_child(left_down_col)

		# Outer up-slope
		var left_up_center_x: float = -(half_road + shoulder_width + ditch_slope_width + (ditch_slope_width * 0.5))
		var left_up_local := Vector3(left_up_center_x, down_center_y, 0.0)
		var left_up_rot := Basis(Vector3.FORWARD, -slope_angle)
		var left_up_tr := Transform3D(slice_basis * left_up_rot, slice_center + slice_basis * left_up_local)

		var left_up_mesh := BoxMesh.new()
		left_up_mesh.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		left_up_mesh.material = ditch_mat
		var left_up_inst := MeshInstance3D.new()
		left_up_inst.name = "DitchLeftUpMesh_%d" % i
		left_up_inst.mesh = left_up_mesh
		left_up_inst.transform = left_up_tr
		static_body.add_child(left_up_inst)

		var left_up_col := CollisionShape3D.new()
		var left_up_shape := BoxShape3D.new()
		left_up_shape.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		left_up_col.name = "DitchLeftUpCol_%d" % i
		left_up_col.shape = left_up_shape
		left_up_col.transform = left_up_tr
		static_body.add_child(left_up_col)

		# Right Ditch
		# Inner down-slope (slopes smoothly down from shoulder edge at Y = +0.5)
		var right_down_center_x: float = half_road + shoulder_width + (ditch_slope_width * 0.5)
		var right_down_local := Vector3(right_down_center_x, down_center_y, 0.0)
		var right_down_rot := Basis(Vector3.FORWARD, -slope_angle)
		var right_down_tr := Transform3D(slice_basis * right_down_rot, slice_center + slice_basis * right_down_local)

		var right_down_mesh := BoxMesh.new()
		right_down_mesh.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		right_down_mesh.material = ditch_mat
		var right_down_inst := MeshInstance3D.new()
		right_down_inst.name = "DitchRightDownMesh_%d" % i
		right_down_inst.mesh = right_down_mesh
		right_down_inst.transform = right_down_tr
		static_body.add_child(right_down_inst)

		var right_down_col := CollisionShape3D.new()
		var right_down_shape := BoxShape3D.new()
		right_down_shape.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		right_down_col.name = "DitchRightDownCol_%d" % i
		right_down_col.shape = right_down_shape
		right_down_col.transform = right_down_tr
		static_body.add_child(right_down_col)

		# Outer up-slope
		var right_up_center_x: float = half_road + shoulder_width + ditch_slope_width + (ditch_slope_width * 0.5)
		var right_up_local := Vector3(right_up_center_x, down_center_y, 0.0)
		var right_up_rot := Basis(Vector3.FORWARD, slope_angle)
		var right_up_tr := Transform3D(slice_basis * right_up_rot, slice_center + slice_basis * right_up_local)

		var right_up_mesh := BoxMesh.new()
		right_up_mesh.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		right_up_mesh.material = ditch_mat
		var right_up_inst := MeshInstance3D.new()
		right_up_inst.name = "DitchRightUpMesh_%d" % i
		right_up_inst.mesh = right_up_mesh
		right_up_inst.transform = right_up_tr
		static_body.add_child(right_up_inst)

		var right_up_col := CollisionShape3D.new()
		var right_up_shape := BoxShape3D.new()
		right_up_shape.size = Vector3(slope_hypot, ditch_slab_thickness, slice_box_length)
		right_up_col.name = "DitchRightUpCol_%d" % i
		right_up_col.shape = right_up_shape
		right_up_col.transform = right_up_tr
		static_body.add_child(right_up_col)

		# Ditch Mud Drag Trigger Area3D (Left & Right)
		var ditch_area_w: float = ditch_slope_width * 2.0
		var ditch_left_mud := Area3D.new()
		ditch_left_mud.name = "DitchMudLeft_%d" % i
		ditch_left_mud.collision_layer = 0
		ditch_left_mud.collision_mask = 1
		var ditch_left_mud_col := CollisionShape3D.new()
		var ditch_left_mud_shape := BoxShape3D.new()
		ditch_left_mud_shape.size = Vector3(ditch_area_w, 2.0, slice_box_length)
		ditch_left_mud_col.shape = ditch_left_mud_shape
		ditch_left_mud.add_child(ditch_left_mud_col)
		var left_mud_local := Vector3(-(half_road + shoulder_width + ditch_slope_width), -0.5, 0.0)
		ditch_left_mud.transform = Transform3D(slice_basis, slice_center + slice_basis * left_mud_local)
		ditch_left_mud.body_entered.connect(_on_mud_area_entered)
		ditch_left_mud.body_exited.connect(_on_mud_area_exited)
		add_child(ditch_left_mud)

		var ditch_right_mud := Area3D.new()
		ditch_right_mud.name = "DitchMudRight_%d" % i
		ditch_right_mud.collision_layer = 0
		ditch_right_mud.collision_mask = 1
		var ditch_right_mud_col := CollisionShape3D.new()
		var ditch_right_mud_shape := BoxShape3D.new()
		ditch_right_mud_shape.size = Vector3(ditch_area_w, 2.0, slice_box_length)
		ditch_right_mud_col.shape = ditch_right_mud_shape
		ditch_right_mud.add_child(ditch_right_mud_col)
		var right_mud_local := Vector3(half_road + shoulder_width + ditch_slope_width, -0.5, 0.0)
		ditch_right_mud.transform = Transform3D(slice_basis, slice_center + slice_basis * right_mud_local)
		ditch_right_mud.body_entered.connect(_on_mud_area_entered)
		ditch_right_mud.body_exited.connect(_on_mud_area_exited)
		add_child(ditch_right_mud)

		# 5. Selective Outer Curve Guardrails
		# NO guardrails on straight chunks (open roads and shoulders).
		# On curves, ONLY generate barrier on the outer edge:
		# CURVE_LEFT -> outer edge is Right (+X)
		# CURVE_RIGHT -> outer edge is Left (-X)
		var has_left_barrier: bool = (segment_type == SegmentType.CURVE_RIGHT)
		var has_right_barrier: bool = (segment_type == SegmentType.CURVE_LEFT)

		var barrier_lateral_x: float = half_road + shoulder_width + (barrier_thickness * 0.5)
		var barrier_y: float = barrier_height * 0.5

		if has_left_barrier:
			var left_local := Vector3(-barrier_lateral_x, barrier_y, 0.0)
			var left_transform := Transform3D(slice_basis, slice_center + slice_basis * left_local)

			# Retain full collider so vehicle cannot glitch through or jump over outer curve edge
			var left_col_shape := BoxShape3D.new()
			left_col_shape.size = Vector3(barrier_thickness, barrier_height, barrier_box_length)

			var left_col := CollisionShape3D.new()
			left_col.name = "BarrierLeftCol_%d" % i
			left_col.shape = left_col_shape
			left_col.transform = left_transform
			static_body.add_child(left_col)

			# Modular corrugated galvanized metal W-beam rails & posts
			var post_mat := get_guardrail_post_material()
			var delineator_mat := get_reflector_amber_material()

			# Upper W-Beam Rail
			var upper_rail_mesh := BoxMesh.new()
			upper_rail_mesh.size = Vector3(0.12, 0.35, barrier_box_length)
			upper_rail_mesh.material = barrier_mat
			var upper_rail_inst := MeshInstance3D.new()
			upper_rail_inst.name = "UpperRailLeft_%d" % i
			upper_rail_inst.mesh = upper_rail_mesh
			var upper_rail_local := Vector3(-barrier_lateral_x + 0.1, 0.95, 0.0)
			upper_rail_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * upper_rail_local)
			static_body.add_child(upper_rail_inst)

			# Lower W-Beam Rail
			var lower_rail_mesh := BoxMesh.new()
			lower_rail_mesh.size = Vector3(0.12, 0.28, barrier_box_length)
			lower_rail_mesh.material = barrier_mat
			var lower_rail_inst := MeshInstance3D.new()
			lower_rail_inst.name = "LowerRailLeft_%d" % i
			lower_rail_inst.mesh = lower_rail_mesh
			var lower_rail_local := Vector3(-barrier_lateral_x + 0.1, 0.55, 0.0)
			lower_rail_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * lower_rail_local)
			static_body.add_child(lower_rail_inst)

			# Vertical Support Post
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.16, 1.35, 0.16)
			post_mesh.material = post_mat
			var post_inst := MeshInstance3D.new()
			post_inst.name = "GuardrailPostLeft_%d" % i
			post_inst.mesh = post_mesh
			var post_local := Vector3(-barrier_lateral_x + 0.2, 0.65, 0.0)
			post_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * post_local)
			static_body.add_child(post_inst)

			# Amber Retro-Reflective Delineator facing oncoming traffic
			var delineator_mesh := BoxMesh.new()
			delineator_mesh.size = Vector3(0.06, 0.14, 0.08)
			delineator_mesh.material = delineator_mat
			var delineator_inst := MeshInstance3D.new()
			delineator_inst.name = "DelineatorLeft_%d" % i
			delineator_inst.mesh = delineator_mesh
			var delineator_local := Vector3(-barrier_lateral_x + 0.02, 1.05, 0.0)
			delineator_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * delineator_local)
			static_body.add_child(delineator_inst)

			if i % 2 == 0:
				_build_warning_sign(i, slice_basis, slice_center, -barrier_lateral_x, barrier_height)

		if has_right_barrier:
			var right_local := Vector3(barrier_lateral_x, barrier_y, 0.0)
			var right_transform := Transform3D(slice_basis, slice_center + slice_basis * right_local)

			# Retain full collider so vehicle cannot glitch through or jump over outer curve edge
			var right_col_shape := BoxShape3D.new()
			right_col_shape.size = Vector3(barrier_thickness, barrier_height, barrier_box_length)

			var right_col := CollisionShape3D.new()
			right_col.name = "BarrierRightCol_%d" % i
			right_col.shape = right_col_shape
			right_col.transform = right_transform
			static_body.add_child(right_col)

			# Modular corrugated galvanized metal W-beam rails & posts
			var post_mat := get_guardrail_post_material()
			var delineator_mat := get_reflector_amber_material()

			# Upper W-Beam Rail
			var upper_rail_mesh := BoxMesh.new()
			upper_rail_mesh.size = Vector3(0.12, 0.35, barrier_box_length)
			upper_rail_mesh.material = barrier_mat
			var upper_rail_inst := MeshInstance3D.new()
			upper_rail_inst.name = "UpperRailRight_%d" % i
			upper_rail_inst.mesh = upper_rail_mesh
			var upper_rail_local := Vector3(barrier_lateral_x - 0.1, 0.95, 0.0)
			upper_rail_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * upper_rail_local)
			static_body.add_child(upper_rail_inst)

			# Lower W-Beam Rail
			var lower_rail_mesh := BoxMesh.new()
			lower_rail_mesh.size = Vector3(0.12, 0.28, barrier_box_length)
			lower_rail_mesh.material = barrier_mat
			var lower_rail_inst := MeshInstance3D.new()
			lower_rail_inst.name = "LowerRailRight_%d" % i
			lower_rail_inst.mesh = lower_rail_mesh
			var lower_rail_local := Vector3(barrier_lateral_x - 0.1, 0.55, 0.0)
			lower_rail_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * lower_rail_local)
			static_body.add_child(lower_rail_inst)

			# Vertical Support Post
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.16, 1.35, 0.16)
			post_mesh.material = post_mat
			var post_inst := MeshInstance3D.new()
			post_inst.name = "GuardrailPostRight_%d" % i
			post_inst.mesh = post_mesh
			var post_local := Vector3(barrier_lateral_x - 0.2, 0.65, 0.0)
			post_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * post_local)
			static_body.add_child(post_inst)

			# Amber Retro-Reflective Delineator
			var delineator_mesh := BoxMesh.new()
			delineator_mesh.size = Vector3(0.06, 0.14, 0.08)
			delineator_mesh.material = delineator_mat
			var delineator_inst := MeshInstance3D.new()
			delineator_inst.name = "DelineatorRight_%d" % i
			delineator_inst.mesh = delineator_mesh
			var delineator_local := Vector3(barrier_lateral_x - 0.02, 1.05, 0.0)
			delineator_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * delineator_local)
			static_body.add_child(delineator_inst)

			if i % 2 == 0:
				_build_warning_sign(i, slice_basis, slice_center, barrier_lateral_x, barrier_height)

		# 6. Roadside Wooden Telegraph / Utility Poles and Overhead Power Cables
		# Placed along the left verge outside the shoulder
		var pole_verge_x: float = -(half_road + shoulder_width + 0.9)
		var wood_mat := get_telegraph_wood_material()
		var insulator_mat := get_insulator_material()
		var cable_mat := get_cable_wire_material()

		# Spawn telegraph pole every 4 slices (every ~40m)
		if i % 4 == 0:
			var pole_root := Node3D.new()
			pole_root.name = "TelegraphPole_%d" % i

			# Vertical wooden pole (CylinderMesh)
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.14
			pole_mesh.bottom_radius = 0.20
			pole_mesh.height = 7.6
			pole_mesh.material = wood_mat

			var pole_inst := MeshInstance3D.new()
			pole_inst.name = "PoleShaft"
			pole_inst.mesh = pole_mesh
			pole_inst.position = Vector3(0.0, 3.8, 0.0)
			pole_root.add_child(pole_inst)

			# Horizontal wooden crossarm
			var crossarm_mesh := BoxMesh.new()
			crossarm_mesh.size = Vector3(2.2, 0.16, 0.16)
			crossarm_mesh.material = wood_mat

			var crossarm_inst := MeshInstance3D.new()
			crossarm_inst.name = "Crossarm"
			crossarm_inst.mesh = crossarm_mesh
			crossarm_inst.position = Vector3(0.0, 7.1, 0.0)
			pole_root.add_child(crossarm_inst)

			# Diagonal crossarm support braces
			var brace_mesh := BoxMesh.new()
			brace_mesh.size = Vector3(0.06, 0.65, 0.06)
			brace_mesh.material = wood_mat
			var brace_l := MeshInstance3D.new()
			brace_l.mesh = brace_mesh
			brace_l.position = Vector3(-0.45, 6.75, 0.0)
			brace_l.rotation.z = deg_to_rad(35.0)
			pole_root.add_child(brace_l)

			var brace_r := MeshInstance3D.new()
			brace_r.mesh = brace_mesh
			brace_r.position = Vector3(0.45, 6.75, 0.0)
			brace_r.rotation.z = deg_to_rad(-35.0)
			pole_root.add_child(brace_r)

			# 3 Ceramic green-tinted insulators on top of the crossarm
			var ins_offsets: Array[float] = [-0.85, 0.0, 0.85]
			for ins_x in ins_offsets:
				var ins_mesh := CylinderMesh.new()
				ins_mesh.top_radius = 0.04
				ins_mesh.bottom_radius = 0.06
				ins_mesh.height = 0.18
				ins_mesh.material = insulator_mat

				var ins_inst := MeshInstance3D.new()
				ins_inst.mesh = ins_mesh
				ins_inst.position = Vector3(ins_x, 7.27, 0.0)
				pole_root.add_child(ins_inst)

			var pole_local := Vector3(pole_verge_x, 0.0, 0.0)
			pole_root.transform = Transform3D(slice_basis, slice_center + slice_basis * pole_local)
			static_body.add_child(pole_root)

		# Overhead sagging catenary wires spanning every slice
		var sag_offset_y: float = 0.0
		var slice_in_quad: int = i % 4
		if slice_in_quad == 1 or slice_in_quad == 3:
			sag_offset_y = -0.22
		elif slice_in_quad == 2:
			sag_offset_y = -0.42

		var cable_wire_mesh := BoxMesh.new()
		cable_wire_mesh.size = Vector3(0.025, 0.025, slice_box_length)
		cable_wire_mesh.material = cable_mat

		# Cable 1 (outer)
		var cable_inst1 := MeshInstance3D.new()
		cable_inst1.name = "CableOuter_%d" % i
		cable_inst1.mesh = cable_wire_mesh
		var c1_local := Vector3(pole_verge_x - 0.85, 7.25 + sag_offset_y, 0.0)
		cable_inst1.transform = Transform3D(slice_basis, slice_center + slice_basis * c1_local)
		static_body.add_child(cable_inst1)

		# Cable 2 (inner)
		var cable_inst2 := MeshInstance3D.new()
		cable_inst2.name = "CableInner_%d" % i
		cable_inst2.mesh = cable_wire_mesh
		var c2_local := Vector3(pole_verge_x + 0.85, 7.25 + sag_offset_y, 0.0)
		cable_inst2.transform = Transform3D(slice_basis, slice_center + slice_basis * c2_local)
		static_body.add_child(cable_inst2)

		# Advance current trajectory to slice end
		current_pos += mid_fwd * slice_length
		current_yaw += delta_yaw

	# Anchor ExitMarker at the exact end position and orientation of the segment
	var exit_basis := Basis(Vector3.UP, current_yaw)
	exit_marker.transform = Transform3D(exit_basis, current_pos)

## Returns the global transform of the exit anchor for seamless chunk chaining.
func get_exit_transform() -> Transform3D:
	if not exit_marker:
		return global_transform if is_inside_tree() else transform
	if is_inside_tree() and exit_marker.is_inside_tree():
		return exit_marker.global_transform
	var parent_tr := global_transform if is_inside_tree() else transform
	return parent_tr * exit_marker.transform

## Returns the global position of the exit anchor.
func get_exit_position() -> Vector3:
	return get_exit_transform().origin

## Returns the forward tangent vector at the exit of this chunk.
func get_exit_forward() -> Vector3:
	return -get_exit_transform().basis.z

## Checks whether a target position has progressed past this chunk's exit by threshold_distance.
func is_behind_position(target_global_pos: Vector3, threshold_distance: float) -> bool:
	var exit_pos := get_exit_position()
	var exit_fwd := get_exit_forward()
	var to_target := target_global_pos - exit_pos
	var forward_progress := to_target.dot(exit_fwd)
	return forward_progress > threshold_distance

## Returns total generated geometric slices for this chunk.
func get_slice_count() -> int:
	return slice_transforms.size()

## Returns the local transform of a specific slice along this chunk's curvature.
func get_slice_transform(index: int) -> Transform3D:
	if index >= 0 and index < slice_transforms.size():
		return slice_transforms[index]
	return Transform3D.IDENTITY

func _on_shoulder_area_entered(body: Node3D) -> void:
	if body.has_method("enter_shoulder_zone"):
		body.enter_shoulder_zone()

func _on_shoulder_area_exited(body: Node3D) -> void:
	if body.has_method("exit_shoulder_zone"):
		body.exit_shoulder_zone()

func _on_mud_area_entered(body: Node3D) -> void:
	if body.has_method("enter_mud_zone"):
		body.enter_mud_zone()

func _on_mud_area_exited(body: Node3D) -> void:
	if body.has_method("exit_mud_zone"):
		body.exit_mud_zone()

func _build_warning_sign(i: int, slice_basis: Basis, slice_center: Vector3, sign_side_x: float, _barrier_h: float) -> void:
	var sign_y: float = 0.9
	var sign_local := Vector3(sign_side_x, sign_y, 0.0)

	# Black iron mounting pole
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.12, 1.8, 0.12)
	pole_mesh.material = get_sign_post_material()

	var pole_inst := MeshInstance3D.new()
	pole_inst.name = "WarningSignPole_%d" % i
	pole_inst.mesh = pole_mesh
	pole_inst.transform = Transform3D(slice_basis, slice_center + slice_basis * sign_local)
	static_body.add_child(pole_inst)

	# Retro-reflective amber diamond plate (#FFA000)
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.55, 0.55, 0.05)
	plate_mesh.material = get_reflector_amber_material()

	var plate_inst := MeshInstance3D.new()
	plate_inst.name = "ReflectorDiamond_%d" % i
	plate_inst.mesh = plate_mesh
	var diamond_rot := slice_basis.rotated(slice_basis.z, deg_to_rad(45.0))
	plate_inst.transform = Transform3D(diamond_rot, slice_center + slice_basis * (sign_local + Vector3(0.0, 0.65, 0.0)))
	static_body.add_child(plate_inst)
