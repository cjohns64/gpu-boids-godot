extends MultiMeshInstance3D

@onready var world_scene: Node = $"../World_Scene"

var boids_cohesion:float = 1.0
var boids_alignment:float = 1.0
var boids_seperation:float = 1.8
@export var dist:Vector3 = Vector3(8.0, 5.0, 5.0)
var half_dist:Vector3

# initalize all fish
func _ready() -> void:
	for i in range(self.multimesh.instance_count):
		var transform_matrix := Transform3D()
		var location:Vector3 = Vector3(randf() * dist.x - half_dist.x, randf() * dist.y - half_dist.y, randf() * dist.z - half_dist.z)
		#var location := Vector3.UP
		var direction:Vector3 = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		transform_matrix = transform_matrix.looking_at(direction + location, Vector3.UP, true)
		transform_matrix = transform_matrix.translated(location)
		self.multimesh.set_instance_transform(i, transform_matrix)
		var rate:float = 0.5
		self.multimesh.set_instance_custom_data(i, Color(rate, randf(), randf(), randf()))

# run an update each physics tick
func _physics_process(delta: float) -> void:
	world_scene.set_instance_count_text(self.multimesh.instance_count)
	__update_instances(delta)

func __update_instances(delta: float) -> void:
	var avg_pos:Vector3 = Vector3.ZERO
	var avg_dir:Vector3 = Vector3.ZERO
	# calculate average position and direction
	for i in range(self.multimesh.instance_count):
		var transform_matrix:Transform3D = self.multimesh.get_instance_transform(i)
		# add position
		avg_pos += transform_matrix.origin
		# add direction
		avg_dir += transform_matrix.basis.z
	# normalize
	avg_pos /= self.multimesh.instance_count
	avg_dir /= sqrt(avg_dir.dot(avg_dir) + 0.001)
	
	# update each fish
	for i in range(self.multimesh.instance_count):
		var transform_matrix:Transform3D = self.multimesh.get_instance_transform(i)
		var target_dir:Vector3 = (world_scene.target.position - transform_matrix.origin).normalized()
		var cohesion:Vector3 = boids_cohesion * (avg_pos - transform_matrix.origin).normalized()
		var alignment:Vector3 = boids_alignment * avg_dir
		var seperation:Vector3 = Vector3.ZERO
		# calculate seperation from all other fish within test radius
		for j in range(self.multimesh.instance_count):
			if i == j:
				continue # skip this fish
			var sep:Vector3 = transform_matrix.origin - self.multimesh.get_instance_transform(j).origin
			var sep_len:float = sep.dot(sep)
			if sep_len < 5.0:
				seperation += sep / (sep_len + 0.001)
		seperation = boids_seperation * seperation.normalized()
		# calculate new velocity
		var velocity:Vector3 = transform_matrix.basis.z * (1.0 - delta) + (target_dir + cohesion + alignment + seperation) * delta
		# apply calculated transform
		transform_matrix = transform_matrix.translated(velocity * delta)
		transform_matrix = transform_matrix.looking_at(transform_matrix.origin + velocity, Vector3.UP, true)
		self.multimesh.set_instance_transform(i, transform_matrix)
