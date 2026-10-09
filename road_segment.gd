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
## Total driveable road width between barriers in meters.
@export var road_width: float = 16.0
## Thickness of the road floor slab.
@export var road_thickness: float = 1.0
## Total turning angle in degrees for curved segments.
@export var curve_angle_deg: float = 22.5
## Number of geometric primitive slices used to construct smooth curves.
@export var slice_count: int = 8

@export_group("Guardrails")
## Height of lateral barrier guardrails to prevent falling off during drifts.
@export var barrier_height: float = 3.0
## Thickness of the barrier guardrail boxes.
@export var barrier_thickness: float = 1.0

# Node references
var static_body: StaticBody3D
var exit_marker: Marker3D

# Static shared materials to optimize draw calls and shader memory
static var _road_material: StandardMaterial3D
static var _barrier_material: StandardMaterial3D

static func get_road_material() -> StandardMaterial3D:
	if not _road_material:
		_road_material = StandardMaterial3D.new()
		# Dark lead-gray asphalt with high roughness
		_road_material.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
		_road_material.roughness = 0.95
		_road_material.metallic = 0.05
	return _road_material

static func get_barrier_material() -> StandardMaterial3D:
	if not _barrier_material:
		_barrier_material = StandardMaterial3D.new()
		# Galvanized weathered steel guardrail
		_barrier_material.albedo_color = Color(0.32, 0.34, 0.37, 1.0)
		_barrier_material.roughness = 0.55
		_barrier_material.metallic = 0.65
	return _barrier_material

func _ready() -> void:
	if not static_body:
		build_segment()

## Builds all road slices, collision shapes, and guardrails from Box primitives.
func build_segment() -> void:
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

	# Slight overlap on primitive boxes to ensure zero gaps between adjacent slices
	var overlap: float = 0.35
	var slice_box_length: float = slice_length + overlap
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
		road_shape.size = Vector3(road_width, road_thickness, slice_box_length)

		var road_col := CollisionShape3D.new()
		road_col.name = "RoadCol_%d" % i
		road_col.shape = road_shape
		road_col.transform = slice_transform
		static_body.add_child(road_col)

		# 2. Side Guardrails / Barriers
		# Placed flush along road edges. Height extends well above road to contain drifts.
		var lateral_offset: float = (road_width * 0.5) + (barrier_thickness * 0.5)
		var vertical_offset: float = barrier_height * 0.5 # Centered so top is at barrier_height

		# Left Guardrail
		var left_local := Vector3(-lateral_offset, vertical_offset, 0.0)
		var left_transform := Transform3D(slice_basis, slice_center + slice_basis * left_local)

		var left_mesh := BoxMesh.new()
		left_mesh.size = Vector3(barrier_thickness, barrier_height, barrier_box_length)
		left_mesh.material = barrier_mat

		var left_mesh_instance := MeshInstance3D.new()
		left_mesh_instance.name = "BarrierLeftMesh_%d" % i
		left_mesh_instance.mesh = left_mesh
		left_mesh_instance.transform = left_transform
		static_body.add_child(left_mesh_instance)

		var left_col_shape := BoxShape3D.new()
		left_col_shape.size = Vector3(barrier_thickness, barrier_height, barrier_box_length)

		var left_col := CollisionShape3D.new()
		left_col.name = "BarrierLeftCol_%d" % i
		left_col.shape = left_col_shape
		left_col.transform = left_transform
		static_body.add_child(left_col)

		# Right Guardrail
		var right_local := Vector3(lateral_offset, vertical_offset, 0.0)
		var right_transform := Transform3D(slice_basis, slice_center + slice_basis * right_local)

		var right_mesh := BoxMesh.new()
		right_mesh.size = Vector3(barrier_thickness, barrier_height, barrier_box_length)
		right_mesh.material = barrier_mat

		var right_mesh_instance := MeshInstance3D.new()
		right_mesh_instance.name = "BarrierRightMesh_%d" % i
		right_mesh_instance.mesh = right_mesh
		right_mesh_instance.transform = right_transform
		static_body.add_child(right_mesh_instance)

		var right_col_shape := BoxShape3D.new()
		right_col_shape.size = Vector3(barrier_thickness, barrier_height, barrier_box_length)

		var right_col := CollisionShape3D.new()
		right_col.name = "BarrierRightCol_%d" % i
		right_col.shape = right_col_shape
		right_col.transform = right_transform
		static_body.add_child(right_col)

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
