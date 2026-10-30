class_name RoadEventSpawner
extends Node

const SupplyStopScene = preload("res://supply_stop.tscn")
const TrafficConeModel = preload("res://models/route77_traffic_cone.glb")
const BloodSplatterModel = preload("res://models/route77_blood_splatter.glb")
const GothicLamppostModel = preload("res://models/route77_gothic_lamppost.glb")
const RoadsideShrineModel = preload("res://models/route77_roadside_shrine.glb")
const GothicChapelModel = preload("res://models/route77_gothic_chapel.glb")
const GothicArchModel = preload("res://models/route77_gothic_arch.glb")
const DeadTreeModel = preload("res://models/route77_dead_tree.glb")
const HearseModel = preload("res://models/route77_hearse.glb")

@export_group("Obstacle Probabilities")
## Chance (0.0 to 1.0) to spawn a wrecked/crashed vehicle on a chunk.
@export var crashed_car_probability: float = 0.28
## Chance (0.0 to 1.0) to spawn a cluster of traffic cones / debris on a chunk.
@export var debris_probability: float = 0.30
## Chance (0.0 to 1.0) to spawn a broken-down vehicle with blinking hazards on the shoulder.
@export var shoulder_breakdown_probability: float = 0.32
## Accident stains are guaranteed on each fourth hazard segment.
@export var accident_stain_probability: float = 0.45

@export_group("Supply Stop Balancing")
## Maximum segments allowed without a supply stop (at least once every 8 segments).
@export var max_segments_without_supply_stop: int = 8
## Fuel percentage threshold below which a supply stop is guaranteed to spawn soon.
@export var emergency_fuel_threshold: float = 35.0

@export_group("Roadside Details")
## Chance (0.0 to 1.0) to spawn a Victorian wrought-iron gothic lamppost on a chunk.
@export var lamppost_probability: float = 0.72
## Chance (0.0 to 1.0) to spawn a Gothic roadside shrine (animita) on a chunk.
@export var shrine_probability: float = 0.65
## Starting kilometer marker descending toward 77.
@export var starting_kilometer: int = 85
## How many chunks between each kilometer marker milestone.
@export var chunks_per_milestone: int = 2
## Chance (0.0 to 1.0) to spawn a retro highway guide or hazard sign on a chunk.
@export var guide_sign_probability: float = 0.40

@export_group("Roadside Scenery")
## Chance (0.0 to 1.0) to spawn a distant Gothic ruined chapel in the woods.
@export var distant_cabin_probability: float = 0.38
## Enables continuous dense pine and twisted dead-tree forest along both road margins.
@export var enable_woods: bool = true

# Internal state
var current_kilometer: int = 85
var milestone_counter: int = 0
var chunks_since_supply_stop: int = 0

# Shared cached materials for performance
static var _rust_metal_mat: StandardMaterial3D
static var _tire_material: StandardMaterial3D
static var _hazard_orange_mat: StandardMaterial3D
static var _cone_white_mat: StandardMaterial3D
static var _wood_post_mat: StandardMaterial3D
static var _lantern_emission_mat: StandardMaterial3D
static var _milestone_concrete_mat: StandardMaterial3D
static var _milestone_red_mat: StandardMaterial3D
static var _tree_bark_mat: StandardMaterial3D
static var _tree_wind_shader: Shader
static var _tree_foliage_mat: ShaderMaterial
static var _grass_wind_shader: Shader
static var _grass_wind_mat: ShaderMaterial
static var _fern_mat: StandardMaterial3D
static var _wet_log_mat: StandardMaterial3D
static var _hazard_amber_blink_mat: StandardMaterial3D
static var _cabin_wall_mat: StandardMaterial3D
static var _cabin_roof_mat: StandardMaterial3D
static var _window_emission_mat: StandardMaterial3D
static var _blood_crimson_mat: StandardMaterial3D
static var _taillight_red_mat: StandardMaterial3D
static var _guide_sign_green_mat: StandardMaterial3D
static var _guide_sign_amber_mat: StandardMaterial3D
static var _guide_sign_white_mat: StandardMaterial3D
static var _forest_ground_mat: StandardMaterial3D
static var _hazard_advance_mat: StandardMaterial3D

func _ready() -> void:
	reset_spawner()

## Resets spawner milestone counters and roadside event intervals.
func reset_spawner() -> void:
	current_kilometer = starting_kilometer
	milestone_counter = 0
	chunks_since_supply_stop = 0

static func _get_blood_crimson_mat() -> StandardMaterial3D:
	if not _blood_crimson_mat:
		_blood_crimson_mat = StandardMaterial3D.new()
		# Deep coagulated crimson blood with slick wet specular sheen (#550508)
		_blood_crimson_mat.albedo_color = Color(0.38, 0.02, 0.03, 1.0)
		_blood_crimson_mat.roughness = 0.18
		_blood_crimson_mat.metallic = 0.08
	return _blood_crimson_mat

static func _get_forest_ground_mat() -> StandardMaterial3D:
	if not _forest_ground_mat:
		_forest_ground_mat = StandardMaterial3D.new()
		_forest_ground_mat.albedo_color = Color(0.055, 0.060, 0.058, 1.0)
		_forest_ground_mat.roughness = 0.98
		var ground_noise := FastNoiseLite.new()
		ground_noise.frequency = 0.11
		ground_noise.fractal_octaves = 3
		var ground_texture := NoiseTexture2D.new()
		ground_texture.width = 128
		ground_texture.height = 128
		ground_texture.seamless = true
		ground_texture.noise = ground_noise
		_forest_ground_mat.albedo_texture = ground_texture
		_forest_ground_mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	return _forest_ground_mat

static func _get_taillight_red_mat() -> StandardMaterial3D:
	if not _taillight_red_mat:
		_taillight_red_mat = StandardMaterial3D.new()
		_taillight_red_mat.albedo_color = Color(0.85, 0.05, 0.05, 1.0)
		_taillight_red_mat.emission_enabled = true
		_taillight_red_mat.emission = Color(0.9, 0.04, 0.02, 1.0)
		_taillight_red_mat.emission_energy_multiplier = 1.3
	return _taillight_red_mat

static func _apply_dither_fade(mat: StandardMaterial3D) -> StandardMaterial3D:
	if mat:
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	return mat

static func _get_rust_material() -> StandardMaterial3D:
	if not _rust_metal_mat:
		_rust_metal_mat = StandardMaterial3D.new()
		_rust_metal_mat.albedo_color = Color(0.20, 0.20, 0.20, 1.0) # Weathered monochrome metal
		_rust_metal_mat.roughness = 0.85
		_rust_metal_mat.metallic = 0.35
		_apply_dither_fade(_rust_metal_mat)
	return _rust_metal_mat

static func _get_tire_material() -> StandardMaterial3D:
	if not _tire_material:
		_tire_material = StandardMaterial3D.new()
		_tire_material.albedo_color = Color(0.025, 0.027, 0.03, 1.0)
		_tire_material.roughness = 0.97
	return _tire_material

static func _get_hazard_orange_mat() -> StandardMaterial3D:
	if not _hazard_orange_mat:
		_hazard_orange_mat = StandardMaterial3D.new()
		_hazard_orange_mat.albedo_color = Color(0.48, 0.48, 0.48, 1.0) # Weathered monochrome safety paint
		_hazard_orange_mat.roughness = 0.7
	return _hazard_orange_mat

static func _get_cone_white_mat() -> StandardMaterial3D:
	if not _cone_white_mat:
		_cone_white_mat = StandardMaterial3D.new()
		_cone_white_mat.albedo_color = Color(0.88, 0.88, 0.88, 1.0) # Reflective band
		_cone_white_mat.roughness = 0.6
	return _cone_white_mat

static func _get_wood_post_mat() -> StandardMaterial3D:
	if not _wood_post_mat:
		_wood_post_mat = StandardMaterial3D.new()
		_wood_post_mat.albedo_color = Color(0.16, 0.15, 0.14, 1.0) # Aged dark wood / iron
		_wood_post_mat.roughness = 0.9
		_apply_dither_fade(_wood_post_mat)
	return _wood_post_mat

static func _get_lantern_emission_mat() -> StandardMaterial3D:
	if not _lantern_emission_mat:
		_lantern_emission_mat = StandardMaterial3D.new()
		_lantern_emission_mat.albedo_color = Color(0.78, 0.78, 0.78, 1.0)
		_lantern_emission_mat.emission_enabled = true
		_lantern_emission_mat.emission = Color(0.78, 0.78, 0.78, 1.0)
		_lantern_emission_mat.emission_energy_multiplier = 2.0
		_apply_dither_fade(_lantern_emission_mat)
	return _lantern_emission_mat

static func _get_milestone_concrete_mat() -> StandardMaterial3D:
	if not _milestone_concrete_mat:
		_milestone_concrete_mat = StandardMaterial3D.new()
		_milestone_concrete_mat.albedo_color = Color(0.65, 0.64, 0.62, 1.0) # Concrete post
		_milestone_concrete_mat.roughness = 0.95
		_apply_dither_fade(_milestone_concrete_mat)
	return _milestone_concrete_mat

static func _get_milestone_red_mat() -> StandardMaterial3D:
	if not _milestone_red_mat:
		_milestone_red_mat = StandardMaterial3D.new()
		_milestone_red_mat.albedo_color = Color(0.72, 0.16, 0.14, 1.0) # Faded red cap
		_milestone_red_mat.roughness = 0.8
		_apply_dither_fade(_milestone_red_mat)
	return _milestone_red_mat

static func _get_tree_bark_mat() -> StandardMaterial3D:
	if not _tree_bark_mat:
		_tree_bark_mat = StandardMaterial3D.new()
		_tree_bark_mat.albedo_color = Color(0.12, 0.12, 0.12, 1.0) # Dark monochrome pine bark
		_tree_bark_mat.roughness = 0.95
	return _tree_bark_mat

static func _get_tree_foliage_mat() -> Material:
	if not _tree_foliage_mat:
		if not _tree_wind_shader:
			_tree_wind_shader = Shader.new()
			_tree_wind_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley;

uniform vec4 foliage_color : source_color = vec4(0.045, 0.045, 0.045, 1.0);
uniform float wind_speed = 1.6;
uniform float wind_amplitude = 0.07;

void vertex() {
	float h = max(0.0, VERTEX.y - 1.0);
	float wave = sin(TIME * wind_speed + NODE_POSITION_WORLD.x * 0.25 + VERTEX.y * 0.5) * wind_amplitude * h;
	VERTEX.x += wave;
	VERTEX.z += cos(TIME * wind_speed * 0.75 + NODE_POSITION_WORLD.z * 0.25 + VERTEX.y * 0.4) * (wind_amplitude * 0.75) * h;
}

void fragment() {
	ALBEDO = foliage_color.rgb;
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
}
"""
		_tree_foliage_mat = ShaderMaterial.new()
		_tree_foliage_mat.shader = _tree_wind_shader
	return _tree_foliage_mat

static func _get_grass_wind_mat() -> Material:
	if not _grass_wind_mat:
		if not _grass_wind_shader:
			_grass_wind_shader = Shader.new()
			_grass_wind_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform vec4 grass_color : source_color = vec4(0.065, 0.065, 0.065, 1.0);

void vertex() {
	float h = clamp(VERTEX.y, 0.0, 1.0);
	float sway = sin(TIME * 2.2 + NODE_POSITION_WORLD.x * 0.4) * 0.05 * h;
	VERTEX.x += sway;
}

void fragment() {
	ALBEDO = grass_color.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""
		_grass_wind_mat = ShaderMaterial.new()
		_grass_wind_mat.shader = _grass_wind_shader
	return _grass_wind_mat

static func _get_fern_mat() -> StandardMaterial3D:
	if not _fern_mat:
		_fern_mat = StandardMaterial3D.new()
		_fern_mat.albedo_color = Color(0.055, 0.055, 0.055, 1.0)
		_fern_mat.roughness = 0.88
	return _fern_mat

static func _get_wet_log_mat() -> StandardMaterial3D:
	if not _wet_log_mat:
		_wet_log_mat = StandardMaterial3D.new()
		_wet_log_mat.albedo_color = Color(0.12, 0.12, 0.12, 1.0)
		_wet_log_mat.roughness = 0.65
		_wet_log_mat.metallic = 0.05
	return _wet_log_mat

static func _get_hazard_amber_blink_mat() -> StandardMaterial3D:
	if not _hazard_amber_blink_mat:
		_hazard_amber_blink_mat = StandardMaterial3D.new()
		_hazard_amber_blink_mat.albedo_color = Color(0.78, 0.78, 0.78, 1.0)
		_hazard_amber_blink_mat.emission_enabled = true
		_hazard_amber_blink_mat.emission = Color(0.92, 0.92, 0.92, 1.0)
		_hazard_amber_blink_mat.emission_energy_multiplier = 4.0
	return _hazard_amber_blink_mat

static func _get_cabin_wall_mat() -> StandardMaterial3D:
	if not _cabin_wall_mat:
		_cabin_wall_mat = StandardMaterial3D.new()
		_cabin_wall_mat.albedo_color = Color(0.07, 0.07, 0.07, 1.0) # Distant dark log cabin
		_cabin_wall_mat.roughness = 0.95
		_apply_dither_fade(_cabin_wall_mat)
	return _cabin_wall_mat

static func _get_cabin_roof_mat() -> StandardMaterial3D:
	if not _cabin_roof_mat:
		_cabin_roof_mat = StandardMaterial3D.new()
		_cabin_roof_mat.albedo_color = Color(0.04, 0.04, 0.04, 1.0) # Dark pitched roof
		_cabin_roof_mat.roughness = 0.9
		_apply_dither_fade(_cabin_roof_mat)
	return _cabin_roof_mat

static func _get_window_emission_mat() -> StandardMaterial3D:
	if not _window_emission_mat:
		_window_emission_mat = StandardMaterial3D.new()
		_window_emission_mat.albedo_color = Color(0.72, 0.72, 0.72, 1.0)
		_window_emission_mat.emission_enabled = true
		_window_emission_mat.emission = Color(0.9, 0.9, 0.9, 1.0)
		_window_emission_mat.emission_energy_multiplier = 3.0
		_apply_dither_fade(_window_emission_mat)
	return _window_emission_mat

static func _get_guide_sign_green_mat() -> StandardMaterial3D:
	if not _guide_sign_green_mat:
		_guide_sign_green_mat = StandardMaterial3D.new()
		# Weathered rural highway dark green sign (#14442A)
		_guide_sign_green_mat.albedo_color = Color(0.12, 0.12, 0.12, 1.0)
		_guide_sign_green_mat.roughness = 0.55
		_guide_sign_green_mat.metallic = 0.15
		_apply_dither_fade(_guide_sign_green_mat)
	return _guide_sign_green_mat

static func _get_guide_sign_amber_mat() -> StandardMaterial3D:
	if not _guide_sign_amber_mat:
		_guide_sign_amber_mat = StandardMaterial3D.new()
		# Retro-reflective yellow hazard sign (#FFA000)
		_guide_sign_amber_mat.albedo_color = Color(0.72, 0.72, 0.72, 1.0)
		_guide_sign_amber_mat.roughness = 0.25
		_guide_sign_amber_mat.emission_enabled = true
		_guide_sign_amber_mat.emission = Color(0.86, 0.86, 0.86, 1.0)
		_guide_sign_amber_mat.emission_energy_multiplier = 0.6
		_apply_dither_fade(_guide_sign_amber_mat)
	return _guide_sign_amber_mat

static func _get_guide_sign_white_mat() -> StandardMaterial3D:
	if not _guide_sign_white_mat:
		_guide_sign_white_mat = StandardMaterial3D.new()
		# Retro-reflective white border and lettering
		_guide_sign_white_mat.albedo_color = Color(0.92, 0.92, 0.90, 1.0)
		_guide_sign_white_mat.roughness = 0.3
		_guide_sign_white_mat.emission_enabled = true
		_guide_sign_white_mat.emission = Color(0.85, 0.85, 0.85, 1.0)
		_guide_sign_white_mat.emission_energy_multiplier = 0.4
		_apply_dither_fade(_guide_sign_white_mat)
	return _guide_sign_white_mat

## Populates a newly spawned RoadSegment with obstacles, roadside props, and milestone markers.
func spawn_events_for_segment(segment: RoadSegment, chunk_index: int, rng: RandomNumberGenerator, has_supply_stop: bool = false) -> void:
	if not segment:
		return
	var slice_count := segment.get_slice_count()
	if slice_count < 3:
		return

	if has_supply_stop:
		chunks_since_supply_stop = 0
	else:
		chunks_since_supply_stop += 1
		var force_supply_stop := chunks_since_supply_stop >= max_segments_without_supply_stop or (_is_player_low_on_fuel() and chunks_since_supply_stop >= 2)
		if chunk_index >= 2 and force_supply_stop:
			_spawn_supply_stop_on_segment(segment)
			has_supply_stop = true
			chunks_since_supply_stop = 0

	# Road hazards appear on a predictable schedule so a normal drive reliably finds them.
	var occupied_slices: Array[int] = []
	if chunk_index >= 3 and not has_supply_stop and (chunk_index % 5 == 0 or rng.randf() < crashed_car_probability * 0.35):
		var wreck_slice := rng.randi_range(mini(3, slice_count - 2), slice_count - 2)
		occupied_slices.append(wreck_slice)
		_spawn_crashed_vehicle(segment, wreck_slice, rng)
		_spawn_hazard_advance_markers(segment, wreck_slice)
	if chunk_index >= 2 and not has_supply_stop and (chunk_index % 2 == 0 or rng.randf() < debris_probability):
		var debris_slice := rng.randi_range(mini(3, slice_count - 2), slice_count - 2)
		if not occupied_slices.has(debris_slice):
			occupied_slices.append(debris_slice)
			_spawn_debris_cluster(segment, debris_slice, rng)
			_spawn_hazard_advance_markers(segment, debris_slice)
	if chunk_index >= 4 and not has_supply_stop and (chunk_index % 4 == 0 or rng.randf() < accident_stain_probability):
		var stain_slice := rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(stain_slice):
			occupied_slices.append(stain_slice)
			_spawn_accident_stain(segment, stain_slice, rng)
	if chunk_index >= 3 and not has_supply_stop and rng.randf() < shoulder_breakdown_probability:
		var breakdown_slice := rng.randi_range(mini(3, slice_count - 2), slice_count - 2)
		if not occupied_slices.has(breakdown_slice):
			occupied_slices.append(breakdown_slice)
			_spawn_shoulder_breakdown(segment, breakdown_slice, rng)
			_spawn_hazard_advance_markers(segment, breakdown_slice)

	if rng.randf() < lamppost_probability:
		_spawn_lamppost(segment, rng.randi_range(0, slice_count - 1), rng)
	if not has_supply_stop and rng.randf() < shrine_probability:
		_spawn_roadside_shrine(segment, rng.randi_range(1, slice_count - 2), rng)
	if chunk_index >= 1 and not has_supply_stop and segment.segment_type == RoadSegment.SegmentType.STRAIGHT and (chunk_index % 3 == 1 or current_kilometer <= 79):
		_spawn_gothic_arch(segment, slice_count / 2)
	if chunk_index >= 2 and not has_supply_stop and rng.randf() < 0.45:
		var raven_slice := rng.randi_range(2, slice_count - 2)
		if not occupied_slices.has(raven_slice):
			occupied_slices.append(raven_slice)
			_spawn_raven_omen_flock(segment, raven_slice, rng)
	if current_kilometer <= 78 and not has_supply_stop:
		_spawn_ash_procession_hearses(segment, slice_count / 2)
	milestone_counter += 1
	if milestone_counter >= chunks_per_milestone and current_kilometer >= 77:
		milestone_counter = 0
		_spawn_milestone_marker(segment, slice_count / 2, current_kilometer)
		current_kilometer -= 1
	if enable_woods:
		_spawn_woods_for_segment(segment, rng)
	if rng.randf() < distant_cabin_probability:
		_spawn_distant_cabin(segment, rng.randi_range(1, slice_count - 2), rng)
	if not has_supply_stop and rng.randf() < guide_sign_probability:
		var sign_slice := rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(sign_slice):
			_spawn_highway_guide_sign(segment, sign_slice, rng)

## Spawns a cluster of red-eyed ravens on the asphalt that scatter when the player sounds the horn [X].
func _spawn_raven_omen_flock(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var flock := RavenFlockOmen.new()
	flock.name = "RavenFlockOmen_%d" % slice_idx
	var lane_x: float = 3.2 if rng.randf() < 0.68 else -3.2
	flock.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(lane_x, 0.5, 0.0))
	segment.add_child(flock)

## Spawns "La Procesión de Ceniza" (KM 78 -> 77): Gothic funeral hearses parked along both shoulders with crimson headlights.
func _spawn_ash_procession_hearses(segment: RoadSegment, slice_idx: int) -> void:
	if not HearseModel:
		return
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	for side_sign in [-1.0, 1.0]:
		var hearse_node := Node3D.new()
		hearse_node.name = "ProcessionHearse_%s_%d" % [("L" if side_sign < 0.0 else "R"), slice_idx]
		var model := HearseModel.instantiate()
		hearse_node.add_child(model)

		# Crimson-amber vigil headlights pointing slightly across the road
		var vigil_light := SpotLight3D.new()
		vigil_light.name = "VigilBeam"
		vigil_light.position = Vector3(0.0, 0.85, -2.5)
		vigil_light.light_color = Color(1.0, 0.24, 0.14, 1.0)
		vigil_light.light_energy = 9.5
		vigil_light.spot_range = 28.0
		vigil_light.spot_angle = 36.0
		hearse_node.add_child(vigil_light)

		var yaw := deg_to_rad(-18.0 * side_sign)
		var local_tr := Transform3D(Basis(Vector3.UP, yaw), Vector3(side_sign * 8.6, 0.5, 0.0))
		hearse_node.transform = slice_tr * local_tr
		segment.add_child(hearse_node)

## Places restrained amber reflectors about 30m before a lane hazard.
func _spawn_hazard_advance_markers(segment: RoadSegment, hazard_slice: int) -> void:
	if not segment or segment.get_slice_count() < 3:
		return
	if not _hazard_advance_mat:
		_hazard_advance_mat = StandardMaterial3D.new()
		_hazard_advance_mat.albedo_color = Color(0.72, 0.46, 0.12, 1.0)
		_hazard_advance_mat.roughness = 0.35
		_hazard_advance_mat.emission_enabled = true
		_hazard_advance_mat.emission = Color(0.95, 0.52, 0.12, 1.0)
		_hazard_advance_mat.emission_energy_multiplier = 0.9
	var marker_slice: int = maxi(0, hazard_slice - 3)
	var slice_tr := segment.get_slice_transform(marker_slice)
	for side in [-1.0, 1.0]:
		var marker := MeshInstance3D.new()
		marker.name = "HazardAdvanceReflector_%d" % marker_slice
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.22, 0.52, 0.08)
		mesh.material = _hazard_advance_mat
		marker.mesh = mesh
		marker.transform = Transform3D(slice_tr.basis, slice_tr.origin + slice_tr.basis * Vector3(side * 8.15, 1.0, 0.0))
		segment.add_child(marker)

## Spawns a SupplyStop beyond the right shoulder; its access lane leaves and rejoins the highway.
func _spawn_supply_stop_on_segment(segment: RoadSegment) -> void:
	var slice_count: int = segment.get_slice_count()
	if slice_count < 2:
		return
	var slice_idx: int = slice_count / 2
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	var stop_inst := SupplyStopScene.instantiate() as SupplyStop
	var local_offset := Vector3(12.5, 0.5, 0.0)
	stop_inst.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(stop_inst)

## Checks whether the player vehicle is below the emergency fuel threshold (< 35%).
func _is_player_low_on_fuel() -> bool:
	var tree := get_tree()
	if not tree:
		return false
	var vans := tree.get_nodes_in_group("player_van")
	if not vans.is_empty() and vans[0] is Van:
		return (vans[0] as Van).current_fuel <= emergency_fuel_threshold
	if tree.current_scene:
		var van_node := tree.current_scene.find_child("Van", true, false) as Van
		if van_node:
			return van_node.current_fuel <= emergency_fuel_threshold
	return false

# Reuse the same late-80s sedan mesh while allowing wreck-specific paint.
func _apply_sedan_body_material(node: Node, body_mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var lower_name := node.name.to_lower()
		if lower_name.contains("body shell") or lower_name.contains("underbody"):
			(node as MeshInstance3D).material_override = body_mat
	for child in node.get_children():
		_apply_sedan_body_material(child, body_mat)

## Spawns an abandoned/crashed car or Gothic hearse blocking one lane with heavy collision.
func _spawn_crashed_vehicle(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	# Pick either left lane (-3.5m) or right lane (+3.5m).
	var is_left_lane: bool = rng.randf() < 0.5
	var lateral_x: float = -3.5 if is_left_lane else 3.5
	lateral_x += rng.randf_range(-0.5, 0.5)

	var yaw_angle: float = rng.randf_range(deg_to_rad(20.0), deg_to_rad(45.0))
	if rng.randf() < 0.5:
		yaw_angle = -yaw_angle

	var wreck_body := StaticBody3D.new()
	wreck_body.name = "CrashedVehicle_%d" % slice_idx
	wreck_body.add_to_group("heavy_obstacle")
	wreck_body.collision_layer = 1
	wreck_body.collision_mask = 1

	var use_hearse: bool = rng.randf() < 0.48 and HearseModel != null
	if use_hearse:
		var hearse_visual := HearseModel.instantiate()
		wreck_body.add_child(hearse_visual)
	else:
		var sedan_scene := load("res://models/route77_sedan.glb") as PackedScene
		if sedan_scene:
			var sedan_visual := sedan_scene.instantiate()
			_apply_sedan_body_material(sedan_visual, _get_rust_material())
			wreck_body.add_child(sedan_visual)

	# Low-poly wheels remain visible beneath the body even when the car is tilted.
	var wheel_z_front := -1.35 if use_hearse else -1.28
	var wheel_z_rear := 1.55 if use_hearse else 1.28
	for wheel_pos in [Vector3(-1.02, 0.36, wheel_z_front), Vector3(1.02, 0.36, wheel_z_front), Vector3(-1.02, 0.36, wheel_z_rear), Vector3(1.02, 0.36, wheel_z_rear)]:
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.36
		wheel_mesh.bottom_radius = 0.36
		wheel_mesh.height = 0.25
		wheel_mesh.radial_segments = 8
		wheel_mesh.material = _get_tire_material()
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.rotation.z = PI * 0.5
		wheel.position = wheel_pos
		wreck_body.add_child(wheel)

	# Collision shape (BoxShape3D)
	var wreck_col := CollisionShape3D.new()
	var wreck_shape := BoxShape3D.new()
	wreck_shape.size = Vector3(2.2, 1.75, 4.9) if use_hearse else Vector3(2.2, 1.6, 4.4)
	wreck_col.shape = wreck_shape
	wreck_col.position = Vector3(0.0, 0.85, 0.0)
	wreck_body.add_child(wreck_col)

	# Rear taillights (dim broken crimson lights)
	var taillight_mesh := BoxMesh.new()
	taillight_mesh.size = Vector3(0.28, 0.16, 0.05)
	taillight_mesh.material = _get_taillight_red_mat()

	var tail_z := 2.58 if use_hearse else 2.16
	var left_tail := MeshInstance3D.new()
	left_tail.mesh = taillight_mesh
	left_tail.position = Vector3(-0.82, 0.75, tail_z)
	wreck_body.add_child(left_tail)

	var right_tail := MeshInstance3D.new()
	right_tail.mesh = taillight_mesh
	right_tail.position = Vector3(0.82, 0.75, tail_z)
	wreck_body.add_child(right_tail)

	# Place relative to slice transform (top of road is at Y = 0.5)
	var local_offset := Vector3(lateral_x, 0.5, 0.0)
	var local_basis := Basis(Vector3.UP, yaw_angle)
	wreck_body.transform = slice_tr * Transform3D(local_basis, local_offset)

	segment.add_child(wreck_body)

	# Crimson blood impact zone beneath crashed vehicle
	var blood_pool := BloodSplatterModel.instantiate() as Node3D
	blood_pool.name = "BloodPool"
	blood_pool.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(lateral_x, 0.51, 0.0))
	blood_pool.scale = Vector3(2.05, 1.0, 2.55)
	segment.add_child(blood_pool)

	# Irregular secondary blood splatter streak
	var blood_streak := BloodSplatterModel.instantiate() as Node3D
	blood_streak.name = "BloodDragMark"
	var streak_basis := Basis(Vector3.UP, rng.randf_range(-0.8, 0.8))
	blood_streak.transform = slice_tr * Transform3D(streak_basis, Vector3(lateral_x + rng.randf_range(-1.2, 1.2), 0.512, rng.randf_range(-1.5, 1.5)))
	blood_streak.scale = Vector3(0.8, 1.0, 1.35)
	segment.add_child(blood_streak)

	# Spawn a memorial Gothic shrine (animita) on the nearest verge beside the crash site
	_spawn_roadside_shrine(segment, slice_idx, rng, -1.0 if is_left_lane else 1.0)

## Spawns a cluster of physics-driven debris and traffic cones that scatter upon impact.
func _spawn_debris_cluster(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var cluster_count: int = rng.randi_range(3, 5)
	var base_x: float = rng.randf_range(-4.5, 4.5)

	for i in range(cluster_count):
		var offset_x: float = base_x + rng.randf_range(-1.2, 1.2)
		var offset_z: float = rng.randf_range(-2.0, 2.0)

		var rigid_body := RigidBody3D.new()
		rigid_body.name = "Debris_%d_%d" % [slice_idx, i]
		# Keep light props out of the van's physical collision mask; ImpactSensor moves them instead.
		rigid_body.collision_layer = 2
		rigid_body.collision_mask = 1
		# A hollow cone should tumble from a modest vehicle impact.
		rigid_body.mass = 0.75
		rigid_body.angular_damp = 2.0
		rigid_body.linear_damp = 1.0

		var col_shape := CollisionShape3D.new()
		# Low-poly tapered road cone with a separate reflective collar.
		var cone_shape := CylinderShape3D.new()
		cone_shape.radius = 0.20
		cone_shape.height = 0.68
		col_shape.shape = cone_shape
		col_shape.position = Vector3(0.0, 0.34, 0.0)
		rigid_body.add_child(col_shape)

		var cone_model := TrafficConeModel.instantiate() as Node3D
		cone_model.name = "BlenderTrafficCone"
		rigid_body.add_child(cone_model)

		var local_offset := Vector3(offset_x, 0.5, offset_z)
		rigid_body.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
		segment.add_child(rigid_body)

## Spawns a Victorian wrought-iron Gothic lamppost with a hanging lantern and flickering gaslight.
func _spawn_lamppost(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left_verge: bool = rng.randf() < 0.5
	var verge_x: float = -8.9 if on_left_verge else 8.9

	var lamppost_root := Node3D.new()
	lamppost_root.name = "GothicLamppost_%d" % slice_idx

	if GothicLamppostModel:
		var lamp_visual := GothicLamppostModel.instantiate() as Node3D
		lamp_visual.name = "BlenderGothicLamppost"
		# In Blender, the scroll arm extends toward +X. Rotate by PI on the right verge so it reaches -X over the road.
		if not on_left_verge:
			lamp_visual.rotation.y = PI
		lamppost_root.add_child(lamp_visual)

	# Solid physical collision for lamppost
	var post_body := StaticBody3D.new()
	post_body.name = "PostCollision"
	post_body.collision_layer = 1
	post_body.collision_mask = 1
	post_body.add_to_group("heavy_obstacle")

	var post_col := CollisionShape3D.new()
	var post_shape := BoxShape3D.new()
	post_shape.size = Vector3(0.45, 6.2, 0.45)
	post_col.shape = post_shape
	post_col.position = Vector3(0.0, 3.1, 0.0)
	post_body.add_child(post_col)
	lamppost_root.add_child(post_body)

	# OmniLight3D positioned at the hanging hexagonal lantern cage (X = ±1.12m, Y = 5.48m)
	var lantern_x: float = 1.12 if on_left_verge else -1.12
	var light := FlickerLight.new()
	light.name = "FlickerLight"
	light.position = Vector3(lantern_x, 5.48, 0.0)
	light.light_color = Color(0.96, 0.48, 0.18, 1.0) # Warm gaslight amber-crimson preserved by Gothic noir shader
	light.base_energy = 3.1
	light.omni_range = 17.5
	light.omni_attenuation = 1.25
	light.is_flickering = rng.randf() < 0.72
	lamppost_root.add_child(light)

	var local_offset := Vector3(verge_x, 0.25, 0.0)
	lamppost_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(lamppost_root)

## Spawns a Gothic roadside memorial shrine (Animita) with stone cross, iron pickets, and blood-red votive candles.
func _spawn_roadside_shrine(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator, side_override: float = 0.0) -> void:
	if not RoadsideShrineModel:
		return
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var side: float = side_override if absf(side_override) > 0.1 else (-1.0 if rng.randf() < 0.5 else 1.0)
	var verge_x: float = side * rng.randf_range(8.3, 9.2)

	var shrine_root := Node3D.new()
	shrine_root.name = "GothicShrine_%d" % slice_idx

	var shrine_visual := RoadsideShrineModel.instantiate() as Node3D
	shrine_visual.name = "BlenderRoadsideShrine"
	# Orient the shrine niche toward the road and oncoming headlights
	shrine_visual.rotation.y = deg_to_rad(55.0 if side < 0.0 else -55.0)
	shrine_root.add_child(shrine_visual)

	var shrine_body := StaticBody3D.new()
	shrine_body.name = "ShrineCollision"
	shrine_body.collision_layer = 1
	shrine_body.collision_mask = 1
	shrine_body.add_to_group("heavy_obstacle")
	var shrine_col := CollisionShape3D.new()
	var shrine_shape := BoxShape3D.new()
	shrine_shape.size = Vector3(1.3, 2.3, 1.1)
	shrine_col.shape = shrine_shape
	shrine_col.position = Vector3(0.0, 1.15, 0.0)
	shrine_body.add_child(shrine_col)
	shrine_root.add_child(shrine_body)

	# Flickering blood-crimson votive candle light
	var candle_light := FlickerLight.new()
	candle_light.name = "ShrineCandleLight"
	candle_light.position = Vector3(0.0, 0.65, 0.25)
	candle_light.light_color = Color(1.0, 0.22, 0.06, 1.0)
	candle_light.base_energy = 2.2
	candle_light.min_energy = 0.8
	candle_light.omni_range = 6.5
	candle_light.omni_attenuation = 1.4
	candle_light.is_flickering = true
	candle_light.subtle_flicker = true
	candle_light.flicker_probability = 0.65
	shrine_root.add_child(candle_light)

	shrine_root.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(verge_x, 0.35, 0.0))
	segment.add_child(shrine_root)

## Spawns a monumental Gothic stone archway spanning the highway with portcullis spikes and crimson lanterns.
func _spawn_gothic_arch(segment: RoadSegment, slice_idx: int) -> void:
	if not GothicArchModel:
		return
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var arch_root := Node3D.new()
	arch_root.name = "GothicHighwayArch_%d" % slice_idx

	var arch_visual := GothicArchModel.instantiate() as Node3D
	arch_visual.name = "BlenderGothicArch"
	arch_root.add_child(arch_visual)

	# Solid stone tower colliders on left and right verges (X = ±8.8m, leaving full 14m road + shoulders clear)
	var arch_body := StaticBody3D.new()
	arch_body.name = "ArchTowersCollision"
	arch_body.collision_layer = 1
	arch_body.collision_mask = 1
	arch_body.add_to_group("heavy_obstacle")
	for side in [-1.0, 1.0]:
		var tower_col := CollisionShape3D.new()
		var tower_shape := BoxShape3D.new()
		tower_shape.size = Vector3(2.5, 7.5, 3.2)
		tower_col.shape = tower_shape
		tower_col.position = Vector3(side * 8.8, 3.75, 0.0)
		arch_body.add_child(tower_col)

		# Crimson gate lantern OmniLight3D on inner face of each gatehouse pillar
		var gate_light := FlickerLight.new()
		gate_light.name = "ArchGateLight_%s" % ("L" if side < 0.0 else "R")
		gate_light.position = Vector3(side * 7.1, 4.85, 0.0)
		gate_light.light_color = Color(1.0, 0.16, 0.05, 1.0)
		gate_light.base_energy = 2.8
		gate_light.min_energy = 1.2
		gate_light.omni_range = 14.0
		gate_light.is_flickering = true
		gate_light.subtle_flicker = true
		arch_root.add_child(gate_light)

	arch_root.add_child(arch_body)
	arch_root.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0))
	segment.add_child(arch_root)

## Spawns a tall, slender dark vertical box standing silently on the shoulder.
func _spawn_milestone_marker(segment: RoadSegment, slice_idx: int, km_value: int) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var verge_x: float = 7.8 # Right shoulder milestone

	var marker_root := Node3D.new()
	marker_root.name = "MilestoneMarker_KM%d" % km_value

	# Concrete base post
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.5, 0.9, 0.35)
	base_mesh.material = _get_milestone_concrete_mat()

	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(0.0, 0.45, 0.0)
	marker_root.add_child(base_inst)

	# Red top stripe
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.52, 0.18, 0.37)
	cap_mesh.material = _get_milestone_red_mat()

	var cap_inst := MeshInstance3D.new()
	cap_inst.mesh = cap_mesh
	cap_inst.position = Vector3(0.0, 0.85, 0.0)
	marker_root.add_child(cap_inst)

	# Solid collision for concrete milestone
	var marker_body := StaticBody3D.new()
	marker_body.name = "MilestoneCollision"
	marker_body.collision_layer = 1
	marker_body.collision_mask = 1
	marker_body.add_to_group("heavy_obstacle")

	var marker_col := CollisionShape3D.new()
	var marker_shape := BoxShape3D.new()
	marker_shape.size = Vector3(0.55, 1.1, 0.4)
	marker_col.shape = marker_shape
	marker_col.position = Vector3(0.0, 0.55, 0.0)
	marker_body.add_child(marker_col)
	marker_root.add_child(marker_body)

	# Text label displaying "KM 77"
	var label := Label3D.new()
	label.name = "Label3D"
	label.text = "KM\n%d" % km_value
	label.font_size = 44
	label.outline_size = 6
	label.modulate = Color(0.12, 0.12, 0.12, 1.0)
	label.outline_modulate = Color(0.9, 0.9, 0.9, 1.0)
	label.position = Vector3(0.0, 0.45, -0.19) # Front face towards oncoming vehicles
	label.rotation.y = 0.0
	marker_root.add_child(label)

	var local_offset := Vector3(verge_x, 0.2, 0.0)
	marker_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(marker_root)

## Populates new road segments with vehicles, collision props, and roadside scenery.
func _spawn_woods_for_segment(segment: RoadSegment, rng: RandomNumberGenerator) -> void:
	var slice_count: int = segment.get_slice_count()
	var bark_mat := _get_tree_bark_mat()
	var foliage_mat := _get_tree_foliage_mat()
	var grass_mat := _get_grass_wind_mat()
	var fern_mat := _get_fern_mat()
	var log_mat := _get_wet_log_mat()

	for i in range(slice_count):
		var slice_tr: Transform3D = segment.get_slice_transform(i)

		# Close the exposed terrain beneath the treeline so leaving the shoulder cannot drop the van into infinity.
		var forest_ground_mat := _get_forest_ground_mat()
		for forest_side in [-1.0, 1.0]:
			var ground_body := StaticBody3D.new()
			ground_body.name = "ForestFloorCollision_%d_%s" % [i, "L" if forest_side < 0.0 else "R"]
			var ground_box := BoxShape3D.new()
			ground_box.size = Vector3(48.0, 0.8, segment.segment_length / float(slice_count) + 0.4)
			var ground_col := CollisionShape3D.new()
			ground_col.shape = ground_box
			ground_col.transform = Transform3D(Basis.IDENTITY, Vector3(forest_side * 36.0, -0.4, 0.0))
			ground_body.add_child(ground_col)
			var ground_mesh := BoxMesh.new()
			ground_mesh.size = ground_box.size
			ground_mesh.material = forest_ground_mat
			var ground_inst := MeshInstance3D.new()
			ground_inst.mesh = ground_mesh
			ground_inst.transform = ground_col.transform
			ground_body.add_child(ground_inst)
			ground_body.transform = slice_tr
			segment.add_child(ground_body)

			# Layer roots and thorn brush form a continuous boundary along the main road.
			var hedge_body := StaticBody3D.new()
			hedge_body.name = "RootHedgeCollision_%d_%s" % [i, "L" if forest_side < 0.0 else "R"]
			var hedge_collider := CollisionShape3D.new()
			var hedge_shape := BoxShape3D.new()
			hedge_shape.size = Vector3(2.2, 1.35, segment.segment_length / float(slice_count) + 0.4)
			hedge_collider.shape = hedge_shape
			hedge_collider.position = Vector3(forest_side * 12.6, 0.45, 0.0)
			hedge_body.add_child(hedge_collider)
			var root_mat := _get_tree_bark_mat()
			for root_i in range(3):
				var root_mesh := CylinderMesh.new()
				root_mesh.top_radius = 0.12
				root_mesh.bottom_radius = 0.24
				root_mesh.height = 2.5 + float(root_i) * 0.35
				root_mesh.material = root_mat
				var root_inst := MeshInstance3D.new()
				root_inst.mesh = root_mesh
				root_inst.position = Vector3(forest_side * (11.8 + float(root_i) * 0.55), 0.24, float(root_i - 1) * 2.1)
				root_inst.rotation.z = deg_to_rad(68.0 if forest_side > 0.0 else -68.0)
				hedge_body.add_child(root_inst)
			var hedge_mesh := SphereMesh.new()
			hedge_mesh.radial_segments = 6
			hedge_mesh.rings = 3
			hedge_mesh.height = 1.35
			hedge_mesh.radius = 0.85
			hedge_mesh.material = foliage_mat
			for bush_i in range(3):
				var bush_inst := MeshInstance3D.new()
				bush_inst.mesh = hedge_mesh
				bush_inst.position = Vector3(forest_side * 12.6, 0.54 + float(bush_i % 2) * 0.18, float(bush_i - 1) * 2.7)
				bush_inst.scale = Vector3(1.0, rng.randf_range(0.75, 1.0), rng.randf_range(1.2, 1.7))
				hedge_body.add_child(bush_inst)
			hedge_body.transform = slice_tr
			segment.add_child(hedge_body)

		# Layer 1: Near treeline (14.0m to 21.0m) - solid trunk collision
		var left_near: int = rng.randi_range(1, 2)
		var right_near: int = rng.randi_range(1, 2)
		for t in range(left_near):
			var stagger_x: float = rng.randf_range(-1.8, 1.8)
			var x_dist: float = rng.randf_range(-21.0, -14.0) + stagger_x
			var z_dist: float = rng.randf_range(-4.5, 4.5)
			_spawn_tree(segment, slice_tr, Vector3(x_dist, 0.0, z_dist), bark_mat, foliage_mat, rng, true, 6.5, 9.5)
		for t in range(right_near):
			var stagger_x: float = rng.randf_range(-1.8, 1.8)
			var x_dist: float = rng.randf_range(14.0, 21.0) + stagger_x
			var z_dist: float = rng.randf_range(-4.5, 4.5)
			_spawn_tree(segment, slice_tr, Vector3(x_dist, 0.0, z_dist), bark_mat, foliage_mat, rng, true, 6.5, 9.5)

		# Layer 2: Mid forest (21.0m to 29.0m) - solid trunk collision
		var left_mid: int = rng.randi_range(1, 2)
		var right_mid: int = rng.randi_range(1, 2)
		for t in range(left_mid):
			var stagger_x: float = rng.randf_range(-2.5, 2.5)
			var x_dist: float = rng.randf_range(-29.0, -21.0) + stagger_x
			var z_dist: float = rng.randf_range(-4.5, 4.5)
			_spawn_tree(segment, slice_tr, Vector3(x_dist, 0.0, z_dist), bark_mat, foliage_mat, rng, true, 8.0, 12.0)
		for t in range(right_mid):
			var stagger_x: float = rng.randf_range(-2.5, 2.5)
			var x_dist: float = rng.randf_range(21.0, 29.0) + stagger_x
			var z_dist: float = rng.randf_range(-4.5, 4.5)
			_spawn_tree(segment, slice_tr, Vector3(x_dist, 0.0, z_dist), bark_mat, foliage_mat, rng, true, 8.0, 12.0)

		# Layer 3: Deep backdrop tree line (29.0m to 44.0m), visible through the fog
		var left_deep: int = rng.randi_range(2, 3)
		var right_deep: int = rng.randi_range(2, 3)
		for t in range(left_deep):
			var stagger_x: float = rng.randf_range(-3.5, 3.5)
			var x_dist: float = rng.randf_range(-44.0, -29.0) + stagger_x
			var z_dist: float = rng.randf_range(-4.5, 4.5)
			_spawn_tree(segment, slice_tr, Vector3(x_dist, 0.0, z_dist), bark_mat, foliage_mat, rng, false, 11.0, 16.5)
		for t in range(right_deep):
			var stagger_x: float = rng.randf_range(-3.5, 3.5)
			var x_dist: float = rng.randf_range(29.0, 44.0) + stagger_x
			var z_dist: float = rng.randf_range(-4.5, 4.5)
			_spawn_tree(segment, slice_tr, Vector3(x_dist, 0.0, z_dist), bark_mat, foliage_mat, rng, false, 11.0, 16.5)

		# Undergrowth: roadside grass tufts along the verge and ditch banks
		var grass_count: int = rng.randi_range(2, 4)
		for g in range(grass_count):
			var g_left: bool = rng.randf() < 0.5
			var g_x: float = rng.randf_range(-13.5, -9.0) if g_left else rng.randf_range(9.0, 13.5)
			var g_z: float = rng.randf_range(-4.5, 4.5)

			var grass_root := Node3D.new()
			for blade_i in range(2):
				var blade := BoxMesh.new()
				blade.size = Vector3(0.42, 0.45, 0.02)
				blade.material = grass_mat
				var b_inst := MeshInstance3D.new()
				b_inst.mesh = blade
				b_inst.position = Vector3(0.0, 0.22, 0.0)
				b_inst.rotation.y = float(blade_i) * (PI * 0.5) + rng.randf_range(-0.3, 0.3)
				grass_root.add_child(b_inst)

			grass_root.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(g_x, 0.2, g_z))
			segment.add_child(grass_root)

		# Roadside ferns near ditch banks
		if rng.randf() < 0.45:
			var f_left: bool = rng.randf() < 0.5
			var f_x: float = rng.randf_range(-14.0, -10.5) if f_left else rng.randf_range(10.5, 14.0)
			var f_z: float = rng.randf_range(-4.0, 4.0)
			var fern_root := Node3D.new()
			for f_i in range(4):
				var f_angle: float = float(f_i) * (TAU / 4.0)
				var frond := PrismMesh.new()
				frond.size = Vector3(0.24, 0.55, 0.02)
				frond.material = fern_mat
				var frond_inst := MeshInstance3D.new()
				frond_inst.mesh = frond
				frond_inst.position = Vector3(sin(f_angle) * 0.25, 0.18, cos(f_angle) * 0.25)
				frond_inst.rotation.y = f_angle
				frond_inst.rotation.x = deg_to_rad(35.0)
				fern_root.add_child(frond_inst)

			fern_root.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(f_x, 0.15, f_z))
			segment.add_child(fern_root)

		# Fallen wet mossy logs along roadside perimeter
		if rng.randf() < 0.25:
			var l_left: bool = rng.randf() < 0.5
			var l_x: float = rng.randf_range(-18.0, -13.0) if l_left else rng.randf_range(13.0, 18.0)
			var l_z: float = rng.randf_range(-3.5, 3.5)
			var log_mesh := CylinderMesh.new()
			log_mesh.top_radius = rng.randf_range(0.20, 0.28)
			log_mesh.bottom_radius = log_mesh.top_radius * 1.15
			log_mesh.height = rng.randf_range(3.2, 4.8)
			log_mesh.material = log_mat
			var log_inst := MeshInstance3D.new()
			log_inst.mesh = log_mesh
			log_inst.position = Vector3(0.0, log_mesh.top_radius * 0.9, 0.0)
			log_inst.rotation.x = deg_to_rad(90.0)
			log_inst.rotation.y = rng.randf_range(-0.6, 0.6)

			var log_root := Node3D.new()
			log_root.add_child(log_inst)
			log_root.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(l_x, 0.1, l_z))
			segment.add_child(log_root)

## Helper to build either a gnarled Gothic dead tree with ravens or a dark conifer pine.
func _spawn_tree(segment: RoadSegment, slice_tr: Transform3D, local_offset: Vector3, bark_mat: StandardMaterial3D, foliage_mat: Material, rng: RandomNumberGenerator, has_collision: bool = true, min_h: float = 6.5, max_h: float = 9.5) -> void:
	var tree_root := Node3D.new()
	var height: float = rng.randf_range(min_h, max_h)
	var trunk_h: float = height * 0.42
	var use_gothic_dead_tree: bool = DeadTreeModel != null and rng.randf() < 0.38

	if use_gothic_dead_tree:
		var dead_visual := DeadTreeModel.instantiate() as Node3D
		dead_visual.name = "BlenderDeadTree"
		tree_root.add_child(dead_visual)
	else:
		# Trunk (CylinderMesh)
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.18
		trunk_mesh.bottom_radius = 0.35
		trunk_mesh.height = trunk_h
		trunk_mesh.material = bark_mat

		var trunk_inst := MeshInstance3D.new()
		trunk_inst.mesh = trunk_mesh
		trunk_inst.position = Vector3(0.0, trunk_h * 0.5, 0.0)
		trunk_inst.rotation.y = rng.randf_range(-PI, PI)
		tree_root.add_child(trunk_inst)

		# Exposed root swell wedges at the base spreading into ditch banks
		for r_i in range(3):
			var root_angle: float = float(r_i) * (TAU / 3.0) + rng.randf_range(-0.2, 0.2)
			var root_mesh := PrismMesh.new()
			root_mesh.size = Vector3(0.18, 0.35, 0.55)
			root_mesh.material = bark_mat
			var root_inst := MeshInstance3D.new()
			root_inst.mesh = root_mesh
			root_inst.position = Vector3(sin(root_angle) * 0.28, 0.15, cos(root_angle) * 0.28)
			root_inst.rotation.y = root_angle
			root_inst.rotation.x = deg_to_rad(20.0)
			tree_root.add_child(root_inst)

		# Composite Layered Conifer Canopy: 4 staggered intersecting conical tiers
		var base_r: float = rng.randf_range(1.6, 2.5) * (height / 8.0)
		var tier_count: int = 4
		var canopy_base_y: float = trunk_h * 0.70
		var tier_step: float = (height - canopy_base_y) / float(tier_count + 0.5)

		var tier_radii: Array[float] = [base_r, base_r * 0.78, base_r * 0.56, base_r * 0.34]
		var tier_heights: Array[float] = [tier_step * 1.5, tier_step * 1.35, tier_step * 1.2, tier_step * 1.1]

		for t_idx in range(tier_count):
			var tier_mesh := CylinderMesh.new()
			tier_mesh.top_radius = 0.0
			tier_mesh.bottom_radius = tier_radii[t_idx]
			tier_mesh.height = tier_heights[t_idx]
			tier_mesh.material = foliage_mat

			var tier_inst := MeshInstance3D.new()
			tier_inst.mesh = tier_mesh
			var tier_y: float = canopy_base_y + (float(t_idx) * tier_step) + (tier_heights[t_idx] * 0.45)
			tier_inst.position = Vector3(0.0, tier_y, 0.0)
			tier_inst.rotation.y = rng.randf_range(-PI, PI)
			tree_root.add_child(tier_inst)

	if has_collision:
		var tree_body := StaticBody3D.new()
		tree_body.name = "TreeCollision"
		tree_body.collision_layer = 1
		tree_body.collision_mask = 1
		tree_body.add_to_group("heavy_obstacle")

		var tree_col := CollisionShape3D.new()
		var tree_shape := CylinderShape3D.new()
		tree_shape.height = trunk_h
		tree_shape.radius = 0.38
		tree_col.shape = tree_shape
		tree_col.position = Vector3(0.0, trunk_h * 0.5, 0.0)
		tree_body.add_child(tree_col)
		tree_root.add_child(tree_body)

	# Random scale variation between 0.75x and 1.35x and random yaw orientation
	var scale_mult: float = rng.randf_range(0.75, 1.35)
	var yaw_rot: float = rng.randf_range(-PI, PI)
	var local_tr := Transform3D(Basis(Vector3.UP, yaw_rot).scaled(Vector3(scale_mult, scale_mult, scale_mult)), local_offset)
	tree_root.transform = slice_tr * local_tr
	segment.add_child(tree_root)

## Spawns a distant ruined Gothic chapel in the dark woods with glowing crimson stained-glass windows.
func _spawn_distant_cabin(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left: bool = rng.randf() < 0.5
	var distance_x: float = rng.randf_range(-34.0, -25.0) if on_left else rng.randf_range(25.0, 34.0)

	var chapel_root := Node3D.new()
	chapel_root.name = "DistantGothicChapel_%d" % slice_idx

	# Solid collision for chapel
	var chapel_body := StaticBody3D.new()
	chapel_body.name = "ChapelCollision"
	chapel_body.collision_layer = 1
	chapel_body.collision_mask = 1
	chapel_body.add_to_group("heavy_obstacle")

	var chapel_col := CollisionShape3D.new()
	var chapel_shape := BoxShape3D.new()
	chapel_shape.size = Vector3(6.2, 7.5, 7.6)
	chapel_col.shape = chapel_shape
	chapel_col.position = Vector3(0.0, 3.75, 0.0)
	chapel_body.add_child(chapel_col)
	chapel_root.add_child(chapel_body)

	if GothicChapelModel:
		var chapel_visual := GothicChapelModel.instantiate() as Node3D
		chapel_visual.name = "BlenderGothicChapel"
		# Angle the chapel facade slightly toward the highway and oncoming driver
		chapel_visual.rotation.y = deg_to_rad(35.0 if on_left else -35.0)
		chapel_root.add_child(chapel_visual)

	# Distant crimson-amber OmniLight3D emanating from the chapel's stained-glass lancets
	var light := OmniLight3D.new()
	var window_x: float = 2.2 if on_left else -2.2
	light.position = Vector3(window_x, 3.6, -2.5)
	light.light_color = Color(0.96, 0.22, 0.08, 1.0)
	light.light_energy = 2.8
	light.omni_range = 19.0
	light.omni_attenuation = 1.15
	chapel_root.add_child(light)

	var local_offset := Vector3(distance_x, 0.0, 0.0)
	chapel_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(chapel_root)

## Spawns a retro roadside highway guide sign or yellow hazard sign with Gothic route lore.
func _spawn_highway_guide_sign(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var verge_x: float = 8.6

	var sign_root := Node3D.new()
	sign_root.name = "GuideSign_%d" % slice_idx

	var is_green_route_sign: bool = rng.randf() < 0.65

	if is_green_route_sign:
		# Double dark wrought-iron support posts
		var post_mat := _get_wood_post_mat()
		for post_x in [-0.85, 0.85]:
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.14, 3.4, 0.14)
			post_mesh.material = post_mat
			var post_inst := MeshInstance3D.new()
			post_inst.mesh = post_mesh
			post_inst.position = Vector3(post_x, 1.7, 0.0)
			sign_root.add_child(post_inst)

		# Outer reflective border
		var border_mesh := BoxMesh.new()
		border_mesh.size = Vector3(2.64, 1.44, 0.06)
		border_mesh.material = _get_guide_sign_white_mat()
		var border_inst := MeshInstance3D.new()
		border_inst.mesh = border_mesh
		border_inst.position = Vector3(0.0, 2.5, 0.0)
		sign_root.add_child(border_inst)

		# Dark slate highway plate
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(2.52, 1.32, 0.08)
		plate_mesh.material = _get_guide_sign_green_mat()
		var plate_inst := MeshInstance3D.new()
		plate_inst.mesh = plate_mesh
		plate_inst.position = Vector3(0.0, 2.5, 0.02)
		sign_root.add_child(plate_inst)

		# Gothic highway text label (facing oncoming vehicles)
		var label := Label3D.new()
		label.name = "SignText"
		var sign_options: Array[String] = [
			"† RUTA NACIONAL 77 †\nKILÓMETRO %d\nNO SE DETENGA" % current_kilometer,
			"SANTUARIO KM 77\nPROCESIÓN EN LA NIEBLA\nNO MIRE ATRÁS",
			"VALLE DE LAS ÁNIMAS\nKM %d\nCONSERVE SU CARRIL" % current_kilometer,
			"† RUTA NACIONAL 77 †\nPARROQUIA ABANDONADA\nSIN RETORNO"
		]
		label.text = sign_options[rng.randi_range(0, sign_options.size() - 1)]
		label.font_size = 28
		label.outline_size = 4
		label.modulate = Color(0.96, 0.94, 0.90, 1.0)
		label.outline_modulate = Color(0.06, 0.05, 0.06, 1.0)
		label.position = Vector3(0.0, 2.5, 0.07)
		sign_root.add_child(label)
	else:
		# Single post hazard diamond sign
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.12, 2.8, 0.12)
		post_mesh.material = _get_wood_post_mat()
		var post_inst := MeshInstance3D.new()
		post_inst.mesh = post_mesh
		post_inst.position = Vector3(0.0, 1.4, 0.0)
		sign_root.add_child(post_inst)

		# Diamond backplate
		var diamond_mesh := BoxMesh.new()
		diamond_mesh.size = Vector3(1.1, 1.1, 0.06)
		diamond_mesh.material = _get_guide_sign_amber_mat()
		var diamond_inst := MeshInstance3D.new()
		diamond_inst.mesh = diamond_mesh
		diamond_inst.position = Vector3(0.0, 2.3, 0.02)
		diamond_inst.rotation.z = deg_to_rad(45.0)
		sign_root.add_child(diamond_inst)

		# Label with warning
		var label := Label3D.new()
		label.name = "HazardText"
		var hazard_options: Array[String] = [
			"† PELIGRO †\nCURVA",
			"NIEBLA\nSEPULCRAL",
			"CRUCE DE\nÁNIMAS",
			"NO MIRE\nEL ESPEJO"
		]
		label.text = hazard_options[rng.randi_range(0, hazard_options.size() - 1)]
		label.font_size = 26
		label.outline_size = 5
		label.modulate = Color(0.10, 0.08, 0.08, 1.0)
		label.outline_modulate = Color(0.88, 0.86, 0.84, 1.0)
		label.position = Vector3(0.0, 2.3, 0.06)
		sign_root.add_child(label)

	# Solid collision so vehicle cannot ghost through sign
	var sign_body := StaticBody3D.new()
	sign_body.name = "SignCollision"
	sign_body.collision_layer = 1
	sign_body.collision_mask = 1
	sign_body.add_to_group("heavy_obstacle")
	var sign_col := CollisionShape3D.new()
	var sign_shape := BoxShape3D.new()
	sign_shape.size = Vector3(2.6, 3.4, 0.4)
	sign_col.shape = sign_shape
	sign_col.position = Vector3(0.0, 1.7, 0.0)
	sign_body.add_child(sign_col)
	sign_root.add_child(sign_body)

	var local_offset := Vector3(verge_x, 0.2, 0.0)
	sign_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(sign_root)

## Spawns a broken-down vehicle or funeral hearse parked on the shoulder with hazard lights blinking.
func _spawn_shoulder_breakdown(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var shoulder_x: float = 7.9

	var car_root := StaticBody3D.new()
	car_root.name = "ShoulderBreakdown_%d" % slice_idx
	car_root.collision_layer = 1
	car_root.collision_mask = 1
	car_root.add_to_group("heavy_obstacle")

	var rust_mat := _get_rust_material()
	var hazard_mat := _get_hazard_amber_blink_mat()

	var use_hearse: bool = rng.randf() < 0.45 and HearseModel != null
	if use_hearse:
		var hearse_visual := HearseModel.instantiate()
		car_root.add_child(hearse_visual)
	else:
		var sedan_scene := load("res://models/route77_sedan.glb") as PackedScene
		if sedan_scene:
			var sedan_visual := sedan_scene.instantiate()
			_apply_sedan_body_material(sedan_visual, rust_mat)
			car_root.add_child(sedan_visual)

	# Open driver door exposed to the fog
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.12, 0.85, 1.1)
	door_mesh.material = rust_mat
	var door_inst := MeshInstance3D.new()
	door_inst.mesh = door_mesh
	door_inst.position = Vector3(-0.95, 0.85, 0.2)
	door_inst.rotation.y = deg_to_rad(-55.0)
	car_root.add_child(door_inst)

	# 4 dark tires
	var wheel_z_front := -1.35 if use_hearse else -1.2
	var wheel_z_rear := 1.55 if use_hearse else 1.2
	for wheel_pos in [Vector3(-0.95, 0.35, wheel_z_front), Vector3(0.95, 0.35, wheel_z_front), Vector3(-0.95, 0.35, wheel_z_rear), Vector3(0.95, 0.35, wheel_z_rear)]:
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.34
		wheel_mesh.bottom_radius = 0.34
		wheel_mesh.height = 0.24
		wheel_mesh.material = _get_tire_material()
		var wheel_inst := MeshInstance3D.new()
		wheel_inst.mesh = wheel_mesh
		wheel_inst.rotation.z = deg_to_rad(90.0)
		wheel_inst.position = wheel_pos
		car_root.add_child(wheel_inst)

	# Blinking amber hazard taillights
	var rear_z := 2.58 if use_hearse else 2.05
	for rear_x in [-0.82, 0.82]:
		var light_box := BoxMesh.new()
		light_box.size = Vector3(0.16, 0.12, 0.06)
		light_box.material = hazard_mat
		var l_inst := MeshInstance3D.new()
		l_inst.mesh = light_box
		l_inst.position = Vector3(rear_x, 0.65, rear_z)
		car_root.add_child(l_inst)

	# Pulsating amber-crimson hazard light casting glowing flares into the fog
	var hazard_light := FlickerLight.new()
	hazard_light.position = Vector3(0.0, 1.25, rear_z + 0.15)
	hazard_light.light_color = Color(0.95, 0.38, 0.12, 1.0)
	hazard_light.base_energy = 3.2
	hazard_light.min_energy = 0.2
	hazard_light.omni_range = 4.5
	hazard_light.flicker_probability = 0.8
	car_root.add_child(hazard_light)

	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(2.2, 1.6, 4.9) if use_hearse else Vector3(2.2, 1.4, 4.3)
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 0.75, 0.0)
	car_root.add_child(col)

	var yaw: float = rng.randf_range(deg_to_rad(-8.0), deg_to_rad(8.0))
	var local_tr := Transform3D(Basis(Vector3.UP, yaw), Vector3(shoulder_x, 0.0, 0.0))
	car_root.transform = slice_tr * local_tr
	segment.add_child(car_root)

## Spawns a flat accident stain with two tumbling cones; no body mesh is used.
func _spawn_accident_stain(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr := segment.get_slice_transform(slice_idx)
	var lane_x := rng.randf_range(-3.4, 3.4)
	var angle := rng.randf_range(-0.65, 0.65)
	var stain := BloodSplatterModel.instantiate() as Node3D
	stain.name = "AccidentBloodStain_%d" % slice_idx
	stain.transform = slice_tr * Transform3D(Basis(Vector3.UP, angle), Vector3(lane_x, 0.505, 0.0))
	stain.scale = Vector3(rng.randf_range(1.0, 1.8), 0.45, rng.randf_range(1.2, 2.1))
	segment.add_child(stain)
	# A few nearby cones and crate fragments make this read as a collision scene, without a body model.
	for i in range(2):
		var cone := RigidBody3D.new()
		cone.name = "AccidentCone_%d_%d" % [slice_idx, i]
		cone.mass = 0.75
		cone.collision_layer = 2
		cone.collision_mask = 1
		var cone_col := CollisionShape3D.new()
		var cone_shape := CylinderShape3D.new()
		cone_shape.radius = 0.18
		cone_shape.height = 0.62
		cone_col.shape = cone_shape
		cone_col.position.y = 0.31
		cone.add_child(cone_col)
		cone.add_child(TrafficConeModel.instantiate())
		var side := -1.0 if i == 0 else 1.0
		cone.transform = slice_tr * Transform3D(Basis(Vector3.UP, angle), Vector3(lane_x + side * 1.2, 0.5, rng.randf_range(-1.0, 1.0)))
		segment.add_child(cone)
