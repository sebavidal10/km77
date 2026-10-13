class_name SupplyStop
extends Node3D

signal scavenge_started
signal scavenge_completed
signal threat_triggered_signal

@export_group("Scavenge Parameters")
## Required time in seconds to complete progressive refueling (2 to 3 seconds).
@export var scavenge_required_time: float = 2.5
## Amount of fuel restored upon completion (100% full tank).
@export var fuel_reward: float = 100.0
## Amount of engine health restored upon completion.
@export var health_repair_reward: float = 50.0
## Maximum speed in km/h allowed while refueling (< 5 km/h).
@export var max_scavenge_speed_kmh: float = 5.0

@export_group("Threat / Risk Parameters")
## Duration in seconds lingering stopped before the eerie threat silhouette appears.
@export var threat_delay_seconds: float = 6.5

# Node references
@onready var interaction_area: Area3D = %InteractionArea
@onready var flare_light: OmniLight3D = %FlareLight
@onready var flare_tip: MeshInstance3D = %FlareTip
@onready var threat_silhouette: Node3D = %ThreatSilhouette
@onready var supply_beacon_light: OmniLight3D = get_node_or_null("%SupplyBeaconLight") as OmniLight3D
@onready var fuel_canister: MeshInstance3D = get_node_or_null("%FuelCanister") as MeshInstance3D

# Internal state
var van_in_zone: Van = null
var is_depleted: bool = false
var is_flare_active: bool = true
var scavenge_time: float = 0.0
var stopped_idle_time: float = 0.0
var threat_timer: float = 0.0
var threat_triggered: bool = false
var _flare_noise_time: float = 0.0
var _tip_material: StandardMaterial3D = null

func _ready() -> void:
	# Ensure input action exists
	_ensure_interact_action()

	if threat_silhouette:
		threat_silhouette.visible = false

	if flare_tip and flare_tip.get_surface_override_material(0):
		_tip_material = flare_tip.get_surface_override_material(0).duplicate() as StandardMaterial3D
		flare_tip.set_surface_override_material(0, _tip_material)

	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)

	_apply_distance_fade(self)

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
			supply_beacon_light.light_energy = move_toward(supply_beacon_light.light_energy, 0.5, 6.0 * delta)

## Handles vehicle speed checks, progressive refueling, HUD prompts, and threat tension.
func _process_interaction(delta: float) -> void:
	if not van_in_zone:
		return

	var current_speed: float = van_in_zone.velocity.length() * 3.6
	var is_stopped: bool = current_speed < max_scavenge_speed_kmh

	if is_stopped:
		# 1. Threat Timer (danger builds while waiting in the dark)
		threat_timer += delta
		if threat_timer >= threat_delay_seconds and not threat_triggered:
			_trigger_threat()

		# 2. Refueling Progression (starts immediately on [E] hold or automatically after brief stop)
		if not is_depleted:
			stopped_idle_time += delta
			var holding_interact: bool = Input.is_action_pressed("interact") or Input.is_key_pressed(KEY_E)
			if holding_interact or stopped_idle_time >= 0.35 or scavenge_time > 0.0:
				if scavenge_time == 0.0:
					scavenge_started.emit()
					if RadioManager.instance:
						RadioManager.instance.report_supply_stop_started()
				scavenge_time += delta
				var ratio := clampf(scavenge_time / scavenge_required_time, 0.0, 1.0)
				_update_hud_prompt("REFUELING VEHICLE...", ratio)

				# Progressively refill fuel gauge back to 100% over scavenge_required_time (2.5s)
				var fuel_step: float = (van_in_zone.max_fuel / maxf(scavenge_required_time, 0.1)) * delta
				van_in_zone.add_fuel(fuel_step)
				var repair_step: float = (health_repair_reward / maxf(scavenge_required_time, 0.1)) * delta
				van_in_zone.repair_vehicle(repair_step)

				if scavenge_time >= scavenge_required_time or van_in_zone.current_fuel >= van_in_zone.max_fuel:
					_complete_scavenge()
			else:
				_update_hud_prompt("[E] HOLD TO REFUEL", 0.0)
	else:
		# Vehicle is moving inside trigger zone: show prompt to stop if not depleted
		stopped_idle_time = 0.0
		if scavenge_time > 0.0:
			scavenge_time = 0.0
		if not is_depleted:
			_update_hud_prompt("[E] HOLD TO REFUEL (STOP VEHICLE < 5 KM/H)", 0.0)
		else:
			_hide_hud_prompt()

		# Fleeing from threat silhouette
		if threat_triggered and current_speed > 5.0:
			_dismiss_threat()

func _trigger_threat() -> void:
	threat_triggered = true
	threat_triggered_signal.emit()

	if van_in_zone and threat_silhouette:
		# Position silhouette right outside driver's window (left side of van)
		var van_left := -van_in_zone.global_transform.basis.x
		var van_fwd := -van_in_zone.global_transform.basis.z
		threat_silhouette.global_position = van_in_zone.global_position + (van_left * 1.55) + (van_fwd * 0.3)
		threat_silhouette.global_position.y = 0.0

		var look_target := van_in_zone.global_position + Vector3(0.0, 1.2, 0.0)
		threat_silhouette.look_at(look_target, Vector3.UP)
		threat_silhouette.visible = true

		# Trigger violent headlight strobing and trauma shake
		if van_in_zone.has_method("trigger_threat_glitch"):
			van_in_zone.trigger_threat_glitch()

		# Radio warning dispatch
		if RadioManager.instance:
			RadioManager.instance.broadcast_dispatch(
				"[STATIC BURST] ...it's right outside the glass... DON'T LOOK AT IT... DRIVE...",
				6.0,
				true,
				0.85
			)

func _dismiss_threat() -> void:
	if threat_silhouette and threat_silhouette.visible:
		threat_silhouette.visible = false

func _complete_scavenge() -> void:
	is_depleted = true
	is_flare_active = false
	scavenge_time = 0.0

	if van_in_zone:
		# Ensure fuel gauge reaches 100% upon completion
		van_in_zone.add_fuel(van_in_zone.max_fuel)
		van_in_zone.repair_vehicle(health_repair_reward)

	if fuel_canister:
		fuel_canister.visible = false

	# Disable area to prevent repeated use
	if interaction_area:
		interaction_area.set_deferred("monitoring", false)

	if RadioManager.instance:
		RadioManager.instance.report_supply_stop_completed()

	var hud := _find_hud()
	if hud:
		hud.show_scavenge_success("[ VEHICLE REFUELED TO 100% | REPAIRS COMPLETE ]", 3.0)

	scavenge_completed.emit()

func _on_body_entered(body: Node3D) -> void:
	if body is Van:
		van_in_zone = body
		stopped_idle_time = 0.0
		threat_timer = 0.0
		threat_triggered = false
		if not is_depleted:
			var current_speed: float = van_in_zone.velocity.length() * 3.6
			if current_speed < max_scavenge_speed_kmh:
				_update_hud_prompt("[E] HOLD TO REFUEL", 0.0)
			else:
				_update_hud_prompt("[E] HOLD TO REFUEL (STOP VEHICLE < 5 KM/H)", 0.0)

func _on_body_exited(body: Node3D) -> void:
	if body == van_in_zone:
		van_in_zone = null
		scavenge_time = 0.0
		stopped_idle_time = 0.0
		threat_timer = 0.0
		_hide_hud_prompt()
		_dismiss_threat()

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
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			var mat := mi.material_override as BaseMaterial3D
			mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			mat.distance_fade_min_distance = 55.0
			mat.distance_fade_max_distance = 75.0
		if mi.mesh and mi.mesh.material is BaseMaterial3D:
			var mat := mi.mesh.material as BaseMaterial3D
			mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			mat.distance_fade_min_distance = 55.0
			mat.distance_fade_max_distance = 75.0
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.get_surface_override_material(i)
			if mat is BaseMaterial3D:
				var bmat := mat as BaseMaterial3D
				bmat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
				bmat.distance_fade_min_distance = 55.0
				bmat.distance_fade_max_distance = 75.0
	for child in node.get_children():
		_apply_distance_fade(child)
