class_name LoopResetManager
extends Node

signal collapse_started(reason: String)
signal reboot_completed

const Van = preload("res://van.gd")
const RoadManager = preload("res://road_manager.gd")
const RadioManager = preload("res://radio_manager.gd")
const HUD = preload("res://hud.gd")
const PostProcess = preload("res://post_process.gd")

@export_group("Target Nodes")
@export var target_van: Van
@export var road_manager: RoadManager
@export var hud: HUD
@export var post_process: PostProcess

@export_group("Thresholds")
## Maximum tilt angle before rollover detection starts counting (degrees).
@export var max_rollover_angle_deg: float = 70.0
## Duration in seconds the vehicle must be tilted beyond threshold to trigger death.
@export var rollover_time_threshold: float = 2.0
## Duration of the blackout / reboot pause in seconds.
@export var reboot_duration: float = 3.0
## Deep fall Y-coordinate threshold.
@export var fall_depth_threshold: float = -4.5
## Lateral boundary threshold in meters.
@export var max_lateral_boundary: float = 35.0

var _is_rebooting: bool = false
var _rollover_timer: float = 0.0
var _reboot_timer: float = 0.0

func _ready() -> void:
	_find_dependencies()

func _physics_process(delta: float) -> void:
	if not target_van:
		_find_dependencies()
		if not target_van:
			return

	if _is_rebooting:
		_process_reboot(delta)
		return

	_check_failure_conditions(delta)

func _check_failure_conditions(delta: float) -> void:
	# 1. Rollover Check (vehicle UP vector tilts > 70 degrees from world UP)
	var up_vec: Vector3 = target_van.global_transform.basis.y
	var tilt_dot: float = up_vec.dot(Vector3.UP)
	var tilt_threshold := cos(deg_to_rad(max_rollover_angle_deg))
	if tilt_dot < tilt_threshold:
		_rollover_timer += delta
		if _rollover_timer >= rollover_time_threshold:
			start_timeline_reboot("VEHICLE ROLLOVER DETECTED")
			return
	else:
		_rollover_timer = maxf(0.0, _rollover_timer - delta * 1.5)

	# 2. Deep Ditch / Abyss Fall Check
	var pos := target_van.global_position
	if pos.y < fall_depth_threshold or absf(pos.x) > max_lateral_boundary:
		start_timeline_reboot("OUT OF BOUNDS ABYSS COLLAPSE")
		return

	# 3. Fuel Depletion Stall Check
	if target_van.current_fuel <= 0.0 and absf(target_van.current_speed_kmh) < 4.0:
		start_timeline_reboot("CRITICAL FUEL DEPLETION")
		return

	# 4. Engine Destruction Check
	if target_van.current_engine_health <= 0.0 and absf(target_van.current_speed_kmh) < 4.0:
		start_timeline_reboot("FATAL ENGINE INTEGRITY LOSS")
		return

## Triggers the fatal collapse, CRT failure display, and recursive timeline reboot.
func start_timeline_reboot(reason: String = "") -> void:
	if _is_rebooting:
		return
	_is_rebooting = true
	_reboot_timer = 0.0
	_rollover_timer = 0.0

	collapse_started.emit(reason)

	# 1. Cut inputs and forward momentum in van
	if target_van:
		target_van.is_stalled = true
		target_van.velocity = Vector3.ZERO
		target_van.forward_speed_state = 0.0

	# 2. Screen fade to black and show monospace CRT failure text
	if not hud:
		_find_hud()
	if hud:
		hud.fade_to_black(1.5)
		hud.show_reboot_message(true, "UNIT 77 CRITICAL SIGNAL FAILURE... REBOOTING TIMELINE...")

	# 3. Trigger heavy CRT static and distortion burst
	if not post_process:
		_find_post_process()
	if post_process:
		post_process.trigger_glitch(1.0, 3.5)

	# 4. Radio dispatch
	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[RADIO CRITICAL] ...Unit 77 signal lost... %s... initiating recursive temporal reboot..." % reason,
			4.0,
			true,
			0.9
		)

func _process_reboot(delta: float) -> void:
	_reboot_timer += delta

	# Extinguish headlights and taillights
	if target_van:
		if target_van.headlight_left:
			target_van.headlight_left.light_energy = move_toward(target_van.headlight_left.light_energy, 0.0, 8.0 * delta)
		if target_van.headlight_right:
			target_van.headlight_right.light_energy = move_toward(target_van.headlight_right.light_energy, 0.0, 8.0 * delta)

	if _reboot_timer >= reboot_duration:
		_execute_awakening()

func _execute_awakening() -> void:
	_is_rebooting = false
	_reboot_timer = 0.0
	_rollover_timer = 0.0

	# 1. Reset vehicle state and reposition
	if target_van:
		target_van.reset_loop_state()

	# 2. Reset road
	if not road_manager:
		_find_road_manager()
	if road_manager:
		road_manager.reset_road()

	# 3. Clear reboot text and fade in from black
	if hud:
		hud.show_reboot_message(false)
		hud.fade_from_black(2.0)

	reboot_completed.emit()

func _find_dependencies() -> void:
	var tree := get_tree()
	if not tree:
		return
	var root := tree.current_scene
	if not root:
		return

	if not target_van:
		var van_node := root.get_node_or_null("Van") as Van
		if van_node:
			target_van = van_node
		else:
			var nodes := tree.get_nodes_in_group("player")
			if not nodes.is_empty() and nodes[0] is Van:
				target_van = nodes[0] as Van

	if not road_manager:
		road_manager = root.get_node_or_null("RoadManager") as RoadManager

	if not hud:
		_find_hud()

	if not post_process:
		_find_post_process()

func _find_hud() -> void:
	var tree := get_tree()
	if not tree:
		return
	var nodes := tree.get_nodes_in_group("hud")
	if not nodes.is_empty() and nodes[0] is HUD:
		hud = nodes[0] as HUD
		return
	var root := tree.current_scene
	if root:
		hud = root.get_node_or_null("HUD") as HUD

func _find_post_process() -> void:
	var root := get_tree().current_scene if get_tree() else null
	if root:
		post_process = root.get_node_or_null("PostProcessLayer") as PostProcess

func _find_road_manager() -> void:
	var root := get_tree().current_scene if get_tree() else null
	if root:
		road_manager = root.get_node_or_null("RoadManager") as RoadManager
