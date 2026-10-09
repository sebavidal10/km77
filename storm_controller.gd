class_name StormController
extends Node3D

@export_group("References")
## Vehicle to follow with rain particle volume.
@export var target_vehicle: Node3D
## Directional light used for procedural lightning flashes.
@export var lightning_light: DirectionalLight3D

@export_group("Rain Parameters")
## Total particle count for torrential rain downpour.
@export var rain_amount: int = 2400
## Half-extents of the overhead rain emitter box in meters (28m x 7m x 28m).
@export var rain_box_extents: Vector3 = Vector3(14.0, 3.5, 14.0)
## Downward terminal velocity of falling raindrops.
@export var rain_fall_speed: float = 34.0
## Wind direction vector slanting the rain.
@export var rain_wind_vector: Vector3 = Vector3(0.12, -1.0, 0.16)

@export_group("Lightning Parameters")
## Minimum seconds between procedural lightning strikes.
@export var min_lightning_interval: float = 18.0
## Maximum seconds between procedural lightning strikes.
@export var max_lightning_interval: float = 35.0
## Peak illumination energy of the primary lightning burst.
@export var lightning_peak_energy: float = 3.8
## Pale cyan-blue electric tint of lightning illumination.
@export var lightning_color: Color = Color(0.85, 0.92, 1.0, 1.0)

# Runtime state
var _lightning_timer: float = 0.0
var _next_lightning_interval: float = 22.0
var _flash_stage: int = 0 # 0=idle, 1=burst1, 2=dip, 3=burst2, 4=decay
var _stage_timer: float = 0.0
var _rain_particles: GPUParticles3D

func _ready() -> void:
	_init_lightning_light()
	_create_rain_particles()
	_schedule_next_strike()

func _init_lightning_light() -> void:
	if not lightning_light:
		lightning_light = get_node_or_null("../DirectionalLight3D") as DirectionalLight3D
	if lightning_light:
		lightning_light.light_energy = 0.0
		lightning_light.light_color = lightning_color

func _create_rain_particles() -> void:
	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "RainParticles"
	_rain_particles.amount = rain_amount
	_rain_particles.lifetime = 0.65
	_rain_particles.local_coords = false
	_rain_particles.visibility_aabb = AABB(Vector3(-25.0, -20.0, -25.0), Vector3(50.0, 40.0, 50.0))

	# Particle mesh: elongated translucent droplet primitive
	var drop_mesh := BoxMesh.new()
	drop_mesh.size = Vector3(0.02, 0.65, 0.02)

	var drop_mat := StandardMaterial3D.new()
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.albedo_color = Color(0.82, 0.88, 1.0, 0.38)
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mesh.material = drop_mat
	_rain_particles.draw_pass_1 = drop_mesh

	# Particle process material
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_mat.emission_box_extents = rain_box_extents
	proc_mat.direction = rain_wind_vector.normalized()
	proc_mat.spread = 4.0
	proc_mat.initial_velocity_min = rain_fall_speed * 0.9
	proc_mat.initial_velocity_max = rain_fall_speed * 1.1
	proc_mat.gravity = Vector3(0.0, -12.0, 0.0)
	proc_mat.color = Color(0.85, 0.9, 1.0, 0.42)
	_rain_particles.process_material = proc_mat

	add_child(_rain_particles)

func _process(delta: float) -> void:
	_update_rain_position()
	_process_lightning(delta)

func _update_rain_position() -> void:
	if not _rain_particles:
		return
	if not target_vehicle:
		_find_vehicle()
	if target_vehicle and is_instance_valid(target_vehicle):
		# Position emitter overhead slightly ahead in vehicle heading
		var fwd := -target_vehicle.global_transform.basis.z
		_rain_particles.global_position = target_vehicle.global_position + (Vector3.UP * 9.5) + (fwd * 3.5)

func _find_vehicle() -> void:
	var tree := get_tree()
	if not tree:
		return
	var nodes := tree.get_nodes_in_group("player")
	if not nodes.is_empty():
		target_vehicle = nodes[0] as Node3D
		return
	if tree.current_scene:
		var van := tree.current_scene.get_node_or_null("Van") as Node3D
		if van:
			target_vehicle = van

func _schedule_next_strike() -> void:
	_next_lightning_interval = randf_range(min_lightning_interval, max_lightning_interval)
	_lightning_timer = 0.0

## Triggers an immediate double-strike lightning flash.
func trigger_lightning_strike() -> void:
	_flash_stage = 1
	_stage_timer = 0.0

func _process_lightning(delta: float) -> void:
	if not lightning_light:
		return

	if _flash_stage == 0:
		_lightning_timer += delta
		if _lightning_timer >= _next_lightning_interval:
			trigger_lightning_strike()
	elif _flash_stage == 1:
		# First sudden burst (approx 0.08s)
		lightning_light.light_energy = lightning_peak_energy * 0.85
		_stage_timer += delta
		if _stage_timer >= 0.08:
			_flash_stage = 2
			_stage_timer = 0.0
			_apply_lightning_shake(0.20)
	elif _flash_stage == 2:
		# Brief dip between strikes (approx 0.04s)
		lightning_light.light_energy = 0.35
		_stage_timer += delta
		if _stage_timer >= 0.04:
			_flash_stage = 3
			_stage_timer = 0.0
	elif _flash_stage == 3:
		# Second powerful burst (approx 0.14s)
		lightning_light.light_energy = lightning_peak_energy
		_stage_timer += delta
		if _stage_timer >= 0.14:
			_flash_stage = 4
			_stage_timer = 0.0
			_apply_lightning_shake(0.35)
	elif _flash_stage == 4:
		# Rapid decay back to dark night (0.12s)
		lightning_light.light_energy = move_toward(lightning_light.light_energy, 0.0, 32.0 * delta)
		if lightning_light.light_energy <= 0.01:
			lightning_light.light_energy = 0.0
			_flash_stage = 0
			_stage_timer = 0.0
			_schedule_next_strike()

func _apply_lightning_shake(trauma: float) -> void:
	var tree := get_tree()
	if not tree:
		return
	var cam_nodes := tree.get_nodes_in_group("chase_camera")
	if not cam_nodes.is_empty():
		var cam := cam_nodes[0] as Camera3D
		if cam and cam.has_method("apply_shake"):
			cam.apply_shake(trauma)
