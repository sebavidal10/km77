class_name RearStalker
extends CharacterBody3D

signal stalker_approached
signal stalker_overtaken
signal stalker_evaded

enum State {
	CHASE,
	OVERTAKE,
	EVADE,
	DISSOLVED
}

@export_group("Stalker Tuning")
## Extra speed above the player's forward speed in m/s (~22 to 25 km/h).
@export var overtake_speed_boost: float = 6.8
## Distance behind the van (meters) at which high-beam blinking and overtaking begins.
@export var overtake_trigger_dist: float = 15.0
## Distance ahead of the van (meters) at which the stalker dissolves into the night fog.
@export var dissolve_forward_dist: float = 40.0

var current_state: State = State.CHASE
var target_player: Node3D = null
var current_speed: float = 24.0

var _headlight_left: SpotLight3D
var _headlight_right: SpotLight3D
var _lens_left_mat: StandardMaterial3D
var _lens_right_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _tire_mat: StandardMaterial3D

var _blink_timer: float = 0.0
var _blink_state: bool = true
var _flicker_timer: float = 0.0
var _evade_timer: float = 0.0
var _evade_dir: Vector3 = Vector3.ZERO
var _target_lateral_offset: float = -3.8 # Left overtaking lane
var _signaled_radio: bool = false
var _is_dissolving: bool = false
var _crash_started: bool = false

func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	add_to_group("heavy_obstacle")
	add_to_group("stalker_vehicle")
	_build_visuals_and_collision()
	_find_player()

func setup(player_node: Node3D) -> void:
	target_player = player_node
	if target_player:
		var van_fwd_speed: float = 18.0
		if target_player is Van:
			van_fwd_speed = maxf(12.0, (target_player as Van).forward_speed_state)
		current_speed = van_fwd_speed + overtake_speed_boost

func _build_visuals_and_collision() -> void:
	# 1. Dark chassis material
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.035, 0.035, 0.042, 1.0) # Obsidian funeral lacquer
	_body_mat.roughness = 0.42
	_body_mat.metallic = 0.48
	_tire_mat = StandardMaterial3D.new()
	_tire_mat.albedo_color = Color(0.018, 0.018, 0.018, 1.0)
	_tire_mat.roughness = 0.96

	# Vintage Gothic funeral hearse body stalks the player from behind.
	var hearse_scene := load("res://models/route77_hearse.glb") as PackedScene
	if hearse_scene:
		var hearse_visual := hearse_scene.instantiate()
		hearse_visual.name = "StalkerHearseBody"
		add_child(hearse_visual)
	else:
		var sedan_scene := load("res://models/route77_sedan.glb") as PackedScene
		if sedan_scene:
			var sedan_visual := sedan_scene.instantiate()
			sedan_visual.name = "StalkerSedanBody"
			_apply_stalker_body_material(sedan_visual)
			add_child(sedan_visual)

	# Four low-poly wheels aligned to the elongated hearse wheelbase.
	for wheel_pos in [Vector3(-0.96, 0.37, -1.35), Vector3(0.96, 0.37, -1.35), Vector3(-0.96, 0.37, 1.55), Vector3(0.96, 0.37, 1.55)]:
		var wheel_mesh := CylinderMesh.new()
		wheel_mesh.top_radius = 0.34
		wheel_mesh.bottom_radius = 0.34
		wheel_mesh.height = 0.24
		wheel_mesh.radial_segments = 8
		wheel_mesh.material = _tire_mat
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.rotation.z = PI * 0.5
		wheel.position = wheel_pos
		add_child(wheel)

	# Collision box
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(1.92, 1.65, 4.85)

	var col_inst := CollisionShape3D.new()
	col_inst.name = "CollisionShape3D"
	col_inst.shape = col_shape
	col_inst.position = Vector3(0.0, 0.82, 0.0)
	add_child(col_inst)

	# 2. Glowing High-Beam Headlight Lenses
	_lens_left_mat = StandardMaterial3D.new()
	_lens_left_mat.albedo_color = Color(1.0, 0.92, 0.58, 1.0)
	_lens_left_mat.emission_enabled = true
	_lens_left_mat.emission = Color(1.0, 0.88, 0.48, 1.0)
	_lens_left_mat.emission_energy_multiplier = 6.5

	_lens_right_mat = _lens_left_mat.duplicate() as StandardMaterial3D

	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.32, 0.18, 0.06)

	var lens_left := MeshInstance3D.new()
	lens_left.name = "LensLeft"
	lens_left.mesh = lens_mesh
	lens_left.material_override = _lens_left_mat
	lens_left.position = Vector3(-0.66, 0.72, -2.35)
	add_child(lens_left)

	var lens_right := MeshInstance3D.new()
	lens_right.name = "LensRight"
	lens_right.mesh = lens_mesh
	lens_right.material_override = _lens_right_mat
	lens_right.position = Vector3(0.66, 0.72, -2.35)
	add_child(lens_right)

	# 3. High-Intensity High Beams (SpotLight3D pointing strictly -Z)
	_headlight_left = SpotLight3D.new()
	_headlight_left.name = "HeadlightLeft"
	_headlight_left.position = Vector3(-0.66, 0.72, -2.38)
	_headlight_left.rotation = Vector3.ZERO
	_headlight_left.light_color = Color(1.0, 0.92, 0.58, 1.0) # Eerie piercing vintage yellow
	_headlight_left.light_energy = 9.0
	_headlight_left.spot_range = 75.0
	_headlight_left.spot_angle = 32.0
	_headlight_left.light_volumetric_fog_energy = 4.2
	add_child(_headlight_left)

	_headlight_right = SpotLight3D.new()
	_headlight_right.name = "HeadlightRight"
	_headlight_right.position = Vector3(0.66, 0.72, -2.38)
	_headlight_right.rotation = Vector3.ZERO
	_headlight_right.light_color = Color(1.0, 0.92, 0.58, 1.0)
	_headlight_right.light_energy = 9.0
	_headlight_right.spot_range = 75.0
	_headlight_right.spot_angle = 32.0
	_headlight_right.light_volumetric_fog_energy = 4.2
	add_child(_headlight_right)

	# 4. Crimson Dagger Rear Taillight Lenses
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.88, 0.04, 0.04, 1.0)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(0.95, 0.04, 0.03, 1.0)
	tail_mat.emission_energy_multiplier = 4.0

	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(0.16, 0.48, 0.06)
	tail_mesh.material = tail_mat

	var tail_l := MeshInstance3D.new()
	tail_l.mesh = tail_mesh
	tail_l.position = Vector3(-0.78, 0.92, 2.62)
	add_child(tail_l)

	var tail_r := MeshInstance3D.new()
	tail_r.mesh = tail_mesh
	tail_r.position = Vector3(0.78, 0.92, 2.62)
	add_child(tail_r)

func _apply_stalker_body_material(node: Node) -> void:
	if node is MeshInstance3D:
		var lower_name := node.name.to_lower()
		if lower_name.contains("body shell") or lower_name.contains("underbody"):
			(node as MeshInstance3D).material_override = _body_mat
	for child in node.get_children():
		_apply_stalker_body_material(child)

func _find_player() -> void:
	if target_player:
		return
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		target_player = nodes[0] as Node3D
		return
	var root := get_tree().current_scene
	if root:
		target_player = root.get_node_or_null("Van") as Node3D

func _physics_process(delta: float) -> void:
	if not is_inside_tree() or _is_dissolving:
		return
	if not target_player:
		_find_player()
		if not target_player:
			queue_free()
			return

	var to_player := target_player.global_position - global_position
	var player_fwd := -target_player.global_transform.basis.z
	var player_right := target_player.global_transform.basis.x

	# Longitudinal distance along player heading (positive = stalker is behind player)
	var long_dist: float = to_player.dot(player_fwd)
	var lat_dist: float = to_player.dot(player_right)

	var player_speed_ms: float = 20.0
	if target_player is Van:
		player_speed_ms = maxf(10.0, (target_player as Van).forward_speed_state)

	match current_state:
		State.CHASE:
			# Stalker travels 20-25 km/h faster than player until ~15m behind van
			var target_speed := player_speed_ms + overtake_speed_boost
			current_speed = move_toward(current_speed, target_speed, 14.0 * delta)

			# Subtle high-beam flicker in fog
			_flicker_timer += delta
			if _flicker_timer >= 0.08:
				_flicker_timer = 0.0
				_set_headlight_energy(8.5 + randf_range(-1.4, 1.4))

			# Steer smoothly along the wake of the player
			var target_yaw := target_player.rotation.y
			var steer_target := target_player.global_position
			var to_steer := steer_target - global_position
			to_steer.y = 0.0
			if to_steer.length_squared() > 1.0:
				target_yaw = atan2(-to_steer.x, -to_steer.z)
			rotation.y = rotate_toward(rotation.y, target_yaw, 3.2 * delta)

			# Transition to Overtake when within ~15 meters
			if long_dist <= overtake_trigger_dist and long_dist > 0.0:
				current_state = State.OVERTAKE
				stalker_approached.emit()
				_broadcast_stalker_alert()

			# Check if player brake-checks hard
			if long_dist < 8.0 and long_dist > 0.0:
				var player_slow: bool = false
				if target_player is Van:
					player_slow = (target_player as Van).forward_speed_state < (current_speed - 6.0)
				if player_slow:
					_trigger_evasion(player_right)

		State.OVERTAKE:
			# Aggressive high-beam strobe blinking (~9 Hz)
			_blink_timer += delta
			if _blink_timer >= 0.11:
				_blink_timer = 0.0
				_blink_state = not _blink_state
				_set_headlight_visible(_blink_state)

			# Extra surge speed to pass cleanly
			var overtake_speed := player_speed_ms + overtake_speed_boost + 1.8
			current_speed = move_toward(current_speed, overtake_speed, 18.0 * delta)

			# Target the left overtaking lane
			var left_lane_target: Vector3 = target_player.global_position + (player_right * _target_lateral_offset)
			var to_overtake := left_lane_target - global_position
			to_overtake.y = 0.0

			var overtake_yaw := target_player.rotation.y
			if to_overtake.length_squared() > 1.0:
				overtake_yaw = atan2(-to_overtake.x, -to_overtake.z)
			rotation.y = rotate_toward(rotation.y, overtake_yaw, 3.8 * delta)

			# Check if player swerves to actively block the overtaking lane
			var blocking_offset := absf(lat_dist - _target_lateral_offset)
			if long_dist < 10.0 and long_dist > -2.0 and blocking_offset < 1.4:
				# Player is swerving right in front of the stalker to block it!
				_trigger_evasion(player_right)

			# Dissolve once 40m ahead of the van
			if long_dist < -dissolve_forward_dist:
				current_state = State.DISSOLVED
				stalker_overtaken.emit()
				_start_dissolve()

		State.EVADE:
			# Swerve violently into the roadside ditch
			_evade_timer += delta
			var evade_yaw := atan2(-_evade_dir.x, -_evade_dir.z)
			rotation.y = rotate_toward(rotation.y, evade_yaw, 5.5 * delta)
			current_speed = move_toward(current_speed, current_speed * 1.05, 12.0 * delta)

			if _evade_timer >= 1.2:
				_start_dissolve()

		State.DISSOLVED:
			return

	# Apply motion
	velocity = -transform.basis.z * current_speed
	velocity.y = -1.0
	move_and_slide()

	# Impact handling
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider and (collider.is_in_group("player") or collider is Van):
			_start_crash_burn()
			break

## A real impact leaves a burning wreck on the road instead of shrinking out of sight.
func _start_crash_burn() -> void:
	if _crash_started:
		return
	_crash_started = true
	_is_dissolving = true
	current_state = State.DISSOLVED
	current_speed = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)
	if _headlight_left:
		_headlight_left.light_energy = 0.0
		_headlight_left.visible = false
	if _headlight_right:
		_headlight_right.light_energy = 0.0
		_headlight_right.visible = false
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.albedo_color = Color(1.0, 0.24, 0.025, 0.94)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.13, 0.015)
	fire_mat.emission_energy_multiplier = 3.2
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.65
	flame_mesh.height = 1.5
	flame_mesh.material = fire_mat
	var flame := MeshInstance3D.new()
	flame.name = "ImpactFire"
	flame.mesh = flame_mesh
	flame.position = Vector3(0.0, 1.0, -0.15)
	flame.scale = Vector3(0.2, 0.25, 0.2)
	add_child(flame)
	var flash := OmniLight3D.new()
	flash.name = "CrashFlash"
	flash.light_color = Color(1.0, 0.28, 0.045)
	flash.light_energy = 7.0
	flash.omni_range = 13.0
	flash.position = Vector3(0.0, 1.15, -0.1)
	add_child(flash)
	var sparks := GPUParticles3D.new()
	sparks.name = "CrashSparks"
	sparks.amount = 36
	sparks.lifetime = 0.9
	sparks.one_shot = true
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 180.0
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0.0, -6.0, 0.0)
	sparks.process_material = process
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.045
	spark_mesh.height = 0.09
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.42, 0.07)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.2, 0.02)
	spark_mesh.material = spark_mat
	sparks.draw_pass_1 = spark_mesh
	sparks.position = Vector3(0.0, 1.05, -0.1)
	add_child(sparks)
	sparks.emitting = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flame, "scale", Vector3(0.9, 1.25, 0.9), 0.18)
	tween.tween_property(flash, "light_energy", 1.3, 1.4)
	tween.tween_property(fire_mat, "albedo_color", Color(1.0, 0.24, 0.025, 0.0), 4.8).set_delay(3.0)
	tween.tween_property(flash, "light_energy", 0.0, 4.8).set_delay(3.0)
	tween.chain().tween_callback(queue_free).set_delay(1.5)

func _trigger_evasion(player_right: Vector3) -> void:
	if current_state == State.EVADE or _is_dissolving:
		return
	current_state = State.EVADE
	_evade_timer = 0.0
	stalker_evaded.emit()

	# Determine evasion direction into roadside ditch
	var swerve_side: float = -1.0 if randf() < 0.5 else 1.0
	_evade_dir = (-transform.basis.z * 0.7 + player_right * swerve_side * 0.9).normalized()

	# Headlights flicker out during crash
	_set_headlight_energy(3.0)

func _start_dissolve() -> void:
	if _is_dissolving:
		return
	_is_dissolving = true
	current_state = State.DISSOLVED

	var tween := create_tween()
	tween.set_parallel(true)
	if _headlight_left:
		tween.tween_property(_headlight_left, "light_energy", 0.0, 1.2)
	if _headlight_right:
		tween.tween_property(_headlight_right, "light_energy", 0.0, 1.2)
	if _lens_left_mat:
		tween.tween_property(_lens_left_mat, "emission_energy_multiplier", 0.0, 1.2)
	if _lens_right_mat:
		tween.tween_property(_lens_right_mat, "emission_energy_multiplier", 0.0, 1.2)
	tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 1.2)
	tween.chain().tween_callback(queue_free)

func _set_headlight_energy(val: float) -> void:
	if _headlight_left and not _is_dissolving:
		_headlight_left.light_energy = val
	if _headlight_right and not _is_dissolving:
		_headlight_right.light_energy = val

func _set_headlight_visible(vis: bool) -> void:
	if _headlight_left and not _is_dissolving:
		_headlight_left.visible = vis
	if _headlight_right and not _is_dissolving:
		_headlight_right.visible = vis
	if _lens_left_mat:
		_lens_left_mat.emission_energy_multiplier = 6.0 if vis else 0.5
	if _lens_right_mat:
		_lens_right_mat.emission_energy_multiplier = 6.0 if vis else 0.5

func _broadcast_stalker_alert() -> void:
	if _signaled_radio:
		return
	_signaled_radio = true
	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[RADIO 10-0] <<! UNIDENTIFIED REAR PURSUIT VEHICLE DETECTED !>> ...AGGRESSIVE HIGH BEAMS CLOSING FAST...",
			5.5,
			true
		)
