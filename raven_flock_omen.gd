class_name RavenFlockOmen
extends Area3D

var _is_dispersed: bool = false
var _ravens: Array[Node3D] = []
var _scatter_dirs: Array[Vector3] = []
var _time: float = 0.0
var _scatter_elapsed: float = 0.0
var _omen_light: OmniLight3D = null

static var _feathers_mat: StandardMaterial3D
static var _eye_mat: StandardMaterial3D

static func _get_feathers_mat() -> StandardMaterial3D:
	if not _feathers_mat:
		_feathers_mat = StandardMaterial3D.new()
		_feathers_mat.albedo_color = Color(0.02, 0.02, 0.028, 1.0)
		_feathers_mat.roughness = 0.72
		_feathers_mat.metallic = 0.15
	return _feathers_mat

static func _get_eye_mat() -> StandardMaterial3D:
	if not _eye_mat:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.albedo_color = Color(1.0, 0.06, 0.06, 1.0)
		_eye_mat.emission_enabled = true
		_eye_mat.emission = Color(1.0, 0.04, 0.04, 1.0)
		_eye_mat.emission_energy_multiplier = 4.8
	return _eye_mat

func _ready() -> void:
	add_to_group("omen_flock")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.8, 2.5, 4.8)
	col.shape = shape
	col.position = Vector3(0.0, 1.2, 0.0)
	add_child(col)

	_omen_light = OmniLight3D.new()
	_omen_light.name = "OmenCrimsonGlow"
	_omen_light.position = Vector3(0.0, 0.75, 0.0)
	_omen_light.light_color = Color(0.95, 0.12, 0.14, 1.0)
	_omen_light.light_energy = 2.4
	_omen_light.omni_range = 8.5
	_omen_light.omni_attenuation = 1.2
	add_child(_omen_light)

	_build_raven_cluster()
	body_entered.connect(_on_body_entered)

func _build_raven_cluster() -> void:
	var feathers := _get_feathers_mat()
	var eyes := _get_eye_mat()
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.18, 0.0),
		Vector3(-1.1, 0.18, 0.65),
		Vector3(1.15, 0.18, -0.55),
		Vector3(-0.65, 0.20, -1.10),
		Vector3(0.75, 0.22, 1.05),
		Vector3(-1.55, 0.45, -0.35),
		Vector3(1.45, 0.52, 0.40),
		Vector3(0.15, 0.85, -0.45)
	]

	for i in range(offsets.size()):
		var raven := Node3D.new()
		raven.name = "Raven_%d" % i
		raven.position = offsets[i]
		raven.rotation.y = randf_range(-0.45, 0.45)

		var body_mesh := BoxMesh.new()
		body_mesh.size = Vector3(0.22, 0.18, 0.46)
		body_mesh.material = feathers
		var body_inst := MeshInstance3D.new()
		body_inst.mesh = body_mesh
		raven.add_child(body_inst)

		# Wings
		for w_sign in [-1.0, 1.0]:
			var wing_mesh := BoxMesh.new()
			wing_mesh.size = Vector3(0.38, 0.03, 0.24)
			wing_mesh.material = feathers
			var wing_inst := MeshInstance3D.new()
			wing_inst.name = "WingL" if w_sign < 0.0 else "WingR"
			wing_inst.mesh = wing_mesh
			wing_inst.position = Vector3(w_sign * 0.24, 0.04, 0.0)
			wing_inst.rotation.z = w_sign * 0.22
			raven.add_child(wing_inst)

		# Glowing red eyes facing oncoming van (+Z)
		for e_sign in [-1.0, 1.0]:
			var eye_mesh := BoxMesh.new()
			eye_mesh.size = Vector3(0.045, 0.045, 0.045)
			eye_mesh.material = eyes
			var eye_inst := MeshInstance3D.new()
			eye_inst.mesh = eye_mesh
			eye_inst.position = Vector3(e_sign * 0.065, 0.08, 0.23)
			raven.add_child(eye_inst)

		add_child(raven)
		_ravens.append(raven)
		_scatter_dirs.append(Vector3(randf_range(-1.0, 1.0), randf_range(1.1, 1.8), randf_range(-1.0, 1.0)).normalized())

func _process(delta: float) -> void:
	_time += delta * 14.0
	if _is_dispersed:
		_scatter_elapsed += delta
		for i in range(_ravens.size()):
			var r := _ravens[i]
			if is_instance_valid(r):
				r.position += _scatter_dirs[i] * (16.5 * delta)
				r.rotation.y += 4.5 * delta
				var wl := r.get_node_or_null("WingL") as Node3D
				var wr := r.get_node_or_null("WingR") as Node3D
				var flap := sin(_time * 2.4 + float(i)) * 0.75
				if wl:
					wl.rotation.z = flap
				if wr:
					wr.rotation.z = -flap
		if _omen_light:
			_omen_light.light_energy = move_toward(_omen_light.light_energy, 0.0, 6.0 * delta)
		if _scatter_elapsed >= 1.6:
			queue_free()
	else:
		# Subtle idle wing twitching & Bobbing
		for i in range(_ravens.size()):
			var r := _ravens[i]
			if is_instance_valid(r):
				var wl := r.get_node_or_null("WingL") as Node3D
				var wr := r.get_node_or_null("WingR") as Node3D
				var flap := sin(_time * 0.65 + float(i) * 1.3) * 0.25
				if wl:
					wl.rotation.z = flap
				if wr:
					wr.rotation.z = -flap

func disperse_by_horn() -> bool:
	if _is_dispersed:
		return false
	_is_dispersed = true
	set_deferred("monitoring", false)
	return true

func _on_body_entered(body: Node3D) -> void:
	if _is_dispersed:
		return
	if body is Van:
		_is_dispersed = true
		set_deferred("monitoring", false)
		var van := body as Van
		van.apply_collision_damage(9.5, false)
		van.trigger_threat_glitch()
		if RadioManager.instance:
			RadioManager.instance.broadcast_dispatch(
				"[IMPACTO DE CUERVOS] ¡La bandada golpeó el parabrisas! Usa el CLAXON [X] para ahuyentarlos antes de chocar.",
				5.5,
				true,
				0.75
			)
