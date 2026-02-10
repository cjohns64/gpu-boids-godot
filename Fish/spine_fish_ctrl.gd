extends Node3D

@onready var retopo: MeshInstance3D = $retopo
var swim_rate:float = 2.0
var last:float = 2.0
var tween:Tween
var t:float = 0.0

func __set_swim_rate__(rate:float) -> void:
	if rate > 20.0:
		swim_rate = 20.0
	if rate < 2.0:
		swim_rate = 2.0
	if rate >= 2.0 and rate <= 20.0:
		retopo.mesh.surface_get_material(0).set_shader_parameter("rate", rate)
		swim_rate = rate
	else:
		retopo.mesh.surface_get_material(0).set_shader_parameter("rate", swim_rate)

func _input(event):
	if event.is_action_pressed("Swim Faster"):
		tween = get_tree().create_tween().set_parallel(true)
		tween.tween_method(__set_swim_rate__, swim_rate, swim_rate + 2.0, 0.5)
	elif event.is_action_pressed("Swim Slower"):
		tween = get_tree().create_tween().set_parallel(true)
		tween.tween_method(__set_swim_rate__, swim_rate, swim_rate - 2.0, 0.5)
