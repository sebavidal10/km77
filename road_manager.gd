class_name RoadManager
extends Node3D

@export_group("Target Vehicle")
## Node representing the vehicle to track for spawning and recycling road segments.
@export var target_vehicle: Node3D

@export_group("Chunk Spawning & Streaming")
## Minimum number of active chunks that must always exist ahead of the vehicle.
@export var min_segments_ahead: int = 4
## Target/maximum number of active chunks maintained ahead of the vehicle.
@export var max_segments_ahead: int = 6
## Longitudinal length of each chunk in meters.
@export var segment_length: float = 80.0
## Road surface width between guardrails in meters.
@export var road_width: float = 16.0
## Turning angle in degrees for curved segments.
@export var curve_angle: float = 22.5
## Distance behind the vehicle after which old segments are recycled and freed.
@export var despawn_distance: float = 120.0
## Number of geometric slices per chunk for smooth curve rendering.
@export var slice_count: int = 8

@export_group("Procedural Generation")
## Optional fixed seed for reproducible track generation. Set to 0 for random.
@export var random_seed: int = 0
## Probability weight (0.0 to 1.0) of spawning a curved chunk after a straight chunk.
@export var curve_probability: float = 0.65

# Internal state
var active_segments: Array[RoadSegment] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var consecutive_curves: int = 0
var last_curve_type: RoadSegment.SegmentType = RoadSegment.SegmentType.STRAIGHT
var total_segments_spawned: int = 0

func _ready() -> void:
	_init_rng()
	_find_target_vehicle()
	_spawn_initial_track()

func _physics_process(_delta: float) -> void:
	if not target_vehicle:
		_find_target_vehicle()
		if not target_vehicle:
			return

	_update_road_streaming()

func _init_rng() -> void:
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()

func _find_target_vehicle() -> void:
	if target_vehicle:
		return
	
	# Look for sibling Van in the scene
	var parent_node := get_parent()
	if parent_node:
		var van_candidate := parent_node.get_node_or_null("Van") as Node3D
		if van_candidate:
			target_vehicle = van_candidate
			return

	# Fallback: search by CharacterBody3D or group
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		target_vehicle = nodes[0] as Node3D

func _spawn_initial_track() -> void:
	# Clear any pre-existing children
	for child in get_children():
		child.queue_free()
	active_segments.clear()
	consecutive_curves = 0
	last_curve_type = RoadSegment.SegmentType.STRAIGHT
	total_segments_spawned = 0

	# 1. Spawn a straight buffer segment behind the starting vehicle position (from Z = 80 to Z = 0)
	var initial_rear_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, segment_length))
	var rear_segment := _create_segment_node(RoadSegment.SegmentType.STRAIGHT)
	rear_segment.global_transform = initial_rear_transform
	add_child(rear_segment)
	rear_segment.build_segment()
	active_segments.append(rear_segment)
	total_segments_spawned += 1

	# 2. Spawn the initial straight segment starting at origin (Z = 0 to Z = -segment_length)
	var first_segment := _spawn_segment(RoadSegment.SegmentType.STRAIGHT)

	# 3. Spawn subsequent segments to satisfy the ahead count
	while active_segments.size() < (max_segments_ahead + 1):
		var next_type := _select_next_segment_type()
		_spawn_segment(next_type)

func _update_road_streaming() -> void:
	if active_segments.is_empty():
		return

	var vehicle_pos := target_vehicle.global_position

	# 1. Determine vehicle's current segment index
	var current_segment_index := -1
	for i in range(active_segments.size()):
		var segment := active_segments[i]
		# If the vehicle has NOT crossed this segment's exit, it is currently on or before it
		if not segment.is_behind_position(vehicle_pos, 0.0):
			current_segment_index = i
			break

	# If vehicle is past all registered segments, default to the last one
	if current_segment_index == -1:
		current_segment_index = active_segments.size() - 1

	# 2. Maintain active chunks ahead of current segment
	var segments_ahead := active_segments.size() - 1 - current_segment_index
	while segments_ahead < max_segments_ahead:
		var next_type := _select_next_segment_type()
		_spawn_segment(next_type)
		segments_ahead += 1

	# 3. Recycle old segments that are far behind the vehicle
	while active_segments.size() > (min_segments_ahead + 1):
		var oldest_segment := active_segments[0]
		if oldest_segment.is_behind_position(vehicle_pos, despawn_distance):
			active_segments.pop_front()
			oldest_segment.queue_free()
		else:
			break

func _select_next_segment_type() -> RoadSegment.SegmentType:
	# Keep the first 2 chunks strictly straight to give player runway
	if total_segments_spawned <= 2:
		return RoadSegment.SegmentType.STRAIGHT

	# Guard against endless winding curves (max 2 consecutive curves in same direction)
	if consecutive_curves >= 2:
		consecutive_curves = 0
		return RoadSegment.SegmentType.STRAIGHT

	# If previous was straight, roll for curve
	if last_curve_type == RoadSegment.SegmentType.STRAIGHT:
		if rng.randf() < curve_probability:
			# Alternate curve direction to balance overall highway trajectory
			var pick_left: bool = rng.randf() < 0.5
			var new_type := RoadSegment.SegmentType.CURVE_LEFT if pick_left else RoadSegment.SegmentType.CURVE_RIGHT
			last_curve_type = new_type
			consecutive_curves = 1
			return new_type
		else:
			return RoadSegment.SegmentType.STRAIGHT
	else:
		# Previous was a curve: 60% chance of returning to straight, 40% continuing wide curve
		if rng.randf() < 0.6:
			consecutive_curves = 0
			return RoadSegment.SegmentType.STRAIGHT
		else:
			consecutive_curves += 1
			return last_curve_type

func _create_segment_node(type: RoadSegment.SegmentType) -> RoadSegment:
	var segment := RoadSegment.new()
	segment.name = "RoadSegment_%d" % total_segments_spawned
	segment.segment_type = type
	segment.segment_length = segment_length
	segment.road_width = road_width
	segment.curve_angle_deg = curve_angle
	segment.slice_count = slice_count
	return segment

func _spawn_segment(type: RoadSegment.SegmentType) -> RoadSegment:
	var segment := _create_segment_node(type)

	if not active_segments.is_empty():
		var last_segment := active_segments.back()
		# Anchor new chunk exactly at the exit anchor of the preceding chunk
		segment.global_transform = last_segment.get_exit_transform()

	add_child(segment)
	segment.build_segment()
	active_segments.append(segment)
	total_segments_spawned += 1
	return segment
