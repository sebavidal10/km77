class_name RadioManager
extends Node

const Van = preload("res://van.gd")

signal dispatch_received(text: String, duration: float)
signal static_burst_triggered(intensity: float, decay_speed: float)

static var instance: RadioManager = null

@export_group("Contextual Narrative Settings")
## Enables atmospheric narrative broadcasts and lore dispatches.
@export var enable_narrative_dispatches: bool = true
## Minimum cooldown in seconds between roadside silhouette lore broadcasts.
@export var silhouette_dispatch_cooldown: float = 16.0

# Message queue state
var _message_queue: Array[Dictionary] = []
var _is_displaying: bool = false
var _display_timer: float = 0.0
var _current_duration: float = 0.0

# Contextual milestone progression tracking
var _milestones_fired: Dictionary = {
	85: false,
	83: false,
	81: false,
	78: false,
	77: false
}

var _last_silhouette_dispatch_time: float = -999.0
var _doppelganger_dispatch_index: int = 0
var _silhouette_lore_index: int = 0

const DOPPELGANGER_DISPATCHES: Array[String] = [
	"[DISPATCH 10-33] ALL UNITS ADVISE: Unregistered forensic carrier traveling against traffic in opposing lane. NO VISIBLE OPERATOR. Do not signal high beams. Do not stop.",
	"[RADIO STATIC / 10-33] ...carrier anomaly... radar detects our exact vehicle serial number heading outbound... who is behind that wheel?!",
	"[DISPATCH ??-?] ...Do not look into the oncoming driver window. We repeat: keep your eyes on the road. It has your face..."
]

const SILHOUETTE_LORE_DISPATCHES: Array[String] = [
	"[RADIO ARCHIVE] ...Cold Case 94-077: Missing transport reported near milepost verge. Subject: Officer S. Vidal. Date: October 1994. Dispatch unconfirmed...",
	"[RADIO INTERCEPT] ...02:40 rural transit line was decommissioned in November 1989... why is dispatch showing passengers waiting at roadside shelters? Unit 77, verify...",
	"[STATIC BURST] ...figures spotted waiting along the tree line... coroner reports they have no pulse... do not stop for pedestrians on Route 77...",
	"[RADIO STATIC] ...case file 77-B: multiple drivers report seeing themselves standing on the shoulder in headlights... dispatch instructs: never brake..."
]

func _init() -> void:
	instance = self

func _ready() -> void:
	instance = self
	_connect_to_player()
	# Broadcast initial game start dispatch after brief startup pause
	get_tree().create_timer(1.2).timeout.connect(func():
		if enable_narrative_dispatches:
			broadcast_dispatch(
				"[DISPATCH 10-4] Unit 77, report status... Signal degrading past milepost 85. Proceed with caution.",
				6.5
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

## Resets all narrative milestones and timers for seamless loop recurrence.
func reset_milestones() -> void:
	for k in _milestones_fired.keys():
		_milestones_fired[k] = false
	_last_silhouette_dispatch_time = -999.0

## Broadcasts a dispatch message to the HUD subtitle overlay.
func broadcast_dispatch(text: String, duration: float = 6.0, priority: bool = false, static_glitch_intensity: float = 0.0) -> void:
	var msg := {
		"text": text,
		"duration": duration
	}

	if static_glitch_intensity > 0.01:
		static_burst_triggered.emit(static_glitch_intensity, 2.2)

	if priority:
		# Urgent events interrupt and take immediate precedence
		_message_queue.insert(0, msg)
		_show_next_in_queue()
	else:
		_message_queue.append(msg)
		if not _is_displaying:
			_show_next_in_queue()

func _show_next_in_queue() -> void:
	if _message_queue.is_empty():
		return
	var msg: Dictionary = _message_queue.pop_front()
	_is_displaying = true
	_display_timer = 0.0
	_current_duration = msg["duration"]
	dispatch_received.emit(msg["text"], msg["duration"])

## Called when the Doppelgänger oncoming patrol vehicle enters proximity.
func report_doppelganger_encounter() -> void:
	if not enable_narrative_dispatches:
		return
	var text: String = DOPPELGANGER_DISPATCHES[_doppelganger_dispatch_index % DOPPELGANGER_DISPATCHES.size()]
	_doppelganger_dispatch_index += 1
	broadcast_dispatch(text, 7.5, true, 0.85)

## Called when passing near mysterious roadside silhouettes or abandoned bus shelters.
func report_silhouette_proximity(_pos: Vector3 = Vector3.ZERO) -> void:
	if not enable_narrative_dispatches:
		return
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_silhouette_dispatch_time < silhouette_dispatch_cooldown:
		return
	_last_silhouette_dispatch_time = current_time

	var text: String = SILHOUETTE_LORE_DISPATCHES[_silhouette_lore_index % SILHOUETTE_LORE_DISPATCHES.size()]
	_silhouette_lore_index += 1
	broadcast_dispatch(text, 7.0, false, 0.45)

## Called when scavenging begins at a SupplyStop (dead air / radio silence).
func report_supply_stop_started() -> void:
	if not enable_narrative_dispatches:
		return
	broadcast_dispatch(
		"[RADIO DEAD AIR] ...carrier signal severed in dead zone... total silence on all state frequencies...",
		4.5,
		true,
		0.2
	)

## Called when scavenging finishes at a SupplyStop (static crackles back).
func report_supply_stop_completed() -> void:
	if not enable_narrative_dispatches:
		return
	broadcast_dispatch(
		"[RADIO STATIC] ...signal faintly re-acquired... supplies logged... don't stay parked out there... the dark knows you stopped...",
		6.5,
		false,
		0.5
	)

func _connect_to_player() -> void:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty() and nodes[0] is Van:
		_on_player_found(nodes[0] as Van)
	else:
		get_tree().create_timer(0.2).timeout.connect(func():
			var retry_nodes := get_tree().get_nodes_in_group("player")
			if not retry_nodes.is_empty() and retry_nodes[0] is Van:
				_on_player_found(retry_nodes[0] as Van)
		)

func _on_player_found(van: Van) -> void:
	if not van.distance_updated.is_connected(_on_van_distance_updated):
		van.distance_updated.connect(_on_van_distance_updated)
	if not van.collision_impact.is_connected(_on_collision_impact):
		van.collision_impact.connect(_on_collision_impact)

func _on_collision_impact(trauma: float) -> void:
	if not enable_narrative_dispatches:
		return
	if trauma > 0.65:
		broadcast_dispatch(
			"[DISPATCH 10-50] ...heavy impact telemetry detected on Unit 77... vehicle integrity failing... respond immediately...",
			5.5,
			true,
			0.9
		)

## Progressive narrative escalation as distance counts down toward Kilómetro 77.
func _on_van_distance_updated(_distance_meters: float, current_km: float) -> void:
	if not enable_narrative_dispatches:
		return

	# Approaching KM 77 escalation evaluated from closest to departure
	if current_km <= 77.2 and not _milestones_fired.get(77, false):
		_milestones_fired[77] = true
		broadcast_dispatch(
			"[DISPATCH 10-0] << RECURSION COLLAPSE >> ...Milepost 77 breached... the clock hands stopped... WHERE ARE YOU, UNIT 77?! ANSWER THE DISPATCH--",
			8.5,
			true,
			0.95
		)
	elif current_km <= 77.8 and not _milestones_fired.get(778, false):
		_milestones_fired[778] = true
		broadcast_dispatch(
			"[RADIO CORRUPT] << MAYDAY >> ...all state frequencies bleeding together... surveyor charts show Route 77 terminates in an empty void... TURN AROUND 77--",
			8.0,
			true,
			0.75
		)
	elif current_km <= 78.5 and not _milestones_fired.get(78, false):
		_milestones_fired[78] = true
		broadcast_dispatch(
			"[DISPATCH 10-33] Unit 77, your transponder is corrupting regional telemetry... confirm current milepost... why does your odometry count down towards zero?!",
			7.5,
			true,
			0.6
		)
	elif current_km <= 81.2 and not _milestones_fired.get(81, false):
		_milestones_fired[81] = true
		broadcast_dispatch(
			"[DISPATCH ??-?] ...all units, reports of an unregistered patrol vehicle inbound... stay sharp...",
			7.0,
			false,
			0.4
		)
	elif current_km <= 83.2 and not _milestones_fired.get(83, false):
		_milestones_fired[83] = true
		broadcast_dispatch(
			"[DISPATCH 10-4] Weather radar confirms dense atmospheric anomaly. Maintain right lane.",
			6.5
		)
