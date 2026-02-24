extends MultiMeshInstance3D

const FISH_SCHOOLING = preload("res://compute-shaders/fish-schooling.glsl")
@export var dist:Vector3 = Vector3(5.0, 2.5, 2.5)
var half_dist:Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	half_dist = dist / 2.0
	for i in range(self.multimesh.instance_count):
		var position = Transform3D()
		position = position.translated(Vector3(randf() * dist.x - half_dist.x, randf() * dist.y - half_dist.y, randf() * dist.z - half_dist.z))
		self.multimesh.set_instance_transform(i, position)
		self.multimesh.set_instance_custom_data(i, Color(randf(), randf(), randf(), randf()))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
