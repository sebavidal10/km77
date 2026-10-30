class_name SupplyStop
extends Node3D

signal scavenge_started
signal scavenge_completed

@export_group("Scavenge Parameters")
## Required time in seconds to complete progressive refueling (2 to 3 seconds).
@export var scavenge_required_time: float = 2.5
## Amount of fuel restored upon completion (100% full tank).
@export var fuel_reward: float = 100.0
## Amount of engine health restored upon completion.
@export var health_repair_reward: float = 50.0
## Maximum speed in km/h allowed while refueling (< 5 km/h).
@export var max_scavenge_speed_kmh: float = 5.0

# Node references
@onready var interaction_area: Area3D = %InteractionArea
@onready var flare_light: OmniLight3D = %FlareLight
@onready var flare_tip: MeshInstance3D = %FlareTip
@onready var supply_beacon_light: OmniLight3D = get_node_or_null("%SupplyBeaconLight") as OmniLight3D
@onready var fuel_canister: MeshInstance3D = get_node_or_null("%FuelCanister") as MeshInstance3D

# Internal state
var van_in_zone: Van = null
var is_depleted: bool = false
var is_flare_active: bool = true
var scavenge_time: float = 0.0
var _flare_noise_time: float = 0.0
var _tip_material: StandardMaterial3D = null
var _fuel_given: float = 0.0
var _repair_given: float = 0.0

const GothicLamppostModel = preload("res://models/route77_gothic_lamppost.glb")
const RoadsideShrineModel = preload("res://models/route77_roadside_shrine.glb")
const GothicChapelModel = preload("res://models/route77_gothic_chapel.glb")

func _ready() -> void:
	_build_service_access_road()
	_build_gothic_parish_props()

	# Ensure input action exists
	_ensure_interact_action()

	if flare_tip and flare_tip.get_surface_override_material(0):
		_tip_material = flare_tip.get_surface_override_material(0).duplicate() as StandardMaterial3D
		flare_tip.set_surface_override_material(0, _tip_material)

	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)

	_apply_distance_fade(self)

func _build_gothic_parish_props() -> void:
	# Twin Victorian Gothic lampposts flanking the Parish Sanctuary island
	if GothicLamppostModel:
		for z_pos in [-6.0, 6.0]:
			var lamp := GothicLamppostModel.instantiate()
			lamp.position = Vector3(-1.5, 0.0, z_pos)
			lamp.rotation.y = PI * 0.5
			add_child(lamp)
			var gas_light := OmniLight3D.new()
			gas_light.position = Vector3(-1.5, 4.9, z_pos)
			gas_light.light_color = Color(1.0, 0.58, 0.24, 1.0)
			gas_light.light_energy = 4.2
			gas_light.omni_range = 14.0
			add_child(gas_light)

	# Roadside Shrine (Animita) with red votive candle light beside the station
	if RoadsideShrineModel:
		var shrine := RoadsideShrineModel.instantiate()
		shrine.position = Vector3(2.4, 0.0, 1.8)
		shrine.rotation.y = -PI * 0.5
		add_child(shrine)
		var candle := OmniLight3D.new()
		candle.position = Vector3(2.1, 0.65, 1.8)
		candle.light_color = Color(1.0, 0.16, 0.12, 1.0)
		candle.light_energy = 3.2
		candle.omni_range = 7.5
		add_child(candle)

	# Gothic Chapel framing the Parish Sanctuary in the mist behind the station
	if GothicChapelModel:
		var chapel := GothicChapelModel.instantiate()
		chapel.position = Vector3(11.5, 0.0, 0.0)
		chapel.rotation.y = -PI * 0.5
		chapel.scale = Vector3(0.75, 0.75, 0.75)
		add_child(chapel)

## Builds a two-ended service road so the vehicle leaves the highway, passes the pumps,
## and merges back into the same route farther ahead.
func _build_service_access_road() -> void:
	if has_node("ServiceAccessRoad"):
		return

	var points: Array[Vector3] = [
		Vector3(-7.5, -0.075, 34.0),
		Vector3(-7.5, -0.075, 26.0),
		Vector3(-7.0, -0.075, 18.0),
		Vector3(-5.5, -0.075, 10.0),
		Vector3(-3.5, -0.075, 4.0),
		Vector3(-3.0, -0.075, 0.0),
		Vector3(-3.5, -0.075, -4.0),
		Vector3(-5.5, -0.075, -10.0),
		Vector3(-7.0, -0.075, -18.0),
		Vector3(-7.5, -0.075, -26.0),
		Vector3(-7.5, -0.075, -34.0),
	]
	var sampled: Array[Vector3] = []
	for i in range(points.size() - 1):
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, points.size() - 1)]
		for step in range(5):
			var t := float(step) / 5.0
			var t2 := t * t
			var t3 := t2 * t
			sampled.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	sampled.append(points.back())

	var access_body := StaticBody3D.new()
	access_body.name = "ServiceAccessRoad"
	access_body.collision_layer = 1
	access_body.collision_mask = 1
	add_child(access_body)
	var access_mat := StandardMaterial3D.new()
	access_mat.albedo_color = Color(0.075, 0.075, 0.08, 1.0)
	access_mat.roughness = 0.96
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.58, 0.58, 0.54, 1.0)
	edge_mat.roughness = 0.6
	edge_mat.emission_enabled = true
	edge_mat.emission = Color(0.28, 0.27, 0.23, 1.0)
	edge_mat.emission_energy_multiplier = 0.22
	for i in range(sampled.size() - 1):
		var start: Vector3 = sampled[i]
		var finish: Vector3 = sampled[i + 1]
		var delta: Vector3 = finish - start
		var length := Vector2(delta.x, delta.z).length()
		if length < 0.01:
			continue
		var yaw := atan2(-delta.x, -delta.z)
		var center := (start + finish) * 0.5
		var road_mesh := BoxMesh.new()
		road_mesh.size = Vector3(6.0, 0.15, length + 0.12)
		road_mesh.material = access_mat
		var road_visual := MeshInstance3D.new()
		road_visual.name = "AccessSlice_%02d" % i
		road_visual.mesh = road_mesh
		road_visual.transform = Transform3D(Basis(Vector3.UP, yaw), center)
		access_body.add_child(road_visual)
		var road_col := CollisionShape3D.new()
		road_col.name = "AccessCollider_%02d" % i
		var road_shape := BoxShape3D.new()
		road_shape.size = road_mesh.size
		road_col.shape = road_shape
		road_col.transform = road_visual.transform
		access_body.add_child(road_col)

		# Subtle edge paint makes the entrance and rejoin readable in the fog.
		for side in [-1.0, 1.0]:
			var edge_mesh := BoxMesh.new()
			edge_mesh.size = Vector3(0.075, 0.012, length + 0.12)
			edge_mesh.material = edge_mat
			var edge_visual := MeshInstance3D.new()
			edge_visual.name = "AccessEdge_%02d_%s" % [i, "L" if side < 0.0 else "R"]
			edge_visual.mesh = edge_mesh
			var edge_transform := road_visual.transform
			edge_transform.origin += edge_transform.basis * Vector3(side * 2.82, 0.082, 0.0)
			edge_visual.transform = edge_transform
			access_body.add_child(edge_visual)

func _process(delta: float) -> void:
	_process_flare_effects(delta)
	_process_interaction(delta)

## Dynamic chemical flare pulsing and burning tip emission.
func _process_flare_effects(delta: float) -> void:
	if not flare_light:
		return

	if is_flare_active:
		_flare_noise_time += delta * 18.0
		var flicker := (sin(_flare_noise_time) * 0.45) + (sin(_flare_noise_time * 2.37) * 0.35) + randf_range(-0.35, 0.35)
		flare_light.light_color = Color(1.0, 0.133333, 0.0, 1.0) # #FF2200 Vivid crimson flare
		flare_light.light_energy = clampf(8.5 + flicker * 2.8, 3.5, 12.0)
		if _tip_material:
			_tip_material.emission = Color(1.0, 0.133333, 0.0, 1.0)
			_tip_material.emission_energy_multiplier = clampf(6.0 + flicker * 2.2, 3.0, 9.5)
	else:
		# Gradually extinguish flare to dark ash
		flare_light.light_energy = move_toward(flare_light.light_energy, 0.0, 7.5 * delta)
		if _tip_material:
			_tip_material.emission_energy_multiplier = move_toward(_tip_material.emission_energy_multiplier, 0.0, 4.0 * delta)
			if _tip_material.emission_energy_multiplier <= 0.01:
				_tip_material.emission_enabled = false
		if flare_light.light_energy <= 0.01:
			flare_light.visible = false
		if supply_beacon_light:
			supply_beacon_light.set_process(false)
			supply_beacon_light.light_energy = move_toward(supply_beacon_light.light_energy, 0.3, 6.0 * delta)

## Handles vehicle speed checks, progressive refueling, and HUD prompts.
func _process_interaction(delta: float) -> void:
	if not van_in_zone:
		return

	var current_speed: float = van_in_zone.velocity.length() * 3.6
	var is_stopped: bool = current_speed < max_scavenge_speed_kmh

	if is_stopped:
		if not is_depleted:
			var holding_interact: bool = Input.is_action_pressed("interact") or Input.is_key_pressed(KEY_E)
			if holding_interact:
				if scavenge_time == 0.0:
					scavenge_started.emit()
					if RadioManager.instance:
						RadioManager.instance.report_supply_stop_started()
				scavenge_time += delta
				var ratio := clampf(scavenge_time / scavenge_required_time, 0.0, 1.0)
				_update_hud_prompt("† MANTÉN [E] — CONSAGRANDO MOTOR Y REPOSTANDO...", ratio)

				# Rewards accumulate only while E is held. Releasing E pauses the
				# service; leaving early keeps the fuel and repairs already received.
				var service_ratio := 1.0 / maxf(scavenge_required_time, 0.1)
				var fuel_step: float = minf(fuel_reward * service_ratio * delta, fuel_reward - _fuel_given)
				var repair_step: float = minf(health_repair_reward * service_ratio * delta, health_repair_reward - _repair_given)
				if fuel_step > 0.0:
					van_in_zone.add_fuel(fuel_step)
					_fuel_given += fuel_step
				if repair_step > 0.0:
					van_in_zone.repair_vehicle(repair_step)
					_repair_given += repair_step

			if scavenge_time >= scavenge_required_time:
				_complete_scavenge()
			else:
				_update_hud_prompt("† [MANTÉN E] — POSTA PARROQUIAL DE AUXILIO", clampf(scavenge_time / scavenge_required_time, 0.0, 1.0))
		else:
			_hide_hud_prompt()
	else:
		# Do not erase progress or the resources already recovered when the van
		# moves away from the pump area.
		if not is_depleted:
			_update_hud_prompt("DETÉN EL FURGÓN EN LA POSTA Y MANTÉN [E]", clampf(scavenge_time / scavenge_required_time, 0.0, 1.0))
		else:
			_hide_hud_prompt()


func _complete_scavenge() -> void:
	is_depleted = true
	is_flare_active = false
	scavenge_time = 0.0

	if van_in_zone:
		# Top up only the remaining portion of this stop's advertised rewards.
		var fuel_remaining := maxf(0.0, fuel_reward - _fuel_given)
		var repair_remaining := maxf(0.0, health_repair_reward - _repair_given)
		van_in_zone.add_fuel(fuel_remaining)
		van_in_zone.repair_vehicle(repair_remaining)

	if fuel_canister:
		fuel_canister.visible = false

	# Disable area to prevent repeated use
	if interaction_area:
		interaction_area.set_deferred("monitoring", false)

	if RadioManager.instance:
		RadioManager.instance.report_supply_stop_completed()

	var hud := _find_hud()
	if hud:
		hud.show_scavenge_success("[ † POSTA PARROQUIAL: COMBUSTIBLE 100% | FURGÓN CONSAGRADO † ]", 3.0)

	scavenge_completed.emit()

func _on_body_entered(body: Node3D) -> void:
	if body is Van:
		van_in_zone = body
		if not is_depleted:
			var current_speed: float = van_in_zone.velocity.length() * 3.6
			if current_speed < max_scavenge_speed_kmh:
				_update_hud_prompt("† [MANTÉN E] — POSTA PARROQUIAL DE AUXILIO", clampf(scavenge_time / scavenge_required_time, 0.0, 1.0))
			else:
				_update_hud_prompt("DETÉN EL FURGÓN EN LA POSTA Y MANTÉN [E]", clampf(scavenge_time / scavenge_required_time, 0.0, 1.0))

func _on_body_exited(body: Node3D) -> void:
	if body == van_in_zone:
		van_in_zone = null
		_hide_hud_prompt()

func _update_hud_prompt(text: String, progress: float) -> void:
	var hud := _find_hud()
	if hud:
		hud.show_scavenge_prompt(text, progress)

func _hide_hud_prompt() -> void:
	var hud := _find_hud()
	if hud:
		hud.hide_scavenge_prompt()

func _find_hud() -> HUD:
	var tree := get_tree()
	if not tree:
		return null
	var nodes := tree.get_nodes_in_group("hud")
	if not nodes.is_empty() and nodes[0] is HUD:
		return nodes[0] as HUD
	if tree.current_scene:
		var hud_candidate := tree.current_scene.get_node_or_null("HUD") as HUD
		if hud_candidate:
			return hud_candidate
	return null

func _ensure_interact_action() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var key_ev := InputEventKey.new()
		key_ev.physical_keycode = KEY_E
		InputMap.action_add_event("interact", key_ev)

func _apply_distance_fade(node: Node) -> void:
	# Ensure distance fade is strictly disabled to prevent premature culling on proximity
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var surface_count := mi.mesh.get_surface_count() if mi.mesh else 0
		for surface_idx in range(surface_count):
			var material := mi.get_active_material(surface_idx)
			if material is BaseMaterial3D:
				(material as BaseMaterial3D).distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	for child in node.get_children():
		_apply_distance_fade(child)
