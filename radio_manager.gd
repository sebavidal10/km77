class_name RadioManager
extends Node

const Van = preload("res://van.gd")

signal dispatch_received(text: String, duration: float)

static var instance: RadioManager = null

@export_group("Narrative Milestone Dispatches")
## Enables atmospheric police dispatch messages based on kilometer progress.
@export var enable_milestone_dispatches: bool = true

var _message_queue: Array[Dictionary] = []
var _is_displaying: bool = false
var _display_timer: float = 0.0
var _current_duration: float = 0.0

# Milestone tracking state to avoid repeated broadcasts
var _milestones_fired: Dictionary = {
	85: false,
	83: false,
	81: false,
	79: false,
	77: false
}

func _init() -> void:
	instance = self

func _ready() -> void:
	instance = self
	_connect_to_player()
	# Broadcast initial game start dispatch after brief startup pause
	get_tree().create_timer(1.2).timeout.connect(func():
		broadcast_dispatch(
			"[DISPATCH 10-4] Unit 77, report status... Signal degrading past milepost 85. Proceed with caution.",
			7.0
		)
	)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if instance == self:
			instance = null

func _process(delta: float) -> void:
	if _is_displaying:
		_display_timer += delta
		if _display_timer >= _current_duration:
			_is_displaying = false
			_display_timer = 0.0
			_show_next_in_queue()
	elif not _message_queue.is_empty():
		_show_next_in_queue()

## Broadcasts a dispatch message to the HUD subtitle overlay.
func broadcast_dispatch(text: String, duration: float = 6.0, priority: bool = false) -> void:
	var msg := {
		"text": text,
		"duration": duration
	}
	if priority:
		# Urgent events (e.g. Doppelgänger encounter or crash) interrupt current transmission
		_message_queue.insert(0, msg)
		_show_next_in_queue()
	else:
		_message_queue.append(msg)

func _show_next_in_queue() -> void:
	if _message_queue.is_empty():
		return
	var msg: Dictionary = _message_queue.pop_front()
	_is_displaying = true
	_display_timer = 0.0
	_current_duration = msg["duration"]
	dispatch_received.emit(msg["text"], msg["duration"])

func _connect_to_player() -> void:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Van:
		_on_player_found(nodes[0] as Van)
	else:
		# Retry in next frame if player is still initializing
		get_tree().create_timer(0.2).timeout.connect(func():
			var retry_nodes := get_tree().get_nodes_in_group("player")
			if not retry_nodes.is_empty() and retry_nodes[0] is Van:
				_on_player_found(retry_nodes[0] as Van)
		)

func _on_player_found(van: Van) -> void:
	if not van.distance_updated.is_connected(_on_van_distance_updated):
		van.distance_updated.connect(_on_van_distance_updated)

func _on_van_distance_updated(_distance_meters: float, current_km: float) -> void:
	if not enable_milestone_dispatches:
		return

	if current_km <= 83.2 and not _milestones_fired[83]:
		_milestones_fired[83] = true
		broadcast_dispatch(
			"[DISPATCH 10-4] Weather radar confirms dense atmospheric anomaly. Maintain right lane.",
			6.5
		)
	elif current_km <= 81.2 and not _milestones_fired[81]:
		_milestones_fired[81] = true
		broadcast_dispatch(
			"[DISPATCH ??-?] ...all units, reports of an unregistered patrol vehicle inbound... stay sharp...",
			7.0
		)
	elif current_km <= 79.2 and not _milestones_fired[79]:
		_milestones_fired[79] = true
		broadcast_dispatch(
			"[DISPATCH 10-4] Unit 77, you are entering the final sector. Keep your high beams engaged.",
			6.5
		)
	elif current_km <= 77.1 and not _milestones_fired[77]:
		_milestones_fired[77] = true
		broadcast_dispatch(
			"[DISPATCH 10-0] ...radio carrier severed... Kilómetro 77 reached. No return transmission detected.",
			8.0,
			true
		)
