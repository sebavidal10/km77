class_name AbandonedCar
extends StaticBody3D

const RadioManager = preload("res://radio_manager.gd")
const Van = preload("res://van.gd")

@export_group("Interior Lighting")
## Whether the interior dome light is still flickering or completely dead.
@export var is_dome_light_flickering: bool = true
## Base illumination energy of the dying dome light bulb.
@export var base_dome_energy: float = 0.75

@onready var dome_light: OmniLight3D = $DomeLight
@onready var door_pivot: Node3D = $DoorPivot
@onready var proximity_area: Area3D = $ProximityArea

var _reported_narrative: bool = false
var _flicker_noise: float = 0.0

func _ready() -> void:
	add_to_group("heavy_obstacle")
	collision_layer = 1
	collision_mask = 1

	if proximity_area:
		proximity_area.body_entered.connect(_on_proximity_entered)

	# 35% chance the dome light battery is completely dead
	if randf() < 0.35:
		is_dome_light_flickering = false
		if dome_light:
			dome_light.visible = false
			dome_light.light_energy = 0.0

func _process(delta: float) -> void:
	if not is_dome_light_flickering or not dome_light:
		return

	_flicker_noise += delta * 12.0
	var flicker := (sin(_flicker_noise * 1.7) * 0.35) + randf_range(-0.35, 0.35)
	if randf() < 0.12:
		# Rapid brownout dropout
		dome_light.light_energy = 0.05
	else:
		dome_light.light_energy = clampf(base_dome_energy + flicker * 0.45, 0.1, 1.2)

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
