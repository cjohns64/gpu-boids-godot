extends MultiMeshInstance3D

const FISH_SCHOOLING = preload("res://compute-shaders/fish-schooling.glsl")
@export var dist:Vector3 = Vector3(5.0, 2.5, 2.5)
var half_dist:Vector3

# Reference to the active Rendering Device
# This is Godot's abstraction of GLSL, objects will interface with it using RIDs
var rd:RenderingDevice
# Reference for the loaded shader
var shader:RID
# Reference to the compute pipeline
var pipeline:RID
# References to storage buffers
var buffers:Array[RID] = []
const NUM_UNIF:int = 6

# setup reused references
func _setup_compute() -> void:
	# Setup the reference to the Rendering Device
	rd = RenderingServer.create_local_rendering_device()
	# Load GLSL shader
	shader = rd.shader_create_from_spirv(FISH_SCHOOLING.get_spirv())
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)
	# priority:float - s0,b0
	# compute_mask:bool - s0,b1
	# target:vec3 - s0,b2
	# location:vec3 - s0,b3
	# boids:vec3 - s0,b4
	# direction:vec3 - s1,b5
	
	var priorities_bytes: PackedByteArray = PackedFloat32Array([0]).to_byte_array()
	var compute_bytes: PackedByteArray = PackedByteArray([false])
	var targets_bytes: PackedByteArray = PackedVector3Array([Vector3.ZERO]).to_byte_array()
	var location_bytes: PackedByteArray = PackedVector3Array([Vector3.ZERO]).to_byte_array()
	var boids_bytes: PackedByteArray = PackedVector3Array([Vector3.ZERO]).to_byte_array()
	var direction_bytes: PackedByteArray = PackedVector3Array([Vector3.ZERO]).to_byte_array()
	
	# Create the storage buffers
	buffers.resize(NUM_UNIF)
	buffers[0] = rd.storage_buffer_create(priorities_bytes.size(), priorities_bytes)
	buffers[1] = rd.storage_buffer_create(compute_bytes.size(), compute_bytes)
	buffers[2] = rd.storage_buffer_create(targets_bytes.size(), targets_bytes)
	buffers[3] = rd.storage_buffer_create(location_bytes.size(), location_bytes)
	buffers[4] = rd.storage_buffer_create(boids_bytes.size(), boids_bytes)
	buffers[5] = rd.storage_buffer_create(direction_bytes.size(), direction_bytes)

func _dir_update_callback(new_direction_data:PackedByteArray) -> void:
	var new_dir:Array[Vector3] = new_direction_data.to_vector3_array()
	pass

func compute_school() -> void:
	# TODO: build input data, apply output data, minimize data transfer

	# Create a uniform for each buffer
	var uniforms:Array[RDUniform] = [];
	uniforms.resize(NUM_UNIF)
	for i in NUM_UNIF:
		uniforms[i] = RDUniform.new()
		uniforms[i].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniforms[i].binding = i # this needs to match the "binding" in the shader file
		uniforms[i].add_id(buffers[i])
	
	# the last parameter needs to match the "set" in the shader file
	var set_id_0:RID = rd.uniform_set_create([uniforms[0], uniforms[1], uniforms[2], uniforms[3], uniforms[4]], shader, 0)
	var set_id_1:RID = rd.uniform_set_create([uniforms[5]], shader, 1)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, set_id_0, 0)
	rd.compute_list_bind_uniform_set(compute_list, set_id_1, 1)
	# dispatch vector will be multiplied by the layout vector in shader for total calls
	rd.compute_list_dispatch(compute_list, 1, 1, 1) # one dispatch
	rd.compute_list_end()
	
	# Submit to GPU
	rd.submit()
	
	# Read back the data from the buffer
	rd.buffer_get_data_async(buffers[5], _dir_update_callback)

	# free local RIDs
	rd.free_rid(set_id_0)
	rd.free_rid(set_id_1)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_setup_compute()
	half_dist = dist / 2.0
	for i in range(self.multimesh.instance_count):
		var position = Transform3D()
		position = position.translated(Vector3(randf() * dist.x - half_dist.x, randf() * dist.y - half_dist.y, randf() * dist.z - half_dist.z))
		self.multimesh.set_instance_transform(i, position)
		self.multimesh.set_instance_custom_data(i, Color(randf(), randf(), randf(), randf()))

func _physics_process(delta: float) -> void:
	#compute_school()
	pass

func _exit_tree() -> void:
	# remove persistent RIDs
	rd.free_rid(pipeline)
	for i in NUM_UNIF:
		rd.free_rid(buffers[i])
