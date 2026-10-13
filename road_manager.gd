class_name RoadManager
extends Node3D

const SupplyStopScene = preload("res://supply_stop.tscn")
const AbandonedCarScene = preload("res://abandoned_car.tscn")

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
## Road surface width in meters (two 7.0m lanes).
@export var road_width: float = 14.0
## Turning angle in degrees for curved segments.
@export var curve_angle: float = 22.5
## Distance behind the vehicle after which old segments are recycled and freed.
@export var despawn_distance: float = 80.0
## Number of geometric slices per chunk for smooth curve rendering.
@export var slice_count: int = 8

@export_group("Procedural Generation")
## Optional fixed seed for reproducible track generation. Set to 0 for random.
@export var random_seed: int = 0
## Probability weight (0.0 to 1.0) of spawning a curved chunk after a straight chunk.
@export var curve_probability: float = 0.65

@export_group("Events & Obstacles")
## Enables procedural obstacle and roadside props spawning.
@export var enable_events: bool = true
## Optional custom event spawner node. If null, a default RoadEventSpawner is created automatically.
@export var event_spawner: RoadEventSpawner

@export_group("Supply Stops")
## Enables roadside supply stops on the shoulder for refueling and vehicle repairs.
@export var enable_supply_stops: bool = true
## Minimum chunks between supply stop occurrences (3 to 5 chunks).
@export var supply_stop_min_chunks: int = 3
## Maximum chunks between supply stop occurrences.
@export var supply_stop_max_chunks: int = 5

@export_group("Abandoned Cars")
## Enables roadside abandoned vehicles with open doors and flickering dome lights.
@export var enable_abandoned_cars: bool = true
## Minimum chunks generated between abandoned car occurrences (6 to 8 chunks).
@export var abandoned_car_min_chunks: int = 6
## Maximum chunks generated between abandoned car occurrences.
@export var abandoned_car_max_chunks: int = 8

@export_group("Rural Turnoffs")
## Enables procedural dead-end dirt turnoffs branching into the woods.
@export var enable_turnoffs: bool = true
## Minimum chunks between turnoff occurrences (12 to 15 chunks).
@export var turnoff_min_chunks: int = 12
## Maximum chunks between turnoff occurrences.
@export var turnoff_max_chunks: int = 15

@export_group("Doppelgänger / Oncoming Vehicle")
## Enables oncoming doppelgänger patrol vehicle encounters in the opposing lane.
@export var enable_oncoming_vehicle: bool = true
## Minimum chunks generated between oncoming vehicle encounters.
@export var oncoming_spawn_min_chunks: int = 4
## Maximum chunks generated between oncoming vehicle encounters.
@export var oncoming_spawn_max_chunks: int = 6
## Chance (0.0 to 1.0) to spawn an oncoming vehicle once the chunk interval is reached.
@export var oncoming_spawn_chance: float = 0.75
## Opposing lane center lateral offset from road center (meters).
@export var opposing_lane_offset: float = 3.5

@export_group("Rear Stalker Vehicle")
## Enables high-speed rear stalker vehicle pursuing the player from behind.
@export var enable_rear_stalker: bool = true
## Minimum chunks generated between rear stalker encounters (every 15-20 chunks).
@export var stalker_spawn_min_chunks: int = 15
## Maximum chunks generated between rear stalker encounters.
@export var stalker_spawn_max_chunks: int = 20

# Internal state
var active_segments: Array[RoadSegment] = []
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var consecutive_curves: int = 0
var last_curve_type: RoadSegment.SegmentType = RoadSegment.SegmentType.STRAIGHT
var total_segments_spawned: int = 0

var active_oncoming_vehicle: OncomingVehicle = null
var chunks_since_last_oncoming: int = 0
var next_oncoming_chunk_interval: int = 5

var chunks_since_last_supply_stop: int = 0
var next_supply_stop_interval: int = 8

var chunks_since_last_abandoned_car: int = 0
var next_abandoned_car_interval: int = 7

var chunks_since_last_turnoff: int = 0
var next_turnoff_interval: int = 13

var active_rear_stalker: RearStalker = null
var chunks_since_last_stalker: int = 0
var next_stalker_interval: int = 17

func _ready() -> void:
	_init_rng()
	_init_event_spawner()
	next_oncoming_chunk_interval = rng.randi_range(oncoming_spawn_min_chunks, oncoming_spawn_max_chunks)
	next_supply_stop_interval = rng.randi_range(supply_stop_min_chunks, supply_stop_max_chunks)
	chunks_since_last_supply_stop = 0
	next_abandoned_car_interval = rng.randi_range(abandoned_car_min_chunks, abandoned_car_max_chunks)
	chunks_since_last_abandoned_car = 0
	next_turnoff_interval = rng.randi_range(turnoff_min_chunks, turnoff_max_chunks)
	chunks_since_last_turnoff = 0
	next_stalker_interval = rng.randi_range(stalker_spawn_min_chunks, stalker_spawn_max_chunks)
	chunks_since_last_stalker = 0
	_find_target_vehicle()
	_spawn_initial_track()

func _init_event_spawner() -> void:
	if enable_events and not event_spawner:
		event_spawner = RoadEventSpawner.new()
		event_spawner.name = "RoadEventSpawner"
		add_child(event_spawner)

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
	var tree := get_tree()
	if tree:
		var nodes := tree.get_nodes_in_group("player")
		if not nodes.is_empty():
			target_vehicle = nodes[0] as Node3D

## Clears all existing chunks and obstacles, and rebuilds the initial runway starting at origin.
func reset_road() -> void:
	if is_instance_valid(active_oncoming_vehicle):
		active_oncoming_vehicle.queue_free()
		active_oncoming_vehicle = null
	if is_instance_valid(active_rear_stalker):
		active_rear_stalker.queue_free()
		active_rear_stalker = null
	if event_spawner and event_spawner.has_method("reset_spawner"):
		event_spawner.reset_spawner()
	_spawn_initial_track()

func _spawn_initial_track() -> void:
	# Clear any pre-existing children chunks (strictly preserve event_spawner)
	for child in get_children():
		if child == event_spawner or child == active_oncoming_vehicle or child == active_rear_stalker:
			continue
		child.queue_free()
	if is_instance_valid(active_rear_stalker):
		active_rear_stalker.queue_free()
		active_rear_stalker = null
	active_segments.clear()
	consecutive_curves = 0
	last_curve_type = RoadSegment.SegmentType.STRAIGHT
	total_segments_spawned = 0
	chunks_since_last_oncoming = 0
	chunks_since_last_supply_stop = 0
	next_supply_stop_interval = rng.randi_range(supply_stop_min_chunks, supply_stop_max_chunks)
	chunks_since_last_abandoned_car = 0
	next_abandoned_car_interval = rng.randi_range(abandoned_car_min_chunks, abandoned_car_max_chunks)
	chunks_since_last_turnoff = 0
	next_turnoff_interval = rng.randi_range(turnoff_min_chunks, turnoff_max_chunks)
	chunks_since_last_stalker = 0
	next_stalker_interval = rng.randi_range(stalker_spawn_min_chunks, stalker_spawn_max_chunks)

	# 1. Spawn a straight buffer segment behind the starting vehicle position (from Z = 80 to Z = 0)
	var initial_rear_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, segment_length))
	var rear_segment := _create_segment_node(RoadSegment.SegmentType.STRAIGHT)
	add_child(rear_segment)
	rear_segment.global_transform = initial_rear_transform
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

	var vehicle_pos := target_vehicle.global_position if target_vehicle.is_inside_tree() else target_vehicle.position

	# 1. Find closest segment to determine vehicle's current segment index
	var current_segment_index: int = 0
	var min_dist: float = INF
	for i in range(active_segments.size()):
		var segment: RoadSegment = active_segments[i]
		if not is_instance_valid(segment):
			continue
		var dist := vehicle_pos.distance_to(segment.get_exit_position())
		if dist < min_dist:
			min_dist = dist
			current_segment_index = i

	# 2. Maintain active chunks ahead of current segment
	var segments_ahead: int = active_segments.size() - 1 - current_segment_index
	while segments_ahead < max_segments_ahead:
		var next_type := _select_next_segment_type()
		_spawn_segment(next_type)
		segments_ahead += 1

	# 3. Strictly recycle old segments more than 80m behind the vehicle
	while active_segments.size() > (min_segments_ahead + 1) and current_segment_index > 0:
		var oldest_segment: RoadSegment = active_segments[0]
		if not is_instance_valid(oldest_segment):
			active_segments.pop_front()
			current_segment_index -= 1
			continue

		var dist_to_exit: float = vehicle_pos.distance_to(oldest_segment.get_exit_position())
		if dist_to_exit > despawn_distance:
			active_segments.pop_front()
			oldest_segment.queue_free()
			current_segment_index -= 1
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
	segment.segment_index = total_segments_spawned
	segment.segment_type = type
	segment.segment_length = segment_length
	segment.road_width = road_width
	segment.curve_angle_deg = curve_angle
	segment.slice_count = slice_count
	return segment

func _spawn_segment(type: RoadSegment.SegmentType) -> RoadSegment:
	var segment := _create_segment_node(type)

	var target_transform := Transform3D.IDENTITY
	if not active_segments.is_empty():
		var last_segment: RoadSegment = active_segments.back()
		target_transform = last_segment.get_exit_transform()

	add_child(segment)
	segment.global_transform = target_transform
	segment.build_segment()

	# Check supply stop spawn eligibility (guaranteed regular appearance or before fuel drops below 30%)
	var has_supply_stop: bool = false
	if enable_supply_stops and total_segments_spawned >= 3:
		chunks_since_last_supply_stop += 1
		var low_fuel_urgent: bool = false
		if target_vehicle is Van and (target_vehicle as Van).current_fuel <= 35.0 and chunks_since_last_supply_stop >= 2:
			low_fuel_urgent = true
		if chunks_since_last_supply_stop >= next_supply_stop_interval or low_fuel_urgent:
			chunks_since_last_supply_stop = 0
			next_supply_stop_interval = rng.randi_range(supply_stop_min_chunks, supply_stop_max_chunks)
			has_supply_stop = true
			_spawn_supply_stop(segment)

	# Check roadside abandoned car spawn eligibility (every 6-8 chunks)
	var has_abandoned_car: bool = false
	if enable_abandoned_cars and total_segments_spawned >= 3 and not has_supply_stop:
		chunks_since_last_abandoned_car += 1
		if chunks_since_last_abandoned_car >= next_abandoned_car_interval:
			chunks_since_last_abandoned_car = 0
			next_abandoned_car_interval = rng.randi_range(abandoned_car_min_chunks, abandoned_car_max_chunks)
			has_abandoned_car = true
			_spawn_abandoned_car(segment)

	# Check dead-end rural turnoff spawn eligibility (every 12-15 chunks)
	var has_turnoff: bool = false
	if enable_turnoffs and total_segments_spawned >= 4 and not has_supply_stop and not has_abandoned_car:
		chunks_since_last_turnoff += 1
		if chunks_since_last_turnoff >= next_turnoff_interval:
			if segment.segment_type != RoadSegment.SegmentType.CURVE_LEFT:
				chunks_since_last_turnoff = 0
				next_turnoff_interval = rng.randi_range(turnoff_min_chunks, turnoff_max_chunks)
				has_turnoff = true
				_spawn_rural_turnoff(segment)

	if enable_events and event_spawner:
		event_spawner.spawn_events_for_segment(segment, total_segments_spawned, rng, has_supply_stop or has_abandoned_car or has_turnoff)

	active_segments.append(segment)
	total_segments_spawned += 1

	_on_segment_spawned_check_oncoming()
	_on_segment_spawned_check_rear_stalker()

	return segment

func _spawn_rural_turnoff(segment: RoadSegment) -> void:
	var slice_count := segment.get_slice_count()
	if slice_count < 3:
		return

	var slice_idx: int = clampi(slice_count / 3, 1, slice_count - 2)
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	var turnoff := RuralTurnoff.new()
	turnoff.name = "RuralTurnoff_%d" % total_segments_spawned

	# Position at the right shoulder (X ≈ +8.5m, Y = 0.5m flush with road surface) and yaw branch at ~30 degrees into the woods
	var branch_yaw_deg: float = -30.0
	var local_rot := Basis(Vector3.UP, deg_to_rad(branch_yaw_deg))
	var local_offset := Vector3(8.5, 0.5, 0.0)

	turnoff.transform = slice_tr * Transform3D(local_rot, local_offset)
	segment.add_child(turnoff)
	turnoff.build_turnoff(62.0, 4.2)

func _spawn_supply_stop(segment: RoadSegment) -> void:
	var slice_count := segment.get_slice_count()
	if slice_count < 2:
		return
	var slice_idx: int = slice_count / 2
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	var stop_inst := SupplyStopScene.instantiate() as SupplyStop
	# Positioned right along the open right shoulder/berm at road surface level (Y = 0.5)
	var local_offset := Vector3(7.8, 0.5, 0.0)
	stop_inst.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(stop_inst)

func _spawn_abandoned_car(segment: RoadSegment) -> void:
	var slice_count := segment.get_slice_count()
	if slice_count < 2:
		return
	var slice_idx: int = slice_count / 2
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	var car_inst := AbandonedCarScene.instantiate() as AbandonedCar
	# Place strictly on the gravel shoulder (7.0m to 9.4m) without obstructing 14m road asphalt.
	var side_sign: float = 1.0 if rng.randf() < 0.65 else -1.0
	var local_offset := Vector3(side_sign * 8.4, 0.5, 0.0)
	var yaw_deg: float = rng.randf_range(-6.0, 6.0)
	if side_sign < 0.0:
		yaw_deg += 180.0
	var local_rot := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	car_inst.transform = slice_tr * Transform3D(local_rot, local_offset)
	segment.add_child(car_inst)

func _on_segment_spawned_check_oncoming() -> void:
	if not enable_oncoming_vehicle:
		return
	if is_instance_valid(active_oncoming_vehicle):
		return
	# Don't spawn on the initial runway chunks
	if total_segments_spawned < 4:
		return

	chunks_since_last_oncoming += 1
	if chunks_since_last_oncoming < next_oncoming_chunk_interval:
		return

	chunks_since_last_oncoming = 0
	next_oncoming_chunk_interval = rng.randi_range(oncoming_spawn_min_chunks, oncoming_spawn_max_chunks)

	if rng.randf() > oncoming_spawn_chance:
		return

	_spawn_oncoming_vehicle()

func _spawn_oncoming_vehicle() -> void:
	if active_segments.size() < 4 or not target_vehicle:
		return

	var vehicle_pos := target_vehicle.global_position if target_vehicle.is_inside_tree() else Vector3.ZERO

	# 1. Find segment closest to the player
	var current_segment_index: int = 0
	var min_dist: float = INF
	for i in range(active_segments.size()):
		var seg: RoadSegment = active_segments[i]
		var dist := vehicle_pos.distance_to(seg.get_exit_position())
		if dist < min_dist:
			min_dist = dist
			current_segment_index = i

	# 2. Select spawn chunk approx 120-150m ahead (current + 2 chunks)
	var spawn_seg_idx: int = clampi(current_segment_index + 2, 0, active_segments.size() - 1)
	if spawn_seg_idx <= current_segment_index:
		return

	# 3. Build left-lane waypoints walking backward from spawn chunk towards & past the player
	var waypoints: Array[Vector3] = []
	for s in range(spawn_seg_idx, -1, -1):
		var seg: RoadSegment = active_segments[s]
		var slices: int = seg.get_slice_count()
		for i in range(slices - 1, -1, -1):
			var slice_tr: Transform3D = seg.get_slice_transform(i)
			var global_slice: Transform3D = seg.global_transform * slice_tr
			var wp: Vector3 = global_slice.origin + global_slice.basis * Vector3(-opposing_lane_offset, 0.75, 0.0)
			waypoints.append(wp)

	if waypoints.size() < 4:
		return

	var oncoming := OncomingVehicle.new()
	oncoming.name = "OncomingDoppelganger_%d" % total_segments_spawned
	add_child(oncoming)
	oncoming.setup_waypoints(waypoints, target_vehicle)
	active_oncoming_vehicle = oncoming

func _on_segment_spawned_check_rear_stalker() -> void:
	if not enable_rear_stalker:
		return
	if is_instance_valid(active_rear_stalker):
		return
	if total_segments_spawned < 8 or not target_vehicle:
		return

	chunks_since_last_stalker += 1
	if chunks_since_last_stalker < next_stalker_interval:
		return

	# Only spawn if the player is traveling at moderate speed
	var player_speed: float = 0.0
	if target_vehicle is Van:
		player_speed = (target_vehicle as Van).current_speed_kmh
	elif target_vehicle is CharacterBody3D:
		player_speed = (target_vehicle as CharacterBody3D).velocity.length() * 3.6

	if player_speed < 15.0:
		return

	chunks_since_last_stalker = 0
	next_stalker_interval = rng.randi_range(stalker_spawn_min_chunks, stalker_spawn_max_chunks)

	_spawn_rear_stalker()

func _spawn_rear_stalker() -> void:
	if not target_vehicle or not is_instance_valid(target_vehicle):
		return
	if is_instance_valid(active_rear_stalker):
		return

	var van_basis := target_vehicle.global_transform.basis
	# Spawn ~65 meters behind the van on the asphalt (facing forward along same direction)
	var spawn_pos: Vector3 = target_vehicle.global_position + (van_basis.z * 65.0)
	spawn_pos.y = target_vehicle.global_position.y

	var stalker := RearStalker.new()
	stalker.name = "RearStalker_%d" % total_segments_spawned
	add_child(stalker)
	stalker.global_position = spawn_pos
	stalker.rotation.y = target_vehicle.rotation.y
	stalker.setup(target_vehicle)
	active_rear_stalker = stalker
