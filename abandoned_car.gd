class_name AbandonedCar
extends StaticBody3D

@export_group("Interior Lighting")
## Whether the interior dome light is still flickering or completely dead.
@export var is_dome_light_flickering: bool = true
## Base illumination energy of the dying dome light bulb.
@export var base_dome_energy: float = 0.75

const FORENSIC_LOGS: Array[String] = [
	"† Registro #04: Coche fúnebre hallado en ralentí bajo la niebla. El odómetro sigue girando, aunque las cuatro ruedas están bloqueadas y las velas del altar cercano siguen tibias.",
	"† Registro #19: Mapa húmedo de la Ruta 77 con el hito 77 marcado con cera roja. Nota manuscrita: 'Las campanas de la capilla en ruinas suenan cada vez que el odómetro vuelve a 85.0.'",
	"† Registro #31: Sedán abandonado junto a una animita de piedra. La radio repite una letanía en estática blanca. Todas las ventanas tienen marcas de manos por dentro.",
	"† Registro #55: Evidencia: Placa forense #077 cubierta de ceniza. La carroza negra con cortinas carmesí nos adelantó dos veces sin conductor al volante.",
	"† Registro #72: Informe final: Cruzamos el arco gótico de piedra en el Km 77. Las luces altas aparecieron de la nada y los cuervos cubrieron el asfalto."
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
				hud.show_scavenge_prompt("† RECUPERANDO RELIQUIA DE 1989...", ratio)

			if _search_hold_timer >= REQUIRED_SEARCH_TIME:
				_complete_glovebox_search()
		else:
			if _search_hold_timer > 0.0:
				_search_hold_timer = 0.0
			if hud:
				hud.show_scavenge_prompt("[MANTÉN E] INSPECCIONAR RELIQUIA FORENSE", 0.0)
	else:
		if _search_hold_timer > 0.0:
			_search_hold_timer = 0.0
		if hud:
			hud.hide_scavenge_prompt()

func _complete_glovebox_search() -> void:
	is_searched = true
	_search_hold_timer = 0.0

	var current_relics: int = 1
	if van_in_search_zone:
		van_in_search_zone.collect_relic()
		current_relics = van_in_search_zone.relics_collected

	var hud := _find_hud()
	if hud:
		hud.hide_scavenge_prompt()
		var log_entry: String = FORENSIC_LOGS[(current_relics - 1) % FORENSIC_LOGS.size()]
		var header_str := "† RELIQUIA CONSAGRADA (%d/3) // ARCHIVO 1989 †" % current_relics
		hud.show_forensic_log(log_entry, 7.5, header_str)
		hud.show_scavenge_success("[ † RELIQUIA %d/3 RECUPERADA | +15%% COMBUSTIBLE | +20%% MOTOR † ]" % current_relics, 3.2)

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
				"[CENTRAL] ...vehículo abandonado en la berma con luz interior encendida... deténgase y mantenga [E] para recuperar la Reliquia Forense...",
				6.5,
				true,
				0.55
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
		var surface_count := mi.mesh.get_surface_count() if mi.mesh else 0
		for surface_idx in range(surface_count):
			var material := mi.get_active_material(surface_idx)
			if material is BaseMaterial3D:
				(material as BaseMaterial3D).distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	for child in node.get_children():
		_apply_distance_fade(child)
