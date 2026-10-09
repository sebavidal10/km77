class_name Hitchhiker
extends Node3D

@export_group("Tracking")
## Maximum distance within which the hitchhiker turns to look at the player's vehicle.
@export var tracking_range: float = 38.0
## Smooth rotational speed (radians per second) when tracking the passing vehicle.
@export var turn_speed: float = 2.4

var target_node: Node3D

func _ready() -> void:
	_find_player()

func _process(delta: float) -> void:
	if not target_node:
		_find_player()
		return

	var dist := global_position.distance_to(target_node.global_position)
	if dist <= tracking_range:
		# Smoothly rotate around Y-axis to track the passing vehicle
		var to_target := target_node.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			var target_rot_y := atan2(to_target.x, to_target.z) + PI
			rotation.y = rotate_toward(rotation.y, target_rot_y, turn_speed * delta)

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
