class_name MainMenu
extends Control

@onready var start_button: Button = %StartButton
@onready var exit_button: Button = %ExitButton
@onready var fade_rect: ColorRect = %FadeRect

var _is_starting: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)

	if fade_rect:
		fade_rect.visible = true
		fade_rect.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_property(fade_rect, "modulate:a", 0.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func(): fade_rect.visible = false)

func _on_start_pressed() -> void:
	if _is_starting:
		return
	_is_starting = true

	if start_button:
		start_button.disabled = true
	if exit_button:
		exit_button.disabled = true

	if fade_rect:
		fade_rect.visible = true
		var tween := create_tween()
		tween.tween_property(fade_rect, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_callback(_launch_game)
	else:
		_launch_game()

func _launch_game() -> void:
	get_tree().change_scene_to_file("res://world.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
