class_name Hitchhiker
extends Node3D

@export_group("Tracking")
## Maximum distance within which the hitchhiker turns to look at the player's vehicle.
@export var tracking_range: float = 30.0
## Smooth rotational speed (radians per second) when tracking the passing vehicle.
@export var turn_speed: float = 4.2
## Proximity radius in meters to consider the vehicle adjacent to the figure.
@export var proximity_dist: float = 7.0
## Speed threshold in km/h below which the player is considered stopped or crawling.
@export var stop_speed_kmh: float = 5.0
## Duration the figure freezes staring at the driver before vanishing (seconds).
@export var stare_freeze_duration: float = 1.2

var target_node: Node3D
var head_node: Node3D
var torso_node: Node3D
var collision_body: CollisionObject3D

var _reported_proximity: bool = false
var _stare_timer: float = 0.0
var _is_vanishing: bool = false

func _ready() -> void:
	head_node = get_node_or_null("Head") as Node3D
	torso_node = get_node_or_null("Torso") as Node3D
	collision_body = get_node_or_null("HitchhikerCollision") as CollisionObject3D
	_find_player()

func _process(delta: float) -> void:
	if _is_vanishing:
		return

	if not target_node:
		_find_player()
		if not target_node:
			return

	var to_target := target_node.global_position - global_position
	var dist := to_target.length()

	# 1. Reactive Tracking when within 30 meters
	if dist <= tracking_range:
		if not _reported_proximity and dist <= 20.0:
			_reported_proximity = true
			if RadioManager.instance:
				RadioManager.instance.report_silhouette_proximity(global_position)

		# Horizontal direction to vehicle
		var to_vehicle_h := Vector3(to_target.x, 0.0, to_target.z)
		if to_vehicle_h.length_squared() > 0.01:
			var target_yaw := atan2(-to_vehicle_h.x, -to_vehicle_h.z)

			# 2. Proximity Vanishing Check: vehicle slowing down or stopping within 7 meters (< 5 km/h)
			var is_stopped_or_slow: bool = false
			if target_node is Van:
				var van := target_node as Van
				is_stopped_or_slow = van.current_speed_kmh < stop_speed_kmh or van.velocity.length() < 1.4
			elif target_node is CharacterBody3D:
				var cb := target_node as CharacterBody3D
				is_stopped_or_slow = cb.velocity.length() * 3.6 < stop_speed_kmh

			if dist <= proximity_dist and is_stopped_or_slow:
				# Freeze staring directly into the driver cabin
				rotation.y = lerp_angle(rotation.y, target_yaw, 8.0 * delta)
				if head_node:
					head_node.rotation.y = lerp_angle(head_node.rotation.y, 0.0, 8.0 * delta)

				_stare_timer += delta
				if _stare_timer >= stare_freeze_duration:
					_start_vanishing()
				return
			else:
				_stare_timer = maxf(0.0, _stare_timer - delta * 0.8)

			# Smooth upper body / head node rotation to face the van as it drives past
			rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)
			if head_node:
				var head_local_target: float = wrapf(target_yaw - rotation.y, -PI, PI)
				head_node.rotation.y = lerp_angle(head_node.rotation.y, head_local_target, turn_speed * 1.6 * delta)
	else:
		_stare_timer = 0.0

func _start_vanishing() -> void:
	if _is_vanishing:
		return
	_is_vanishing = true

	# Disable collision immediately so player doesn't collide with phantom body
	if collision_body:
		collision_body.collision_layer = 0
		collision_body.collision_mask = 0

	var tween := create_tween()
	tween.set_parallel(true)
	# Smoothly melt down into the misty roadside grass over 0.85s
	tween.tween_property(self, "scale:y", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:x", 0.02, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:z", 0.02, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Fade materials of child meshes to 0.0 alpha
	for child in get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var base_mat: StandardMaterial3D = mi.material_override as StandardMaterial3D if mi.material_override else mi.mesh.material as StandardMaterial3D
			if base_mat:
				var dup := base_mat.duplicate() as StandardMaterial3D
				dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi.material_override = dup
				tween.tween_property(dup, "albedo_color:a", 0.0, 0.85)

	tween.chain().tween_callback(queue_free)

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
