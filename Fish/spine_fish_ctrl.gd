extends Node3D

@onready var retopo: MeshInstance3D = $retopo

func set_swim_rate(rate:float) -> void:
	var r:float = rate
	if rate < 2.0:
		r = 2.0
	elif rate > 20.0:
		r = 20.0
	print(retopo.mesh.surface_get_material(0).get_shader_parameter("rate"))
	retopo.mesh.surface_get_material(0).set_shader_parameter("rate", r)
	print(retopo.mesh.surface_get_material(0).get_shader_parameter("rate"))

func _input(event):
	if event.is_action_pressed("Swim Faster"):
		set_swim_rate(15.0)
	elif event.is_action_pressed("Swim Slower"):
		set_swim_rate(2.0)
