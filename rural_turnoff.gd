class_name RuralTurnoff
extends Node3D

## Procedural dead-end rural dirt turnoff branching off Route 77 into the dense forest.
## Features a narrow dirt track tightly flanked by trees, an impassable fallen log blockade,
## and a narrative radio warning dispatch. Forces reverse driving to return to Route 77.

# Shared cached materials
static var _dirt_mat: StandardMaterial3D
static var _rut_mat: StandardMaterial3D
static var _bark_mat: StandardMaterial3D
static var _foliage_mat: StandardMaterial3D
static var _log_mat: StandardMaterial3D
static var _wood_post_mat: StandardMaterial3D
static var _reflector_red_mat: StandardMaterial3D
static var _culvert_mat: StandardMaterial3D

var _has_triggered_radio: bool = false
var static_body: StaticBody3D

static func _get_dirt_mat() -> StandardMaterial3D:
	if not _dirt_mat:
		_dirt_mat = StandardMaterial3D.new()
		# Unpaved damp forest dirt track
		_dirt_mat.albedo_color = Color(0.14, 0.11, 0.08, 1.0)
		_dirt_mat.roughness = 0.96
		_dirt_mat.metallic = 0.0
	return _dirt_mat

static func _get_rut_mat() -> StandardMaterial3D:
	if not _rut_mat:
		_rut_mat = StandardMaterial3D.new()
		# Depressed mud tire track ruts
		_rut_mat.albedo_color = Color(0.09, 0.07, 0.05, 1.0)
		_rut_mat.roughness = 0.98
		_rut_mat.metallic = 0.02
	return _rut_mat

static func _get_bark_mat() -> StandardMaterial3D:
	if not _bark_mat:
		_bark_mat = StandardMaterial3D.new()
		# Weathered dark pine bark
		_bark_mat.albedo_color = Color(0.16, 0.12, 0.09, 1.0)
		_bark_mat.roughness = 0.92
		_bark_mat.metallic = 0.0
	return _bark_mat

static func _get_foliage_mat() -> StandardMaterial3D:
	if not _foliage_mat:
		_foliage_mat = StandardMaterial3D.new()
		# Deep nocturnal pine needles
		_foliage_mat.albedo_color = Color(0.05, 0.12, 0.07, 1.0)
		_foliage_mat.roughness = 0.88
		_foliage_mat.metallic = 0.0
	return _foliage_mat

static func _apply_dither_fade(mat: StandardMaterial3D) -> StandardMaterial3D:
	if mat:
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		mat.distance_fade_min_distance = 55.0
		mat.distance_fade_max_distance = 75.0
	return mat

static func _get_log_mat() -> StandardMaterial3D:
	if not _log_mat:
		_log_mat = StandardMaterial3D.new()
		# Massive rotting fallen log with damp lichen
		_log_mat.albedo_color = Color(0.13, 0.10, 0.07, 1.0)
		_log_mat.roughness = 0.95
		_log_mat.metallic = 0.0
		_apply_dither_fade(_log_mat)
	return _log_mat

static func _get_wood_post_mat() -> StandardMaterial3D:
	if not _wood_post_mat:
		_wood_post_mat = StandardMaterial3D.new()
		_wood_post_mat.albedo_color = Color(0.24, 0.20, 0.16, 1.0)
		_wood_post_mat.roughness = 0.90
		_wood_post_mat.metallic = 0.0
		_apply_dither_fade(_wood_post_mat)
	return _wood_post_mat

static func _get_reflector_red_mat() -> StandardMaterial3D:
	if not _reflector_red_mat:
		_reflector_red_mat = StandardMaterial3D.new()
		_reflector_red_mat.albedo_color = Color(0.85, 0.08, 0.05, 1.0)
		_reflector_red_mat.emission_enabled = true
		_reflector_red_mat.emission = Color(0.92, 0.10, 0.05, 1.0)
		_reflector_red_mat.emission_energy_multiplier = 0.9
		_apply_dither_fade(_reflector_red_mat)
	return _reflector_red_mat

static func _get_culvert_mat() -> StandardMaterial3D:
	if not _culvert_mat:
		_culvert_mat = StandardMaterial3D.new()
		_culvert_mat.albedo_color = Color(0.22, 0.23, 0.25, 1.0)
		_culvert_mat.roughness = 0.72
		_culvert_mat.metallic = 0.35
		_apply_dither_fade(_culvert_mat)
	return _culvert_mat

## Builds the complete dirt turnoff including track slices, tree walls, entrance culvert, and dead end blockade.
func build_turnoff(total_length: float = 62.0, track_width: float = 4.2) -> void:
	static_body = StaticBody3D.new()
	static_body.name = "TurnoffStaticBody"
	add_child(static_body)

	var dirt_mat := _get_dirt_mat()
	var rut_mat := _get_rut_mat()

	# 1. Entrance culvert ramp bridging the roadside ditch onto the dirt path
	_build_entrance_ramp(track_width)

	# 2. Dirt track segments with physical ground collision and wheel rut geometry
	var slice_len: float = 6.0
	var num_slices: int = int(ceil(total_length / slice_len))

	for s in range(num_slices):
		var slice_z: float = -(float(s) * slice_len + (slice_len * 0.5))

		# Driveable ground slab
		var ground_mesh := BoxMesh.new()
		ground_mesh.size = Vector3(track_width, 0.6, slice_len + 0.2)
		ground_mesh.material = dirt_mat

		var ground_inst := MeshInstance3D.new()
		ground_inst.name = "GroundSliceMesh_%d" % s
		ground_inst.mesh = ground_mesh
		ground_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, slice_z))
		static_body.add_child(ground_inst)

		var ground_col := CollisionShape3D.new()
		ground_col.name = "GroundSliceCol_%d" % s
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(track_width, 0.6, slice_len + 0.2)
		ground_col.shape = col_shape
		ground_col.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, slice_z))
		static_body.add_child(ground_col)

		# Left and right sunken mud tire ruts
		for side in [-1.0, 1.0]:
			var rut_mesh := BoxMesh.new()
			rut_mesh.size = Vector3(0.48, 0.03, slice_len + 0.2)
			rut_mesh.material = rut_mat

			var rut_inst := MeshInstance3D.new()
			rut_inst.name = "RutMesh_%d_%s" % [s, "L" if side < 0 else "R"]
			rut_inst.mesh = rut_mesh
			rut_inst.transform = Transform3D(Basis.IDENTITY, Vector3(side * 1.05, 0.015, slice_z))
			static_body.add_child(rut_inst)

		# Shoulder / loose surface drag trigger area
		var drag_area := Area3D.new()
		drag_area.name = "TurnoffDragArea_%d" % s
		drag_area.collision_layer = 0
		drag_area.collision_mask = 1
		var drag_col := CollisionShape3D.new()
		var drag_box := BoxShape3D.new()
		drag_box.size = Vector3(track_width, 1.8, slice_len)
		drag_col.shape = drag_box
		drag_area.add_child(drag_col)
		drag_area.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, slice_z))
		drag_area.body_entered.connect(_on_turnoff_surface_entered)
		drag_area.body_exited.connect(_on_turnoff_surface_exited)
		add_child(drag_area)

	# 3. Flanking pine tree walls (leaving ~4.4m clearance, physically preventing 4.0m van U-turns)
	var tree_step: float = 3.6
	var tree_count: int = int((total_length - 8.0) / tree_step)
	var tree_lateral_dist: float = (track_width * 0.5) + 0.35 # ~2.45m from center

	for t in range(tree_count):
		var tree_z: float = -4.0 - (float(t) * tree_step)
		# Left tree
		_build_flanking_tree(-tree_lateral_dist, tree_z, t * 2)
		# Right tree
		_build_flanking_tree(tree_lateral_dist, tree_z, (t * 2) + 1)

	# 4. Entrance rustic road marker sign
	_build_entrance_marker_sign(track_width)

	# 5. Narrative radio warning trigger area (~10m past the fork)
	_build_radio_trigger_area()

	# 6. Impassable dead-end physical blockade at terminus (~60m)
	_build_terminus_blockade(total_length, track_width)

## Constructs a smooth dirt ramp and drainage culvert bridging the highway ditch.
func _build_entrance_ramp(track_width: float) -> void:
	var dirt_mat := _get_dirt_mat()
	var culvert_mat := _get_culvert_mat()

	# Transitional dirt wedge extending 5.5m behind the fork origin into the road shoulder
	var ramp_mesh := BoxMesh.new()
	ramp_mesh.size = Vector3(track_width + 1.2, 0.6, 6.0)
	ramp_mesh.material = dirt_mat

	var ramp_inst := MeshInstance3D.new()
	ramp_inst.name = "EntranceRampMesh"
	ramp_inst.mesh = ramp_mesh
	ramp_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, 2.5))
	static_body.add_child(ramp_inst)

	var ramp_col := CollisionShape3D.new()
	ramp_col.name = "EntranceRampCol"
	var ramp_box := BoxShape3D.new()
	ramp_box.size = Vector3(track_width + 1.2, 0.6, 6.0)
	ramp_col.shape = ramp_box
	ramp_col.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, 2.5))
	static_body.add_child(ramp_col)

	# Corrugated drainage culvert pipe under the entrance
	var culvert_mesh := CylinderMesh.new()
	culvert_mesh.top_radius = 0.42
	culvert_mesh.bottom_radius = 0.42
	culvert_mesh.height = track_width + 2.0
	culvert_mesh.material = culvert_mat

	var culvert_inst := MeshInstance3D.new()
	culvert_inst.name = "CulvertPipeMesh"
	culvert_inst.mesh = culvert_mesh
	var culvert_rot := Basis(Vector3.FORWARD, deg_to_rad(90.0))
	culvert_inst.transform = Transform3D(culvert_rot, Vector3(0.0, -0.85, 2.5))
	static_body.add_child(culvert_inst)

## Builds a solid pine tree with cylinder collision along the borders.
func _build_flanking_tree(local_x: float, local_z: float, idx: int) -> void:
	var bark_mat := _get_bark_mat()
	var foliage_mat := _get_foliage_mat()

	# Deterministic pseudo-random variation per tree
	var tree_seed: int = idx * 1337 + 42
	var s: float = 0.75 + (float((tree_seed ^ 0x5555) % 100) / 100.0) * 0.60 # 0.75x to 1.35x
	var yaw: float = (float((tree_seed * 73) % 360) / 180.0) * PI
	var stagger_x: float = ((float((tree_seed * 19) % 100) / 100.0) - 0.3) * 0.6 # Stagger slightly outward
	var final_x: float = local_x + (stagger_x if local_x > 0.0 else -stagger_x)
	var stagger_z: float = ((float((tree_seed * 31) % 100) / 100.0) - 0.5) * 1.0
	var final_z: float = local_z + stagger_z

	var tree_visual := Node3D.new()
	tree_visual.name = "TreeVisual_%d" % idx
	tree_visual.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(final_x, 0.0, final_z))
	static_body.add_child(tree_visual)

	# Trunk mesh
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 7.5
	trunk_mesh.material = bark_mat

	var trunk_inst := MeshInstance3D.new()
	trunk_inst.name = "TreeTrunk"
	trunk_inst.mesh = trunk_mesh
	trunk_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 3.5, 0.0))
	tree_visual.add_child(trunk_inst)

	# Solid trunk physical collision shape (directly on static_body for proper collision detection)
	var trunk_col := CollisionShape3D.new()
	trunk_col.name = "TreeCol_%d" % idx
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 0.32 * s
	cyl_shape.height = 7.5 * s
	trunk_col.shape = cyl_shape
	trunk_col.transform = Transform3D(Basis.IDENTITY, Vector3(final_x, 3.5 * s, final_z))
	static_body.add_child(trunk_col)

	# Tiered pine foliage cones
	var tier_heights: Array[float] = [3.2, 4.8, 6.2]
	var tier_radii: Array[float] = [1.45, 1.15, 0.85]

	for tier in range(3):
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.05
		cone_mesh.bottom_radius = tier_radii[tier]
		cone_mesh.height = 2.2
		cone_mesh.material = foliage_mat

		var cone_inst := MeshInstance3D.new()
		cone_inst.name = "TreeFoliage_%d" % tier
		cone_inst.mesh = cone_mesh
		cone_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, tier_heights[tier], 0.0))
		tree_visual.add_child(cone_inst)

## Constructs a tilted wooden signpost with a red warning reflector at the turnoff mouth.
func _build_entrance_marker_sign(track_width: float) -> void:
	var post_mat := _get_wood_post_mat()
	var reflector_mat := _get_reflector_red_mat()

	var sign_x: float = (track_width * 0.5) + 0.65
	var sign_z: float = 0.8

	# Weathered wooden post
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.18, 2.2, 0.18)
	post_mesh.material = post_mat

	var post_inst := MeshInstance3D.new()
	post_inst.name = "EntranceSignPost"
	post_inst.mesh = post_mesh
	var post_rot := Basis(Vector3.FORWARD, deg_to_rad(6.0))
	post_inst.transform = Transform3D(post_rot, Vector3(sign_x, 1.0, sign_z))
	static_body.add_child(post_inst)

	# Rustic warning placard board
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(0.95, 0.42, 0.06)
	board_mesh.material = post_mat

	var board_inst := MeshInstance3D.new()
	board_inst.name = "EntranceSignBoard"
	board_inst.mesh = board_mesh
	var board_rot := Basis(Vector3.UP, deg_to_rad(15.0)) * Basis(Vector3.FORWARD, deg_to_rad(8.0))
	board_inst.transform = Transform3D(board_rot, Vector3(sign_x, 1.7, sign_z))
	static_body.add_child(board_inst)

	# Red square warning reflector
	var ref_mesh := BoxMesh.new()
	ref_mesh.size = Vector3(0.22, 0.22, 0.04)
	ref_mesh.material = reflector_mat

	var ref_inst := MeshInstance3D.new()
	ref_inst.name = "EntranceSignReflector"
	ref_inst.mesh = ref_mesh
	ref_inst.transform = Transform3D(Basis.IDENTITY, Vector3(sign_x, 1.7, sign_z + 0.05))
	static_body.add_child(ref_inst)

## Builds an Area3D trigger that broadcasts a narrative radio dispatch upon entering the track.
func _build_radio_trigger_area() -> void:
	var trigger_area := Area3D.new()
	trigger_area.name = "NarrativeRadioTrigger"
	trigger_area.collision_layer = 0
	trigger_area.collision_mask = 1

	var trigger_col := CollisionShape3D.new()
	var trigger_box := BoxShape3D.new()
	trigger_box.size = Vector3(6.0, 3.5, 4.0)
	trigger_col.shape = trigger_box
	trigger_area.add_child(trigger_col)

	trigger_area.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, -11.0))
	trigger_area.body_entered.connect(_on_radio_trigger_entered)
	add_child(trigger_area)

## Constructs a massive impassable fallen tree trunk, collapsed gate, and glowing red reflector at terminus.
func _build_terminus_blockade(total_length: float, track_width: float) -> void:
	var log_mat := _get_log_mat()
	var post_mat := _get_wood_post_mat()
	var reflector_mat := _get_reflector_red_mat()

	var term_z: float = -total_length + 2.5

	# 1. Massive horizontal fallen log trunk spanning the entire path width
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.58
	trunk_mesh.bottom_radius = 0.72
	trunk_mesh.height = track_width + 2.5
	trunk_mesh.material = log_mat

	var trunk_inst := MeshInstance3D.new()
	trunk_inst.name = "TerminusFallenLogMesh"
	trunk_inst.mesh = trunk_mesh
	var trunk_rot := Basis(Vector3.FORWARD, deg_to_rad(90.0)) * Basis(Vector3.UP, deg_to_rad(4.0))
	trunk_inst.transform = Transform3D(trunk_rot, Vector3(0.0, 0.65, term_z))
	static_body.add_child(trunk_inst)

	# Heavy solid obstacle collision on fallen log
	var log_col := CollisionShape3D.new()
	log_col.name = "TerminusFallenLogCol"
	var log_box := BoxShape3D.new()
	log_box.size = Vector3(track_width + 2.5, 2.0, 1.6)
	log_col.shape = log_box
	log_col.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, term_z))
	static_body.add_child(log_col)
	static_body.add_to_group("heavy_obstacle")

	# Broken splintered branches protruding from the log
	for side in [-1.4, 1.4]:
		var branch_mesh := CylinderMesh.new()
		branch_mesh.top_radius = 0.10
		branch_mesh.bottom_radius = 0.18
		branch_mesh.height = 2.4
		branch_mesh.material = log_mat

		var branch_inst := MeshInstance3D.new()
		branch_inst.name = "SplinterBranch_%s" % ("L" if side < 0 else "R")
		branch_inst.mesh = branch_mesh
		var branch_rot := Basis(Vector3.RIGHT, deg_to_rad(-35.0)) * Basis(Vector3.FORWARD, deg_to_rad(side * 20.0))
		branch_inst.transform = Transform3D(branch_rot, Vector3(side, 1.4, term_z - 0.4))
		static_body.add_child(branch_inst)

	# 2. Collapsed old forestry barrier gate posts
	for side in [-1.0, 1.0]:
		var gate_post_mesh := BoxMesh.new()
		gate_post_mesh.size = Vector3(0.24, 1.8, 0.24)
		gate_post_mesh.material = post_mat

		var gate_post_inst := MeshInstance3D.new()
		gate_post_inst.name = "GatePost_%s" % ("L" if side < 0 else "R")
		gate_post_inst.mesh = gate_post_mesh
		var post_tilt := Basis(Vector3.FORWARD, deg_to_rad(side * 12.0))
		gate_post_inst.transform = Transform3D(post_tilt, Vector3(side * 1.85, 0.85, term_z + 1.2))
		static_body.add_child(gate_post_inst)

	# Broken crossbeam plank resting against the fallen trunk
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(2.8, 0.16, 0.08)
	plank_mesh.material = post_mat

	var plank_inst := MeshInstance3D.new()
	plank_inst.name = "BrokenGatePlank"
	plank_inst.mesh = plank_mesh
	var plank_rot := Basis(Vector3.FORWARD, deg_to_rad(-18.0)) * Basis(Vector3.UP, deg_to_rad(10.0))
	plank_inst.transform = Transform3D(plank_rot, Vector3(0.0, 0.9, term_z + 0.9))
	static_body.add_child(plank_inst)

	# 3. High-visibility red warning reflector mounted on the barricade log
	var term_ref_mesh := BoxMesh.new()
	term_ref_mesh.size = Vector3(0.65, 0.45, 0.06)
	term_ref_mesh.material = reflector_mat

	var term_ref_inst := MeshInstance3D.new()
	term_ref_inst.name = "TerminusWarningReflector"
	term_ref_inst.mesh = term_ref_mesh
	term_ref_inst.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, term_z + 0.8))
	static_body.add_child(term_ref_inst)

func _on_turnoff_surface_entered(body: Node3D) -> void:
	if body.has_method("enter_shoulder_zone"):
		body.enter_shoulder_zone()

func _on_turnoff_surface_exited(body: Node3D) -> void:
	if body.has_method("exit_shoulder_zone"):
		body.exit_shoulder_zone()

func _on_radio_trigger_entered(body: Node3D) -> void:
	if _has_triggered_radio:
		return
	if not (body.is_in_group("player") or body.name == "Van"):
		return

	_has_triggered_radio = true
	if RadioManager.instance:
		RadioManager.instance.broadcast_dispatch(
			"[DISPATCH 10-20] ...Unit 77, telemetry lost main road vector... old forestry track is a dead end... reverse out to Route 77 immediately...",
			8.0,
			false
		)
