class_name Hitchhiker
extends Node3D

const RadioManager = preload("res://radio_manager.gd")
const Van = preload("res://van.gd")

@export_group("Tracking")
## Maximum distance within which the hitchhiker turns to look at the player's vehicle.
@export var tracking_range: float = 25.0
## Smooth rotational speed (radians per second) when tracking the passing vehicle.
@export var turn_speed: float = 3.2

var target_node: Node3D
var head_node: Node3D
var torso_node: Node3D
var collision_body: CollisionObject3D

var _reported_proximity: bool = false
var _stopped_timer: float = 0.0
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

	var dist := global_position.distance_to(target_node.global_position)

	# 1. Reactive Tracking when within 25 meters
	if dist <= tracking_range:
		if not _reported_proximity and dist <= 20.0:
			_reported_proximity = true
			if RadioManager.instance:
				RadioManager.instance.report_silhouette_proximity(global_position)

		# Direction to vehicle on horizontal plane
		var to_target := target_node.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			var target_rot_y := atan2(to_target.x, to_target.z) + PI
			# Rotate head progressively towards the vehicle
			if head_node:
				var head_local_target := target_rot_y - rotation.y
				head_node.rotation.y = rotate_toward(head_node.rotation.y, head_local_target, turn_speed * 1.5 * delta)
			# Rotate upper torso / body smoothly
			rotation.y = rotate_toward(rotation.y, target_rot_y, turn_speed * delta)

		# 2. Vanishing behavior if player halts within 6 meters to observe closely
		if dist <= 6.0:
			var is_stopped: bool = false
			if target_node is Van:
				var van := target_node as Van
				is_stopped = absf(van.current_speed_kmh) < 2.0 or van.velocity.length() < 0.5
			elif target_node is CharacterBody3D:
				is_stopped = (target_node as CharacterBody3D).velocity.length() < 0.5

			if is_stopped:
				_stopped_timer += delta
				if _stopped_timer >= 1.5:
					_start_vanishing()
			else:
				_stopped_timer = maxf(0.0, _stopped_timer - delta * 0.5)
		else:
			_stopped_timer = 0.0

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
	# Smoothly melt down into the misty shoulder over 0.85s
	tween.tween_property(self, "scale:y", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:x", 0.05, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:z", 0.05, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
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
