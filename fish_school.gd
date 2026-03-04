extends MultiMeshInstance3D

const FISH_SCHOOLING = preload("res://compute-shaders/fish-schooling.glsl")
@export var dist:Vector3 = Vector3(8.0, 5.0, 5.0)
var half_dist:Vector3
@onready var target: Node3D = $"../Target"

# Reference to the active Rendering Device
# This is Godot's abstraction of GLSL, objects will interface with it using RIDs
var rd:RenderingDevice
# Reference for the loaded shader
var shader:RID
# Reference to the compute pipeline
var pipeline:RID
# References to storage buffers
var buffers:Array[RID] = []
const NUM_UNIF:int = 7

class FishData:
	var priorites:Array[float]
	var mask:Array[float]
	var target:Vector3
	var positions:Array[Vector3]
	var directions:Array[Vector3]
	var boids:Array[Vector3]
	var rates:Array[float]
	
	func _init(size:int) -> void:
		priorites.resize(size)
		mask.resize(size)
		positions.resize(size)
		directions.resize(size)
		boids.resize(size)
		rates.resize(size)

var data:FishData

func __init_compute() -> void:
	# Setup the reference to the Rendering Device
	rd = RenderingServer.create_local_rendering_device()
	# Load GLSL shader
	shader = rd.shader_create_from_spirv(FISH_SCHOOLING.get_spirv())
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)
	buffers.resize(NUM_UNIF)

func __setup_compute_step() -> void:
	# priority		s0 b0 float
	# mask			s0 b1 float
	# target		s0 b2 vec3
	# coeff			s0 b3 vec3
	# position		s1 b4 vec3
	# rate			s1 b5 float
	# direction		s1 b6 vec3

	var priorities_bytes: PackedByteArray = PackedFloat32Array(data.priorites).to_byte_array()
	var compute_bytes: PackedByteArray = PackedFloat32Array(data.mask).to_byte_array()
	var target_bytes:PackedByteArray = PackedVector3Array([data.target]).to_byte_array()
	var boids_bytes: PackedByteArray = PackedVector3Array(data.boids).to_byte_array()
	var position_bytes: PackedByteArray = PackedVector3Array(data.positions).to_byte_array()
	var rate_bytes: PackedByteArray = PackedFloat32Array(data.rates).to_byte_array()
	var direction_bytes: PackedByteArray = PackedVector3Array(data.directions).to_byte_array()

	# Create the storage buffers
	buffers[0] = rd.storage_buffer_create(priorities_bytes.size(), priorities_bytes)
	buffers[1] = rd.storage_buffer_create(compute_bytes.size(), compute_bytes)
	buffers[2] = rd.storage_buffer_create(target_bytes.size(), target_bytes)
	buffers[3] = rd.storage_buffer_create(boids_bytes.size(), boids_bytes)
	buffers[4] = rd.storage_buffer_create(position_bytes.size(), position_bytes)
	buffers[5] = rd.storage_buffer_create(rate_bytes.size(), rate_bytes)
	buffers[6] = rd.storage_buffer_create(direction_bytes.size(), direction_bytes)

func __compute_school() -> void:
	# Create a uniform for each buffer
	var uniforms:Array[RDUniform] = [];
	uniforms.resize(NUM_UNIF)
	for i in NUM_UNIF:
		uniforms[i] = RDUniform.new()
		uniforms[i].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniforms[i].binding = i # this needs to match the "binding" in the shader file
		uniforms[i].add_id(buffers[i])
	
	# the last parameter needs to match the "set" in the shader file
	var set_id_0:RID = rd.uniform_set_create([uniforms[0], uniforms[1], uniforms[2], uniforms[3]], shader, 0)
	var set_id_1:RID = rd.uniform_set_create([uniforms[4], uniforms[5], uniforms[6]], shader, 1)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, set_id_0, 0)
	rd.compute_list_bind_uniform_set(compute_list, set_id_1, 1)
	# dispatch vector will be multiplied by the layout vector in shader for total calls
	rd.compute_list_dispatch(compute_list, 1, 1, 1) # one dispatch
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	# Read back the data from the buffer
	var new_pos_bytes:PackedByteArray = rd.buffer_get_data(buffers[4])
	var new_pos:PackedVector3Array = new_pos_bytes.to_vector3_array()
	var new_rate_bytes:PackedByteArray = rd.buffer_get_data(buffers[5])
	var new_rate:PackedFloat32Array = new_rate_bytes.to_float32_array()
	var new_dir_bytes:PackedByteArray = rd.buffer_get_data(buffers[6])
	#print(new_dir_bytes.size())
	var new_dir:PackedVector3Array = new_dir_bytes.to_vector3_array()
	#print(new_dir.size())
	for i in range(self.multimesh.instance_count):
		var transform_matrix:Transform3D = self.multimesh.get_instance_transform(i)
		# move to new position
		transform_matrix = transform_matrix.translated(new_pos[i] - data.positions[i])
		# look at new pointing direction
		transform_matrix = transform_matrix.looking_at(new_dir[i] + data.positions[i], Vector3.UP, true)
		self.multimesh.set_instance_transform(i, transform_matrix)
		# update position, rate, and direction
		data.positions[i] = new_pos[i]
		data.rates[i] = new_rate[i]
		data.directions[i] = new_dir[i]

	# free local RIDs
	rd.free_rid(set_id_0)
	rd.free_rid(set_id_1)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	data = FishData.new(self.multimesh.instance_count)
	# place the initial distrubition of fish
	half_dist = dist / 2.0
	for i in range(self.multimesh.instance_count):
		var transform_matrix = Transform3D()
		var location:Vector3 = Vector3(randf() * dist.x - half_dist.x, randf() * dist.y - half_dist.y, randf() * dist.z - half_dist.z)
		#var location := Vector3.UP
		var direction:Vector3 = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		transform_matrix = transform_matrix.looking_at(direction + location, Vector3.UP, true)
		transform_matrix = transform_matrix.translated(location)
		self.multimesh.set_instance_transform(i, transform_matrix)
		var rate:float = 0.5
		self.multimesh.set_instance_custom_data(i, Color(rate, randf(), randf(), randf()))
		# add fish to data
		data.positions[i] = location
		data.mask[i] = 1.0
		data.boids[i] = Vector3(1.0, 1.0, 1.5)
		data.priorites[i] = 1.0
		data.directions[i] = direction # forward direction
		data.rates[i] = rate
		
	# setup compute shader for calculating boids motion
	__init_compute()

func _physics_process(delta: float) -> void:
	data.target = target.position
	__setup_compute_step()
	__compute_school()

func _exit_tree() -> void:
	# remove persistent RIDs
	if not rd:
		return
	else:
		if pipeline: rd.free_rid(pipeline)
	for i in NUM_UNIF:
		rd.free_rid(buffers[i])
