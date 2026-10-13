class_name RoadEventSpawner
extends Node

const SupplyStopScene = preload("res://supply_stop.tscn")
const HitchhikerScene = preload("res://hitchhiker.tscn")

@export_group("Obstacle Probabilities")
## Chance (0.0 to 1.0) to spawn a wrecked/crashed vehicle on a chunk.
@export var crashed_car_probability: float = 0.28
## Chance (0.0 to 1.0) to spawn a cluster of traffic cones / debris on a chunk.
@export var debris_probability: float = 0.30
## Chance (0.0 to 1.0) to spawn a broken-down vehicle with blinking hazards on the shoulder.
@export var shoulder_breakdown_probability: float = 0.32
## Chance (0.0 to 1.0) to spawn strange organic roadkill near the centerline requiring lane swerves.
@export var roadkill_probability: float = 0.25

@export_group("Supply Stop Balancing")
## Maximum segments allowed without a supply stop (at least once every 8 segments).
@export var max_segments_without_supply_stop: int = 8
## Fuel percentage threshold below which a supply stop is guaranteed to spawn soon.
@export var emergency_fuel_threshold: float = 35.0

@export_group("Roadside Anomalies Probabilities")
## Chance (0.0 to 1.0) to spawn a rustic lamppost on a chunk.
@export var lamppost_probability: float = 0.55
## Chance (0.0 to 1.0) to spawn a mysterious dark silhouette on a chunk.
@export var silhouette_probability: float = 0.35
## Starting kilometer marker descending toward 77.
@export var starting_kilometer: int = 85
## How many chunks between each kilometer marker milestone.
@export var chunks_per_milestone: int = 2
## Chance (0.0 to 1.0) to spawn a retro highway guide or hazard sign on a chunk.
@export var guide_sign_probability: float = 0.40

@export_group("Liminal Scenery Probabilities")
## Chance (0.0 to 1.0) to spawn a tracking roadside hitchhiker on the right verge.
@export var hitchhiker_probability: float = 0.45
## Chance (0.0 to 1.0) to spawn a rustic bus stop shelter.
@export var bus_stop_probability: float = 0.40
## Chance (0.0 to 1.0) to spawn a distant cabin with an unreachable glowing window.
@export var distant_cabin_probability: float = 0.25
## Enables continuous dense pine treeline along both road margins.
@export var enable_woods: bool = true

# Internal state
var current_kilometer: int = 85
var milestone_counter: int = 0
var chunks_since_roadside_event: int = 0
var chunks_since_supply_stop: int = 0

# Shared cached materials for performance
static var _rust_metal_mat: StandardMaterial3D
static var _cabin_glass_mat: StandardMaterial3D
static var _hazard_orange_mat: StandardMaterial3D
static var _cone_white_mat: StandardMaterial3D
static var _rubble_mat: StandardMaterial3D
static var _wood_post_mat: StandardMaterial3D
static var _lantern_emission_mat: StandardMaterial3D
static var _silhouette_mat: StandardMaterial3D
static var _milestone_concrete_mat: StandardMaterial3D
static var _milestone_red_mat: StandardMaterial3D
static var _tree_bark_mat: StandardMaterial3D
static var _tree_wind_shader: Shader
static var _tree_foliage_mat: ShaderMaterial
static var _grass_wind_shader: Shader
static var _grass_wind_mat: ShaderMaterial
static var _fern_mat: StandardMaterial3D
static var _wet_log_mat: StandardMaterial3D
static var _organic_flesh_mat: StandardMaterial3D
static var _hazard_amber_blink_mat: StandardMaterial3D
static var _bus_stop_mat: StandardMaterial3D
static var _bus_stop_wood_mat: StandardMaterial3D
static var _cabin_wall_mat: StandardMaterial3D
static var _cabin_roof_mat: StandardMaterial3D
static var _window_emission_mat: StandardMaterial3D
static var _blood_crimson_mat: StandardMaterial3D
static var _taillight_red_mat: StandardMaterial3D
static var _guide_sign_green_mat: StandardMaterial3D
static var _guide_sign_amber_mat: StandardMaterial3D
static var _guide_sign_white_mat: StandardMaterial3D

func _ready() -> void:
	reset_spawner()

## Resets spawner milestone counters and roadside event intervals.
func reset_spawner() -> void:
	current_kilometer = starting_kilometer
	milestone_counter = 0
	chunks_since_roadside_event = 0
	chunks_since_supply_stop = 0

static func _get_blood_crimson_mat() -> StandardMaterial3D:
	if not _blood_crimson_mat:
		_blood_crimson_mat = StandardMaterial3D.new()
		# Deep coagulated crimson blood with slick wet specular sheen (#550508)
		_blood_crimson_mat.albedo_color = Color(0.38, 0.02, 0.03, 1.0)
		_blood_crimson_mat.roughness = 0.18
		_blood_crimson_mat.metallic = 0.08
	return _blood_crimson_mat

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
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		mat.distance_fade_min_distance = 55.0
		mat.distance_fade_max_distance = 75.0
	return mat

static func _get_rust_material() -> StandardMaterial3D:
	if not _rust_metal_mat:
		_rust_metal_mat = StandardMaterial3D.new()
		_rust_metal_mat.albedo_color = Color(0.24, 0.16, 0.13, 1.0) # Corroded metal
		_rust_metal_mat.roughness = 0.85
		_rust_metal_mat.metallic = 0.35
		_apply_dither_fade(_rust_metal_mat)
	return _rust_metal_mat

static func _get_cabin_glass_mat() -> StandardMaterial3D:
	if not _cabin_glass_mat:
		_cabin_glass_mat = StandardMaterial3D.new()
		_cabin_glass_mat.albedo_color = Color(0.1, 0.12, 0.14, 1.0) # Shattered dark glass
		_cabin_glass_mat.roughness = 0.5
		_cabin_glass_mat.metallic = 0.2
		_apply_dither_fade(_cabin_glass_mat)
	return _cabin_glass_mat

static func _get_hazard_orange_mat() -> StandardMaterial3D:
	if not _hazard_orange_mat:
		_hazard_orange_mat = StandardMaterial3D.new()
		_hazard_orange_mat.albedo_color = Color(0.85, 0.35, 0.08, 1.0) # Weathered safety orange
		_hazard_orange_mat.roughness = 0.7
	return _hazard_orange_mat

static func _get_cone_white_mat() -> StandardMaterial3D:
	if not _cone_white_mat:
		_cone_white_mat = StandardMaterial3D.new()
		_cone_white_mat.albedo_color = Color(0.88, 0.88, 0.85, 1.0) # Reflective band
		_cone_white_mat.roughness = 0.6
	return _cone_white_mat

static func _get_rubble_mat() -> StandardMaterial3D:
	if not _rubble_mat:
		_rubble_mat = StandardMaterial3D.new()
		_rubble_mat.albedo_color = Color(0.18, 0.17, 0.16, 1.0) # Broken asphalt / concrete
		_rubble_mat.roughness = 0.95
	return _rubble_mat

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
		_lantern_emission_mat.albedo_color = Color(1.0, 0.82, 0.45, 1.0)
		_lantern_emission_mat.emission_enabled = true
		_lantern_emission_mat.emission = Color(1.0, 0.82, 0.45, 1.0)
		_lantern_emission_mat.emission_energy_multiplier = 2.0
		_apply_dither_fade(_lantern_emission_mat)
	return _lantern_emission_mat

static func _get_silhouette_mat() -> StandardMaterial3D:
	if not _silhouette_mat:
		_silhouette_mat = StandardMaterial3D.new()
		_silhouette_mat.albedo_color = Color(0.015, 0.015, 0.015, 1.0) # Pitch shadow
		_silhouette_mat.roughness = 1.0
		_silhouette_mat.metallic = 0.0
	return _silhouette_mat

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
		_tree_bark_mat.albedo_color = Color(0.12, 0.1, 0.08, 1.0) # Dark forest pine bark
		_tree_bark_mat.roughness = 0.95
	return _tree_bark_mat

static func _get_tree_foliage_mat() -> Material:
	if not _tree_foliage_mat:
		if not _tree_wind_shader:
			_tree_wind_shader = Shader.new()
			_tree_wind_shader.code = """
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley;

uniform vec4 foliage_color : source_color = vec4(0.032, 0.058, 0.038, 1.0);
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

uniform vec4 grass_color : source_color = vec4(0.05, 0.085, 0.045, 1.0);

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
		_fern_mat.albedo_color = Color(0.04, 0.075, 0.035, 1.0)
		_fern_mat.roughness = 0.88
	return _fern_mat

static func _get_wet_log_mat() -> StandardMaterial3D:
	if not _wet_log_mat:
		_wet_log_mat = StandardMaterial3D.new()
		_wet_log_mat.albedo_color = Color(0.14, 0.11, 0.08, 1.0)
		_wet_log_mat.roughness = 0.65
		_wet_log_mat.metallic = 0.05
	return _wet_log_mat

static func _get_organic_flesh_mat() -> StandardMaterial3D:
	if not _organic_flesh_mat:
		_organic_flesh_mat = StandardMaterial3D.new()
		_organic_flesh_mat.albedo_color = Color(0.25, 0.04, 0.05, 1.0)
		_organic_flesh_mat.roughness = 0.25
		_organic_flesh_mat.metallic = 0.1
	return _organic_flesh_mat

static func _get_hazard_amber_blink_mat() -> StandardMaterial3D:
	if not _hazard_amber_blink_mat:
		_hazard_amber_blink_mat = StandardMaterial3D.new()
		_hazard_amber_blink_mat.albedo_color = Color(1.0, 0.55, 0.05, 1.0)
		_hazard_amber_blink_mat.emission_enabled = true
		_hazard_amber_blink_mat.emission = Color(1.0, 0.5, 0.02, 1.0)
		_hazard_amber_blink_mat.emission_energy_multiplier = 4.0
	return _hazard_amber_blink_mat

static func _get_bus_stop_mat() -> StandardMaterial3D:
	if not _bus_stop_mat:
		_bus_stop_mat = StandardMaterial3D.new()
		_bus_stop_mat.albedo_color = Color(0.35, 0.38, 0.36, 1.0) # Weathered rural concrete
		_bus_stop_mat.roughness = 0.95
		_apply_dither_fade(_bus_stop_mat)
	return _bus_stop_mat

static func _get_bus_stop_wood_mat() -> StandardMaterial3D:
	if not _bus_stop_wood_mat:
		_bus_stop_wood_mat = StandardMaterial3D.new()
		_bus_stop_wood_mat.albedo_color = Color(0.2, 0.16, 0.12, 1.0) # Aged dark bench wood
		_bus_stop_wood_mat.roughness = 0.9
		_apply_dither_fade(_bus_stop_wood_mat)
	return _bus_stop_wood_mat

static func _get_cabin_wall_mat() -> StandardMaterial3D:
	if not _cabin_wall_mat:
		_cabin_wall_mat = StandardMaterial3D.new()
		_cabin_wall_mat.albedo_color = Color(0.08, 0.07, 0.06, 1.0) # Distant dark log cabin
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
		_window_emission_mat.albedo_color = Color(1.0, 0.82, 0.35, 1.0)
		_window_emission_mat.emission_enabled = true
		_window_emission_mat.emission = Color(1.0, 0.8, 0.3, 1.0)
		_window_emission_mat.emission_energy_multiplier = 3.0
		_apply_dither_fade(_window_emission_mat)
	return _window_emission_mat

static func _get_guide_sign_green_mat() -> StandardMaterial3D:
	if not _guide_sign_green_mat:
		_guide_sign_green_mat = StandardMaterial3D.new()
		# Weathered rural highway dark green sign (#14442A)
		_guide_sign_green_mat.albedo_color = Color(0.08, 0.28, 0.16, 1.0)
		_guide_sign_green_mat.roughness = 0.55
		_guide_sign_green_mat.metallic = 0.15
		_apply_dither_fade(_guide_sign_green_mat)
	return _guide_sign_green_mat

static func _get_guide_sign_amber_mat() -> StandardMaterial3D:
	if not _guide_sign_amber_mat:
		_guide_sign_amber_mat = StandardMaterial3D.new()
		# Retro-reflective yellow hazard sign (#FFA000)
		_guide_sign_amber_mat.albedo_color = Color(1.0, 0.65, 0.02, 1.0)
		_guide_sign_amber_mat.roughness = 0.25
		_guide_sign_amber_mat.emission_enabled = true
		_guide_sign_amber_mat.emission = Color(1.0, 0.6, 0.02, 1.0)
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

	var slice_count: int = segment.get_slice_count()
	if slice_count < 3:
		return

	# Supply Stop Pacing Guarantee: spawn at least once every max_segments_without_supply_stop (8) segments,
	# or immediately (within 2 chunks) if player fuel drops below emergency_fuel_threshold (35%).
	if has_supply_stop:
		chunks_since_supply_stop = 0
	else:
		chunks_since_supply_stop += 1
		var force_supply_stop: bool = (chunks_since_supply_stop >= max_segments_without_supply_stop) or (_is_player_low_on_fuel() and chunks_since_supply_stop >= 2)
		if chunk_index >= 2 and force_supply_stop:
			_spawn_supply_stop_on_segment(segment)
			has_supply_stop = true
			chunks_since_supply_stop = 0

	# Don't spawn hazardous obstacles on the initial runway or on chunks with a supply stop
	var allow_obstacles: bool = chunk_index > 2 and not has_supply_stop

	# Track occupied slices to avoid overlapping obstacles
	var occupied_slices: Array[int] = []

	# 1. Abandoned / Crashed Vehicle Obstacle
	if allow_obstacles and rng.randf() < crashed_car_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		occupied_slices.append(slice_idx)
		_spawn_crashed_vehicle(segment, slice_idx, rng)

	# 2. Debris / Traffic Cones & Barrels
	if allow_obstacles and rng.randf() < debris_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(slice_idx):
			occupied_slices.append(slice_idx)
			_spawn_debris_cluster(segment, slice_idx, rng)

	# 2b. Broken-down vehicle parked on shoulder with hazard lights blinking
	if not has_supply_stop and rng.randf() < shoulder_breakdown_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(slice_idx):
			occupied_slices.append(slice_idx)
			_spawn_shoulder_breakdown(segment, slice_idx, rng)

	# 2c. Roadkill or strange organic obstruction near centerline requiring lane swerves
	if allow_obstacles and rng.randf() < roadkill_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(slice_idx):
			occupied_slices.append(slice_idx)
			_spawn_roadkill_obstruction(segment, slice_idx, rng)

	# 3. Rustic Lampposts with Erratic Flicker
	if rng.randf() < lamppost_probability:
		var slice_idx: int = rng.randi_range(0, slice_count - 1)
		_spawn_lamppost(segment, slice_idx, rng)

	# 4. Mysterious Roadside Silhouettes
	if rng.randf() < silhouette_probability:
		var slice_idx: int = rng.randi_range(0, slice_count - 1)
		_spawn_silhouette(segment, slice_idx, rng)

	# 5. Milestone Marker (Countdown toward Kilómetro 77)
	milestone_counter += 1
	if milestone_counter >= chunks_per_milestone and current_kilometer >= 77:
		milestone_counter = 0
		var slice_idx: int = slice_count / 2
		_spawn_milestone_marker(segment, slice_idx, current_kilometer)
		current_kilometer -= 1

	# 6. Continuous dense pine woods treeline along outer margins
	if enable_woods:
		_spawn_woods_for_segment(segment, rng)

	# 7. Roadside Hitchhiker with vehicle tracking rotation
	var has_roadside_event: bool = false
	if not has_supply_stop and rng.randf() < hitchhiker_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		_spawn_hitchhiker(segment, slice_idx, rng)
		has_roadside_event = true

	# 8. Rural Bus Stop Shelter with optional silhouette and sickly bulb
	if not has_supply_stop and rng.randf() < bus_stop_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		_spawn_bus_stop(segment, slice_idx, rng)
		has_roadside_event = true

	# Pacing Guarantee: ensure at least one roadside event (supply stop, hitchhiker, bus stop) every 3-4 chunks
	if has_supply_stop or has_roadside_event:
		chunks_since_roadside_event = 0
	else:
		chunks_since_roadside_event += 1
		if chunks_since_roadside_event >= 3 and chunk_index > 1:
			chunks_since_roadside_event = 0
			var slice_idx: int = rng.randi_range(1, slice_count - 2)
			if rng.randf() < 0.5:
				_spawn_hitchhiker(segment, slice_idx, rng)
			else:
				_spawn_bus_stop(segment, slice_idx, rng)

	# 9. Distant Unreachable Cabin Window Light in the dark woods
	if rng.randf() < distant_cabin_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		_spawn_distant_cabin(segment, slice_idx, rng)

	# 10. Retro Highway Guide Signs ("RUTA NACIONAL 77" & Hazard Markers)
	if not has_supply_stop and rng.randf() < guide_sign_probability:
		var slice_idx: int = rng.randi_range(1, slice_count - 2)
		if not occupied_slices.has(slice_idx):
			occupied_slices.append(slice_idx)
			_spawn_highway_guide_sign(segment, slice_idx, rng)

## Spawns a SupplyStop instance on the right shoulder of the given segment.
func _spawn_supply_stop_on_segment(segment: RoadSegment) -> void:
	var slice_count: int = segment.get_slice_count()
	if slice_count < 2:
		return
	var slice_idx: int = slice_count / 2
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	var stop_inst := SupplyStopScene.instantiate() as SupplyStop
	var local_offset := Vector3(7.8, 0.5, 0.0)
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

## Spawns an abandoned/crashed car blocking one lane with heavy collision.
func _spawn_crashed_vehicle(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)

	# Pick either left lane (-3.5m) or right lane (+3.5m).
	# With 14m road width, this centers the obstruction in the chosen lane.
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

	# Chassis mesh (BoxMesh)
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(2.2, 1.3, 4.3)
	chassis_mesh.material = _get_rust_material()

	var chassis_inst := MeshInstance3D.new()
	chassis_inst.mesh = chassis_mesh
	chassis_inst.position = Vector3(0.0, 0.65, 0.0)
	wreck_body.add_child(chassis_inst)

	# Cabin roof mesh (BoxMesh)
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.9, 0.8, 2.3)
	cabin_mesh.material = _get_cabin_glass_mat()

	var cabin_inst := MeshInstance3D.new()
	cabin_inst.mesh = cabin_mesh
	cabin_inst.position = Vector3(0.0, 1.6, -0.2)
	wreck_body.add_child(cabin_inst)

	# Collision shape (BoxShape3D)
	var wreck_col := CollisionShape3D.new()
	var wreck_shape := BoxShape3D.new()
	wreck_shape.size = Vector3(2.2, 1.6, 4.4)
	wreck_col.shape = wreck_shape
	wreck_col.position = Vector3(0.0, 0.8, 0.0)
	wreck_body.add_child(wreck_col)

	# Rear taillights (dim broken crimson lights)
	var taillight_mesh := BoxMesh.new()
	taillight_mesh.size = Vector3(0.28, 0.16, 0.05)
	taillight_mesh.material = _get_taillight_red_mat()

	var left_tail := MeshInstance3D.new()
	left_tail.mesh = taillight_mesh
	left_tail.position = Vector3(-0.85, 0.7, 2.16)
	wreck_body.add_child(left_tail)

	var right_tail := MeshInstance3D.new()
	right_tail.mesh = taillight_mesh
	right_tail.position = Vector3(0.85, 0.7, 2.16)
	wreck_body.add_child(right_tail)

	# Place relative to slice transform (top of road is at Y = 0.5)
	var local_offset := Vector3(lateral_x, 0.5, 0.0)
	var local_basis := Basis(Vector3.UP, yaw_angle)
	wreck_body.transform = slice_tr * Transform3D(local_basis, local_offset)

	segment.add_child(wreck_body)

	# Crimson blood impact zone beneath crashed vehicle
	var blood_pool := MeshInstance3D.new()
	var blood_mesh := BoxMesh.new()
	blood_mesh.size = Vector3(3.4, 0.015, 4.8)
	blood_mesh.material = _get_blood_crimson_mat()
	blood_pool.mesh = blood_mesh
	blood_pool.transform = slice_tr * Transform3D(Basis.IDENTITY, Vector3(lateral_x, 0.51, 0.0))
	segment.add_child(blood_pool)

	# Irregular secondary blood splatter streak
	var blood_streak := MeshInstance3D.new()
	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(1.6, 0.015, 2.8)
	streak_mesh.material = _get_blood_crimson_mat()
	blood_streak.mesh = streak_mesh
	var streak_basis := Basis(Vector3.UP, rng.randf_range(-0.8, 0.8))
	blood_streak.transform = slice_tr * Transform3D(streak_basis, Vector3(lateral_x + rng.randf_range(-1.2, 1.2), 0.512, rng.randf_range(-1.5, 1.5)))
	segment.add_child(blood_streak)

## Spawns a cluster of physics-driven debris and traffic cones that scatter upon impact.
func _spawn_debris_cluster(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var cluster_count: int = rng.randi_range(2, 4)
	var base_x: float = rng.randf_range(-4.5, 4.5)

	for i in range(cluster_count):
		var item_type := rng.randi_range(0, 1) # 0 = Traffic Cone, 1 = Debris Crate
		var offset_x: float = base_x + rng.randf_range(-1.2, 1.2)
		var offset_z: float = rng.randf_range(-2.0, 2.0)

		var rigid_body := RigidBody3D.new()
		rigid_body.name = "Debris_%d_%d" % [slice_idx, i]
		rigid_body.collision_layer = 1
		rigid_body.collision_mask = 1
		rigid_body.mass = 8.0 if item_type == 0 else 14.0
		rigid_body.angular_damp = 2.0
		rigid_body.linear_damp = 1.0

		var col_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()

		if item_type == 0:
			# Traffic Cone (Box primitive base with white band)
			box_shape.size = Vector3(0.55, 0.75, 0.55)
			col_shape.shape = box_shape
			col_shape.position = Vector3(0.0, 0.375, 0.0)
			rigid_body.add_child(col_shape)

			var cone_mesh := BoxMesh.new()
			cone_mesh.size = Vector3(0.55, 0.75, 0.55)
			cone_mesh.material = _get_hazard_orange_mat()

			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = cone_mesh
			mesh_inst.position = Vector3(0.0, 0.375, 0.0)
			rigid_body.add_child(mesh_inst)

			var stripe_mesh := BoxMesh.new()
			stripe_mesh.size = Vector3(0.57, 0.18, 0.57)
			stripe_mesh.material = _get_cone_white_mat()

			var stripe_inst := MeshInstance3D.new()
			stripe_inst.mesh = stripe_mesh
			stripe_inst.position = Vector3(0.0, 0.45, 0.0)
			rigid_body.add_child(stripe_inst)
		else:
			# Debris Block / Rubble
			var size := Vector3(rng.randf_range(0.5, 0.8), rng.randf_range(0.4, 0.6), rng.randf_range(0.5, 0.8))
			box_shape.size = size
			col_shape.shape = box_shape
			col_shape.position = Vector3(0.0, size.y * 0.5, 0.0)
			rigid_body.add_child(col_shape)

			var debris_mesh := BoxMesh.new()
			debris_mesh.size = size
			debris_mesh.material = _get_rubble_mat()

			var mesh_inst := MeshInstance3D.new()
			mesh_inst.mesh = debris_mesh
			mesh_inst.position = Vector3(0.0, size.y * 0.5, 0.0)
			rigid_body.add_child(mesh_inst)

		var local_offset := Vector3(offset_x, 0.5, offset_z)
		rigid_body.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
		segment.add_child(rigid_body)

## Spawns a tall rustic lamppost with an eerie OmniLight3D and flicker logic.
func _spawn_lamppost(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left_verge: bool = rng.randf() < 0.5
	# Place just outside the guardrail (guardrail inner is 8.0m, thickness 1.0m, post at 8.9m)
	var verge_x: float = -8.9 if on_left_verge else 8.9

	var lamppost_root := Node3D.new()
	lamppost_root.name = "Lamppost_%d" % slice_idx

	# Vertical timber/iron post
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.3, 5.8, 0.3)
	post_mesh.material = _get_wood_post_mat()

	var post_inst := MeshInstance3D.new()
	post_inst.mesh = post_mesh
	post_inst.position = Vector3(0.0, 2.9, 0.0)
	lamppost_root.add_child(post_inst)

	# Solid physical collision for lamppost
	var post_body := StaticBody3D.new()
	post_body.name = "PostCollision"
	post_body.collision_layer = 1
	post_body.collision_mask = 1
	post_body.add_to_group("heavy_obstacle")

	var post_col := CollisionShape3D.new()
	var post_shape := BoxShape3D.new()
	post_shape.size = Vector3(0.35, 5.8, 0.35)
	post_col.shape = post_shape
	post_col.position = Vector3(0.0, 2.9, 0.0)
	post_body.add_child(post_col)
	lamppost_root.add_child(post_body)

	# Horizontal arm extending over guardrail toward road
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.3, 0.18, 0.18)
	arm_mesh.material = _get_wood_post_mat()

	var arm_inst := MeshInstance3D.new()
	arm_inst.mesh = arm_mesh
	var arm_offset_x: float = 0.5 if on_left_verge else -0.5
	arm_inst.position = Vector3(arm_offset_x, 5.5, 0.0)
	lamppost_root.add_child(arm_inst)

	# Lantern fixture box
	var lantern_mesh := BoxMesh.new()
	lantern_mesh.size = Vector3(0.35, 0.45, 0.35)
	lantern_mesh.material = _get_lantern_emission_mat()

	var lantern_inst := MeshInstance3D.new()
	lantern_inst.mesh = lantern_mesh
	var lantern_x: float = 1.0 if on_left_verge else -1.0
	lantern_inst.position = Vector3(lantern_x, 5.3, 0.0)
	lamppost_root.add_child(lantern_inst)

	# OmniLight3D with FlickerLight controller
	var light := FlickerLight.new()
	light.name = "FlickerLight"
	light.position = Vector3(lantern_x, 5.0, 0.0)
	light.light_color = Color(1.0, 0.78, 0.45, 1.0) # Sodium-vapor amber
	light.base_energy = 2.4
	light.omni_range = 16.0
	light.omni_attenuation = 1.3
	light.is_flickering = rng.randf() < 0.65 # 65% chance of flickering lamppost
	lamppost_root.add_child(light)

	var local_offset := Vector3(verge_x, 0.0, 0.0)
	lamppost_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(lamppost_root)

## Spawns a tall, slender dark vertical box standing silently on the shoulder.
func _spawn_silhouette(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left_verge: bool = rng.randf() < 0.5
	# Positioned right along the open shoulder (X = ±7.8m)
	var verge_x: float = -7.8 if on_left_verge else 7.8
	verge_x += rng.randf_range(-0.15, 0.15) * (-1.0 if on_left_verge else 1.0)

	var silhouette_root := Node3D.new()
	silhouette_root.name = "Silhouette_%d" % slice_idx

	# Body box (1.4m height, human proportions)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.44, 1.4, 0.32)
	body_mesh.material = _get_silhouette_mat()

	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0.0, 0.7, 0.0)
	silhouette_root.add_child(body_inst)

	# Head box (0.32m height) - total humanoid height ~1.8m
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.28, 0.32, 0.28)
	head_mesh.material = _get_silhouette_mat()

	var head_inst := MeshInstance3D.new()
	head_inst.mesh = head_mesh
	head_inst.position = Vector3(0.0, 1.56, 0.0)
	silhouette_root.add_child(head_inst)

	# Solid physical collision for silhouette
	var sil_body := StaticBody3D.new()
	sil_body.name = "SilhouetteCollision"
	sil_body.collision_layer = 1
	sil_body.collision_mask = 1
	var sil_col := CollisionShape3D.new()
	var sil_shape := BoxShape3D.new()
	sil_shape.size = Vector3(0.5, 1.8, 0.4)
	sil_col.shape = sil_shape
	sil_col.position = Vector3(0.0, 0.9, 0.0)
	sil_body.add_child(sil_col)
	silhouette_root.add_child(sil_body)

	# Detection area for narrative radio trigger
	var det_area := Area3D.new()
	det_area.name = "ProximityArea"
	var det_col := CollisionShape3D.new()
	var det_shape := SphereShape3D.new()
	det_shape.radius = 18.0
	det_col.shape = det_shape
	det_area.add_child(det_col)
	det_area.body_entered.connect(func(body: Node3D):
		if body is Van and RadioManager.instance:
			RadioManager.instance.report_silhouette_proximity(silhouette_root.global_position)
	)
	silhouette_root.add_child(det_area)

	# Viscous dark crimson puddle beneath silhouette
	var puddle_inst := MeshInstance3D.new()
	var puddle_mesh := BoxMesh.new()
	puddle_mesh.size = Vector3(1.5, 0.015, 1.4)
	puddle_mesh.material = _get_blood_crimson_mat()
	puddle_inst.mesh = puddle_mesh
	puddle_inst.position = Vector3(0.0, 0.012, 0.0)
	silhouette_root.add_child(puddle_inst)

	var local_offset := Vector3(verge_x, 0.2, 0.0)
	silhouette_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(silhouette_root)

## Spawns a roadside milestone marker counting down toward Kilómetro 77.
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

## Spawns an eerie composite hitchhiker on the right verge with dynamic tracking and micro-interactions.
func _spawn_hitchhiker(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	# Positioned right on the open gravel shoulder (X = 7.8m), completely accessible
	var verge_x: float = 7.8 + rng.randf_range(-0.1, 0.1)

	var hitchhiker_root: Node3D = null
	if HitchhikerScene:
		hitchhiker_root = HitchhikerScene.instantiate()

	if not hitchhiker_root:
		# Fallback procedural generation if scene failed to load
		hitchhiker_root = Hitchhiker.new()

		var legs_mesh := BoxMesh.new()
		legs_mesh.size = Vector3(0.36, 0.76, 0.28)
		legs_mesh.material = _get_silhouette_mat()
		var legs_inst := MeshInstance3D.new()
		legs_inst.mesh = legs_mesh
		legs_inst.position = Vector3(0.0, 0.38, 0.0)
		hitchhiker_root.add_child(legs_inst)

		var torso_mesh := BoxMesh.new()
		torso_mesh.size = Vector3(0.46, 0.68, 0.32)
		torso_mesh.material = _get_silhouette_mat()
		var torso_inst := MeshInstance3D.new()
		torso_inst.name = "Torso"
		torso_inst.mesh = torso_mesh
		torso_inst.position = Vector3(0.0, 1.10, 0.0)
		hitchhiker_root.add_child(torso_inst)

		var head_mesh := BoxMesh.new()
		head_mesh.size = Vector3(0.28, 0.30, 0.28)
		head_mesh.material = _get_silhouette_mat()
		var head_inst := MeshInstance3D.new()
		head_inst.name = "Head"
		head_inst.mesh = head_mesh
		head_inst.position = Vector3(0.0, 1.59, 0.0)
		hitchhiker_root.add_child(head_inst)

		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(0.70, 0.14, 0.14)
		arm_mesh.material = _get_silhouette_mat()
		var arm_inst := MeshInstance3D.new()
		arm_inst.name = "RightArm"
		arm_inst.mesh = arm_mesh
		arm_inst.position = Vector3(-0.46, 1.20, 0.15)
		hitchhiker_root.add_child(arm_inst)

		var thumb_mesh := BoxMesh.new()
		thumb_mesh.size = Vector3(0.10, 0.18, 0.10)
		thumb_mesh.material = _get_silhouette_mat()
		var thumb_inst := MeshInstance3D.new()
		thumb_inst.mesh = thumb_mesh
		thumb_inst.position = Vector3(-0.76, 1.32, 0.15)
		hitchhiker_root.add_child(thumb_inst)

		var hitch_body := StaticBody3D.new()
		hitch_body.name = "HitchhikerCollision"
		hitch_body.collision_layer = 1
		hitch_body.collision_mask = 1
		var hitch_col := CollisionShape3D.new()
		var hitch_shape := BoxShape3D.new()
		hitch_shape.size = Vector3(0.5, 1.8, 0.4)
		hitch_col.shape = hitch_shape
		hitch_col.position = Vector3(0.0, 0.9, 0.0)
		hitch_body.add_child(hitch_col)
		hitchhiker_root.add_child(hitch_body)

	hitchhiker_root.name = "Hitchhiker_%d" % slice_idx
	var local_offset := Vector3(verge_x, 0.2, 0.0)
	# Initially angled facing oncoming traffic (165 degrees on Y axis)
	var initial_basis := Basis(Vector3.UP, deg_to_rad(165.0))
	hitchhiker_root.transform = slice_tr * Transform3D(initial_basis, local_offset)
	segment.add_child(hitchhiker_root)

## Spawns an open rural bus stop shelter with 3 walls, slanted roof, and optional interior presence.
func _spawn_bus_stop(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	# Positioned right along the road shoulder edge (X = 8.0m)
	var verge_x: float = 8.0

	var shelter_root := Node3D.new()
	shelter_root.name = "BusStop_%d" % slice_idx

	var concrete_mat := _get_bus_stop_mat()
	var wood_mat := _get_bus_stop_wood_mat()

	# 1. Base floor slab (BoxMesh)
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.2, 0.2, 2.6)
	floor_mesh.material = concrete_mat

	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	floor_inst.position = Vector3(0.0, 0.1, 0.0)
	shelter_root.add_child(floor_inst)

	# 2. Back wall (BoxMesh)
	var back_wall_mesh := BoxMesh.new()
	back_wall_mesh.size = Vector3(4.2, 2.5, 0.2)
	back_wall_mesh.material = concrete_mat

	var back_inst := MeshInstance3D.new()
	back_inst.mesh = back_wall_mesh
	back_inst.position = Vector3(0.0, 1.35, 1.2)
	shelter_root.add_child(back_inst)

	# 3. Left side wall (BoxMesh)
	var left_wall_mesh := BoxMesh.new()
	left_wall_mesh.size = Vector3(0.2, 2.5, 2.4)
	left_wall_mesh.material = concrete_mat

	var left_inst := MeshInstance3D.new()
	left_inst.mesh = left_wall_mesh
	left_inst.position = Vector3(-2.0, 1.35, 0.0)
	shelter_root.add_child(left_inst)

	# 4. Right side wall (BoxMesh)
	var right_wall_mesh := BoxMesh.new()
	right_wall_mesh.size = Vector3(0.2, 2.5, 2.4)
	right_wall_mesh.material = concrete_mat

	var right_inst := MeshInstance3D.new()
	right_inst.mesh = right_wall_mesh
	right_inst.position = Vector3(2.0, 1.35, 0.0)
	shelter_root.add_child(right_inst)

	# 5. Slanted roof (BoxMesh angled forward)
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(4.6, 0.15, 2.9)
	roof_mesh.material = concrete_mat

	var roof_inst := MeshInstance3D.new()
	roof_inst.mesh = roof_mesh
	roof_inst.position = Vector3(0.0, 2.65, 0.0)
	roof_inst.rotation.x = deg_to_rad(-8.0)
	shelter_root.add_child(roof_inst)

	# Solid collision for bus stop shelter walls and roof
	var shelter_body := StaticBody3D.new()
	shelter_body.name = "BusStopCollision"
	shelter_body.collision_layer = 1
	shelter_body.collision_mask = 1
	shelter_body.add_to_group("heavy_obstacle")

	var col_back := CollisionShape3D.new()
	var shape_back := BoxShape3D.new()
	shape_back.size = Vector3(4.2, 2.5, 0.3)
	col_back.shape = shape_back
	col_back.position = Vector3(0.0, 1.35, 1.2)
	shelter_body.add_child(col_back)

	var col_left := CollisionShape3D.new()
	var shape_left := BoxShape3D.new()
	shape_left.size = Vector3(0.3, 2.5, 2.4)
	col_left.shape = shape_left
	col_left.position = Vector3(-2.0, 1.35, 0.0)
	shelter_body.add_child(col_left)

	var col_right := CollisionShape3D.new()
	var shape_right := BoxShape3D.new()
	shape_right.size = Vector3(0.3, 2.5, 2.4)
	col_right.shape = shape_right
	col_right.position = Vector3(2.0, 1.35, 0.0)
	shelter_body.add_child(col_right)

	var col_roof := CollisionShape3D.new()
	var shape_roof := BoxShape3D.new()
	shape_roof.size = Vector3(4.6, 0.25, 2.9)
	col_roof.shape = shape_roof
	col_roof.position = Vector3(0.0, 2.65, 0.0)
	col_roof.rotation.x = deg_to_rad(-8.0)
	shelter_body.add_child(col_roof)

	shelter_root.add_child(shelter_body)

	# 6. Interior bench (BoxMesh)
	var bench_mesh := BoxMesh.new()
	bench_mesh.size = Vector3(2.6, 0.12, 0.5)
	bench_mesh.material = wood_mat

	var bench_inst := MeshInstance3D.new()
	bench_inst.mesh = bench_mesh
	bench_inst.position = Vector3(0.0, 0.55, 0.7)
	shelter_root.add_child(bench_inst)

	# 7. Sickly light bulb casting illumination across the shoulder
	var bulb := FlickerLight.new()
	bulb.name = "ShelterBulb"
	bulb.position = Vector3(0.0, 2.3, 0.0)
	bulb.light_color = Color(0.85, 0.9, 0.7, 1.0)
	bulb.base_energy = 2.5
	bulb.omni_range = 14.0
	bulb.is_flickering = rng.randf() < 0.7
	shelter_root.add_child(bulb)

	# 8. Chance of motionless 1.8m figure waiting inside under the bulb
	if rng.randf() < 0.65:
		var figure_inst := MeshInstance3D.new()
		var figure_mesh := BoxMesh.new()
		figure_mesh.size = Vector3(0.42, 1.80, 0.36)
		figure_mesh.material = _get_silhouette_mat()
		figure_inst.mesh = figure_mesh
		figure_inst.position = Vector3(0.0, 1.0, 0.5)
		shelter_root.add_child(figure_inst)

	# Detection area for narrative radio trigger
	var det_area := Area3D.new()
	det_area.name = "ProximityArea"
	var det_col := CollisionShape3D.new()
	var det_shape := SphereShape3D.new()
	det_shape.radius = 20.0
	det_col.shape = det_shape
	det_area.add_child(det_col)
	det_area.body_entered.connect(func(body: Node3D):
		if body is Van and RadioManager.instance:
			RadioManager.instance.report_silhouette_proximity(shelter_root.global_position)
	)
	shelter_root.add_child(det_area)

	var local_offset := Vector3(verge_x, 0.2, 0.0)
	shelter_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(shelter_root)

## Spawns dense pine forest tree silhouettes along outer road margins in 3 depth layers with undergrowth.
func _spawn_woods_for_segment(segment: RoadSegment, rng: RandomNumberGenerator) -> void:
	var slice_count: int = segment.get_slice_count()
	var bark_mat := _get_tree_bark_mat()
	var foliage_mat := _get_tree_foliage_mat()
	var grass_mat := _get_grass_wind_mat()
	var fern_mat := _get_fern_mat()
	var log_mat := _get_wet_log_mat()

	for i in range(slice_count):
		var slice_tr: Transform3D = segment.get_slice_transform(i)

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

		# Layer 3: Deep backdrop horizon silhouettes (29.0m to 44.0m) - visual only, tall dark silhouettes piercing the fog
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

## Helper to build a composite layered conifer pine model with 4 staggered tiers and root swells.
func _spawn_tree(segment: RoadSegment, slice_tr: Transform3D, local_offset: Vector3, bark_mat: StandardMaterial3D, foliage_mat: Material, rng: RandomNumberGenerator, has_collision: bool = true, min_h: float = 6.5, max_h: float = 9.5) -> void:
	var tree_root := Node3D.new()
	var height: float = rng.randf_range(min_h, max_h)
	var trunk_h: float = height * 0.42

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

	# Random scale variation between 0.7x and 1.4x and random yaw orientation
	var scale_mult: float = rng.randf_range(0.7, 1.4)
	var yaw_rot: float = rng.randf_range(-PI, PI)
	var local_tr := Transform3D(Basis(Vector3.UP, yaw_rot).scaled(Vector3(scale_mult, scale_mult, scale_mult)), local_offset)
	tree_root.transform = slice_tr * local_tr
	segment.add_child(tree_root)

## Spawns a distant, unreachable cabin in the dark woods with an illuminated window and eerie light.
func _spawn_distant_cabin(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var on_left: bool = rng.randf() < 0.5
	var distance_x: float = rng.randf_range(-34.0, -26.0) if on_left else rng.randf_range(26.0, 34.0)

	var cabin_root := Node3D.new()
	cabin_root.name = "DistantCabin_%d" % slice_idx

	# Solid collision for cabin
	var cabin_body := StaticBody3D.new()
	cabin_body.name = "CabinCollision"
	cabin_body.collision_layer = 1
	cabin_body.collision_mask = 1
	cabin_body.add_to_group("heavy_obstacle")

	var cabin_col := CollisionShape3D.new()
	var cabin_shape := BoxShape3D.new()
	cabin_shape.size = Vector3(5.2, 3.4, 5.8)
	cabin_col.shape = cabin_shape
	cabin_col.position = Vector3(0.0, 1.7, 0.0)
	cabin_body.add_child(cabin_col)
	cabin_root.add_child(cabin_body)

	# Cabin body (BoxMesh)
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(5.2, 3.4, 5.8)
	cabin_mesh.material = _get_cabin_wall_mat()

	var cabin_inst := MeshInstance3D.new()
	cabin_inst.mesh = cabin_mesh
	cabin_inst.position = Vector3(0.0, 1.7, 0.0)
	cabin_root.add_child(cabin_inst)

	# Pitched Roof (PrismMesh)
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(5.6, 1.8, 6.2)
	roof_mesh.material = _get_cabin_roof_mat()

	var roof_inst := MeshInstance3D.new()
	roof_inst.mesh = roof_mesh
	roof_inst.position = Vector3(0.0, 4.3, 0.0)
	cabin_root.add_child(roof_inst)

	# Eerie glowing yellow window (BoxMesh with warm emission)
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(0.9, 0.9, 0.1)
	window_mesh.material = _get_window_emission_mat()

	var window_inst := MeshInstance3D.new()
	window_inst.mesh = window_mesh
	var window_x: float = 1.2 if on_left else -1.2
	window_inst.position = Vector3(window_x, 1.8, -2.95)
	cabin_root.add_child(window_inst)

	# Distant warm OmniLight3D emanating from the window
	var light := OmniLight3D.new()
	light.position = Vector3(window_x, 1.8, -3.2)
	light.light_color = Color(1.0, 0.78, 0.3, 1.0)
	light.light_energy = 1.8
	light.omni_range = 14.0
	light.omni_attenuation = 1.2
	cabin_root.add_child(light)

	var local_offset := Vector3(distance_x, 0.0, 0.0)
	cabin_root.transform = slice_tr * Transform3D(Basis.IDENTITY, local_offset)
	segment.add_child(cabin_root)

## Spawns a retro roadside highway guide sign or yellow hazard sign.
func _spawn_highway_guide_sign(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var verge_x: float = 8.6

	var sign_root := Node3D.new()
	sign_root.name = "GuideSign_%d" % slice_idx

	var is_green_route_sign: bool = rng.randf() < 0.65

	if is_green_route_sign:
		# Double dark steel/wood support posts
		var post_mat := _get_wood_post_mat()
		for post_x in [-0.85, 0.85]:
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.14, 3.4, 0.14)
			post_mesh.material = post_mat
			var post_inst := MeshInstance3D.new()
			post_inst.mesh = post_mesh
			post_inst.position = Vector3(post_x, 1.7, 0.0)
			sign_root.add_child(post_inst)

		# Outer white reflective border
		var border_mesh := BoxMesh.new()
		border_mesh.size = Vector3(2.64, 1.44, 0.06)
		border_mesh.material = _get_guide_sign_white_mat()
		var border_inst := MeshInstance3D.new()
		border_inst.mesh = border_mesh
		border_inst.position = Vector3(0.0, 2.5, 0.0)
		sign_root.add_child(border_inst)

		# Green retro highway plate
		var plate_mesh := BoxMesh.new()
		plate_mesh.size = Vector3(2.52, 1.32, 0.08)
		plate_mesh.material = _get_guide_sign_green_mat()
		var plate_inst := MeshInstance3D.new()
		plate_inst.mesh = plate_mesh
		plate_inst.position = Vector3(0.0, 2.5, 0.02)
		sign_root.add_child(plate_inst)

		# Retro highway text label (facing oncoming vehicles)
		var label := Label3D.new()
		label.name = "SignText"
		var sign_options: Array[String] = [
			"RUTA NACIONAL 77\nKILÓMETRO %d\nNO SE DETENGA" % current_kilometer,
			"RUTA 77 SUR\nNIEBLA DENSA\nLUCES OBLIGATORIAS",
			"TRAMO VIGILADO\nKM %d\nCONSERVE SU CARRIL" % current_kilometer,
			"RUTA NACIONAL 77\nZONA RURAL AISLADA\nSIN ASISTENCIA"
		]
		label.text = sign_options[rng.randi_range(0, sign_options.size() - 1)]
		label.font_size = 28
		label.outline_size = 4
		label.modulate = Color(0.96, 0.96, 0.94, 1.0)
		label.outline_modulate = Color(0.04, 0.14, 0.08, 1.0)
		label.position = Vector3(0.0, 2.5, 0.07)
		sign_root.add_child(label)
	else:
		# Single post yellow hazard diamond sign
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

		# Label with retro warning
		var label := Label3D.new()
		label.name = "HazardText"
		var hazard_options: Array[String] = [
			"PELIGRO\nCURVA",
			"ZONA DE\nNIEBLA",
			"CALZADA\nRESBALADIZA",
			"REDUZCA\nVELOCIDAD"
		]
		label.text = hazard_options[rng.randi_range(0, hazard_options.size() - 1)]
		label.font_size = 26
		label.outline_size = 5
		label.modulate = Color(0.10, 0.10, 0.10, 1.0)
		label.outline_modulate = Color(1.0, 0.75, 0.1, 1.0)
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

## Spawns a broken-down vehicle parked on the shoulder with hazard lights blinking and open door.
func _spawn_shoulder_breakdown(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var shoulder_x: float = 7.9

	var car_root := StaticBody3D.new()
	car_root.name = "ShoulderBreakdown_%d" % slice_idx
	car_root.collision_layer = 1
	car_root.collision_mask = 1
	car_root.add_to_group("heavy_obstacle")

	var rust_mat := _get_rust_material()
	var glass_mat := _get_cabin_glass_mat()
	var hazard_mat := _get_hazard_amber_blink_mat()

	# Lower body / chassis
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.9, 0.65, 4.1)
	body_mesh.material = rust_mat
	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0.0, 0.55, 0.0)
	car_root.add_child(body_inst)

	# Cabin with dark glass
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.65, 0.55, 1.9)
	cabin_mesh.material = glass_mat
	var cabin_inst := MeshInstance3D.new()
	cabin_inst.mesh = cabin_mesh
	cabin_inst.position = Vector3(0.0, 1.15, -0.1)
	car_root.add_child(cabin_inst)

	# Open driver door casting a silhouette into the fog
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.12, 0.85, 1.1)
	door_mesh.material = rust_mat
	var door_inst := MeshInstance3D.new()
	door_inst.mesh = door_mesh
	door_inst.position = Vector3(-0.95, 0.85, 0.2)
	door_inst.rotation.y = deg_to_rad(-55.0)
	car_root.add_child(door_inst)

	# 4 dark tires
	for wheel_pos in [Vector3(-0.95, 0.35, -1.2), Vector3(0.95, 0.35, -1.2), Vector3(-0.95, 0.35, 1.2), Vector3(0.95, 0.35, 1.2)]:
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.34
		wheel_mesh.bottom_radius = 0.34
		wheel_mesh.height = 0.24
		wheel_mesh.material = _get_silhouette_mat()
		var wheel_inst := MeshInstance3D.new()
		wheel_inst.mesh = wheel_mesh
		wheel_inst.rotation.z = deg_to_rad(90.0)
		wheel_inst.position = wheel_pos
		car_root.add_child(wheel_inst)

	# Blinking amber hazard taillights
	for rear_x in [-0.82, 0.82]:
		var light_box := BoxMesh.new()
		light_box.size = Vector3(0.16, 0.12, 0.06)
		light_box.material = hazard_mat
		var l_inst := MeshInstance3D.new()
		l_inst.mesh = light_box
		l_inst.position = Vector3(rear_x, 0.65, 2.05)
		car_root.add_child(l_inst)

	# Pulsating amber hazard light casting glowing flares into the rain/fog
	var hazard_light := FlickerLight.new()
	hazard_light.position = Vector3(0.0, 0.75, 2.2)
	hazard_light.light_color = Color(1.0, 0.55, 0.05, 1.0)
	hazard_light.base_energy = 5.0
	hazard_light.min_energy = 0.2
	hazard_light.omni_range = 14.0
	hazard_light.flicker_probability = 0.8
	car_root.add_child(hazard_light)

	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(2.2, 1.4, 4.3)
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 0.7, 0.0)
	car_root.add_child(col)

	var yaw: float = rng.randf_range(deg_to_rad(-8.0), deg_to_rad(8.0))
	var local_tr := Transform3D(Basis(Vector3.UP, yaw), Vector3(shoulder_x, 0.0, 0.0))
	car_root.transform = slice_tr * local_tr
	segment.add_child(car_root)

## Spawns strange low-poly organic roadkill/obstruction near the centerline requiring lane swerves.
func _spawn_roadkill_obstruction(segment: RoadSegment, slice_idx: int, rng: RandomNumberGenerator) -> void:
	var slice_tr: Transform3D = segment.get_slice_transform(slice_idx)
	var center_offset_x: float = rng.randf_range(-1.4, 1.4)

	var roadkill_root := StaticBody3D.new()
	roadkill_root.name = "RoadkillObstruction_%d" % slice_idx
	roadkill_root.collision_layer = 1
	roadkill_root.collision_mask = 1
	roadkill_root.add_to_group("heavy_obstacle")

	var flesh_mat := _get_organic_flesh_mat()
	var blood_mat := _get_blood_crimson_mat()

	# Large slick puddle of coagulated crimson blood on asphalt
	var puddle_mesh := BoxMesh.new()
	puddle_mesh.size = Vector3(2.4, 0.015, 2.8)
	puddle_mesh.material = blood_mat
	var puddle_inst := MeshInstance3D.new()
	puddle_inst.mesh = puddle_mesh
	puddle_inst.position = Vector3(0.0, 0.51, 0.0)
	roadkill_root.add_child(puddle_inst)

	# Distorted organic body mass
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.3, 0.48, 1.6)
	body_mesh.material = flesh_mat
	var body_inst := MeshInstance3D.new()
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0.0, 0.72, 0.0)
	body_inst.rotation.y = rng.randf_range(-PI, PI)
	roadkill_root.add_child(body_inst)

	# Projecting organic horns / twisted limbs
	for limb_i in range(3):
		var limb_mesh := PrismMesh.new()
		limb_mesh.size = Vector3(0.24, 0.65, 0.24)
		limb_mesh.material = flesh_mat
		var limb_inst := MeshInstance3D.new()
		limb_inst.mesh = limb_mesh
		limb_inst.position = Vector3(rng.randf_range(-0.4, 0.4), 0.85, rng.randf_range(-0.5, 0.5))
		limb_inst.rotation = Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-PI, PI), rng.randf_range(-0.4, 0.4))
		roadkill_root.add_child(limb_inst)

	# Solid collider
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(1.6, 0.8, 1.8)
	var col := CollisionShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0.0, 0.7, 0.0)
	roadkill_root.add_child(col)

	var local_tr := Transform3D(Basis.IDENTITY, Vector3(center_offset_x, 0.0, 0.0))
	roadkill_root.transform = slice_tr * local_tr
	segment.add_child(roadkill_root)
