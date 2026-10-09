class_name FlickerLight
extends OmniLight3D

@export_group("Flicker Settings")
## Base target light energy when fully lit.
@export var base_energy: float = 2.2
## Minimum energy during a brownout or electrical dip.
@export var min_energy: float = 0.15
## Probability (0.0 to 1.0) per tick of experiencing a flicker or dip.
@export var flicker_probability: float = 0.35
## Enables erratic electrical flickering behavior.
@export var is_flickering: bool = true

var _timer: float = 0.0
var _interval: float = 0.08
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	if not is_flickering:
		light_energy = base_energy
		set_process(false)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _interval:
		_timer = 0.0
		_interval = _rng.randf_range(0.04, 0.18)

		if _rng.randf() < flicker_probability:
			var roll := _rng.randf()
			if roll < 0.3:
				# Total momentary power cutout
				light_energy = 0.0
			elif roll < 0.7:
				# Voltage drop / weak buzz
				light_energy = _rng.randf_range(min_energy, base_energy * 0.45)
			else:
				# High voltage surge spike
				light_energy = base_energy * 1.4
		else:
			light_energy = base_energy
