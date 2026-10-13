class_name AbandonedCar
extends StaticBody3D

@export_group("Interior Lighting")
## Whether the interior dome light is still flickering or completely dead.
@export var is_dome_light_flickering: bool = true
## Base illumination energy of the dying dome light bulb.
@export var base_dome_energy: float = 0.75

const FORENSIC_LOGS: Array[String] = [
	"Report #04: Patrol cruiser found idling in rain. Driver's wallet left on passenger seat. Heavy bootprints lead directly into the dark woods and abruptly vanish.",
	"Report #19: Glovebox contained a wet map of Route 77 with milepost 77 heavily circled in black ink. Handwritten note: 'The odometer won't go past 77.0. It starts over every time.'",
	"Report #31: Abandoned transport sedan. Key still in ignition turned to ACC. Dashboard radio locked on continuous white noise. Driver side window shattered from the inside.",
	"Report #55: Evidence log: Found police badge #077 covered in road grit. Vehicle registration matches our unit's plates. How is this car already here?",
	"Report #72: Incident report: Driver reported seeing high beams approaching from nowhere. Car stalled out, headlights shattered. Audio cassette in player repeats: 'Turn around before milepost 77.'"
]

@onready var dome_light: OmniLight3D = $DomeLight
@onready var door_pivot: Node3D = $DoorPivot
@onready var proximity_area: Area3D = $ProximityArea
@onready var search_area: Area3D = $SearchArea

var _reported_narrative: bool = false
var _flicker_noise: float = 0.0

var van_in_search_zone: Van = null
var is_searched: bool = false
var _search_hold_timer: float = 0.0
const REQUIRED_SEARCH_TIME: float = 2.0

func _ready() -> void:
	add_to_group("heavy_obstacle")
	collision_layer = 1
	collision_mask = 1

	if proximity_area:
		proximity_area.body_entered.connect(_on_proximity_entered)

	if search_area:
		search_area.body_entered.connect(_on_search_area_entered)
		search_area.body_exited.connect(_on_search_area_exited)

	# 35% chance the dome light battery is completely dead
	if randf() < 0.35:
		is_dome_light_flickering = false
		if dome_light:
			dome_light.visible = false
			dome_light.light_energy = 0.0

	_apply_distance_fade(self)

func _process(delta: float) -> void:
	_process_dome_light(delta)
	_process_glovebox_search(delta)

func _process_dome_light(delta: float) -> void:
	if not is_dome_light_flickering or not dome_light:
		return

	_flicker_noise += delta * 12.0
	var flicker := (sin(_flicker_noise * 1.7) * 0.35) + randf_range(-0.35, 0.35)
	if randf() < 0.12:
		# Rapid brownout dropout
		dome_light.light_energy = 0.05
	else:
		dome_light.light_energy = clampf(base_dome_energy + flicker * 0.45, 0.1, 1.2)

func _process_glovebox_search(delta: float) -> void:
	if is_searched or not van_in_search_zone:
		return

	var is_stopped: bool = absf(van_in_search_zone.current_speed_kmh) < 2.0 or van_in_search_zone.velocity.length() < 0.6
	var hud := _find_hud()

	if is_stopped:
		var wants_interact: bool = Input.is_action_pressed("interact")
		if wants_interact:
			_search_hold_timer += delta
			var ratio := clampf(_search_hold_timer / REQUIRED_SEARCH_TIME, 0.0, 1.0)
			if hud:
				hud.show_scavenge_prompt("SEARCHING GLOVEBOX...", ratio)

			if _search_hold_timer >= REQUIRED_SEARCH_TIME:
				_complete_glovebox_search()
		else:
			if _search_hold_timer > 0.0:
				_search_hold_timer = 0.0
			if hud:
				hud.show_scavenge_prompt("[HOLD E] SEARCH GLOVEBOX", 0.0)
	else:
		if _search_hold_timer > 0.0:
			_search_hold_timer = 0.0
		if hud:
			hud.hide_scavenge_prompt()

func _complete_glovebox_search() -> void:
	is_searched = true
	_search_hold_timer = 0.0

	var hud := _find_hud()
	if hud:
		hud.hide_scavenge_prompt()
		var log_entry: String = FORENSIC_LOGS[randi() % FORENSIC_LOGS.size()]
		hud.show_forensic_log(log_entry, 6.0)

	if search_area:
		search_area.set_deferred("monitoring", false)
		search_area.set_deferred("monitorable", false)

func _on_search_area_entered(body: Node3D) -> void:
	if is_searched:
		return
	if body is Van:
		van_in_search_zone = body as Van

func _on_search_area_exited(body: Node3D) -> void:
	if body == van_in_search_zone:
		van_in_search_zone = null
		_search_hold_timer = 0.0
		var hud := _find_hud()
		if hud and not is_searched:
			hud.hide_scavenge_prompt()

func _on_proximity_entered(body: Node3D) -> void:
	if _reported_narrative:
		return
	if body is Van:
		_reported_narrative = true
		if RadioManager.instance:
			RadioManager.instance.broadcast_dispatch(
				"[DISPATCH] ...unattended sedan spotted on shoulder... driver door swung wide... no occupants in area...",
				6.5,
				true,
				0.65
			)

func _find_hud() -> HUD:
	var tree := get_tree()
	if not tree:
		return null
	var nodes := tree.get_nodes_in_group("hud")
	if not nodes.is_empty() and nodes[0] is HUD:
		return nodes[0] as HUD
	if tree.current_scene:
		var candidate := tree.current_scene.get_node_or_null("HUD") as HUD
		if candidate:
			return candidate
	return null

func _apply_distance_fade(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			var mat := mi.material_override as BaseMaterial3D
			mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
		if mi.mesh and mi.mesh.material is BaseMaterial3D:
			var mat := mi.mesh.material as BaseMaterial3D
			mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(i)
			if mat is BaseMaterial3D:
				var bmat := mat as BaseMaterial3D
				bmat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	for child in node.get_children():
		_apply_distance_fade(child)
