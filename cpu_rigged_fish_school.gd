extends Node3D

@onready var world_scene: Node = $"../World_Scene"
const SPINE_FISH_RIGGED = preload("res://Fish/spine_fish_rigged.tscn")

var boids_cohesion:float = 1.0
var boids_alignment:float = 1.0
var boids_seperation:float = 1.8
@export var dist:Vector3 = Vector3(8.0, 5.0, 5.0)
var half_dist:Vector3
@export var instance_count:int = 1024
var fish_nodes:Array[Node3D] = []

# initialize all fish
func _ready() -> void:
	fish_nodes.resize(instance_count)
	for i in range(instance_count):
		var transform_matrix := Transform3D()
		var location:Vector3 = Vector3(randf() * dist.x - half_dist.x, randf() * dist.y - half_dist.y, randf() * dist.z - half_dist.z)
		#var location := Vector3.UP
		var direction:Vector3 = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		transform_matrix = transform_matrix.looking_at(direction + location, Vector3.UP, true)
		transform_matrix = transform_matrix.translated(location)
		var fish:Node3D = SPINE_FISH_RIGGED.instantiate()
		fish_nodes[i] = fish
		self.add_child(fish)
		fish.transform = transform_matrix
		var rate:float = 2.5
		fish.play_anim(rate)

# run an update each physics tick
func _process(delta: float) -> void:
	world_scene.set_instance_count_text(instance_count)
	__update_instances(delta)

func __update_instances(delta: float) -> void:
	var avg_pos:Vector3 = Vector3.ZERO
	var avg_dir:Vector3 = Vector3.ZERO
	# calculate average position and direction
	for i in range(instance_count):
		# add position
		avg_pos += fish_nodes[i].transform.origin
		# add direction
		avg_dir += fish_nodes[i].transform.basis.z
	# normalize
	avg_pos /= instance_count
	avg_dir /= sqrt(avg_dir.dot(avg_dir) + 0.001)
	
	# update each fish
	for i in range(instance_count):
		var target_dir:Vector3 = (world_scene.target.position - fish_nodes[i].transform.origin).normalized()
		var cohesion:Vector3 = boids_cohesion * (avg_pos - fish_nodes[i].transform.origin).normalized()
		var alignment:Vector3 = boids_alignment * avg_dir
		var seperation:Vector3 = Vector3.ZERO
		# calculate separation from all other fish within test radius
		for j in range(instance_count):
			if i == j:
				continue # skip this fish
			var sep:Vector3 = fish_nodes[i].transform.origin - fish_nodes[j].transform.origin
			var sep_len:float = sep.dot(sep)
			if sep_len < 5.0:
				seperation += sep / (sep_len + 0.001)
		seperation = boids_seperation * seperation.normalized()
		# calculate new velocity
		var velocity:Vector3 = fish_nodes[i].transform.basis.z * (1.0 - delta) + (target_dir + cohesion + alignment + seperation) * delta
		# apply calculated transform
		fish_nodes[i].transform = fish_nodes[i].transform.translated(velocity * delta)
		fish_nodes[i].transform = fish_nodes[i].transform.looking_at(fish_nodes[i].transform.origin + velocity, Vector3.UP, true)
