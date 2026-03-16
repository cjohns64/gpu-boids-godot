extends MultiMeshInstance3D

const FISH_SCHOOLING = preload("res://compute-shaders/fish-schooling.glsl")
const AVERAGE_VECTORS = preload("res://compute-shaders/average-vectors.glsl")
#const SPINE_FISH_LP = preload("res://Fish/spine_fish_lp.tscn")
const NUMBER:int = 2048
const SCHOOL_SIZE:int = 1024 # should match value in glsl file!
var num_workgroups:int = ceili(float(NUMBER) / float(SCHOOL_SIZE))
# initial distribution of fish
@export var dist:Vector3 = Vector3(8.0, 5.0, 5.0)
var half_dist:Vector3
@onready var world_scene: Node = $"../World_Scene"

# Reference to the active Rendering Device
# This is Godot's abstraction of GLSL, objects will interface with it using RIDs
var rd:RenderingDevice
# Reference for the loaded shader
var avg_shader:RID
var boids_shader:RID
# Reference to the compute pipeline
var avg_pipeline:RID
var boids_pipeline:RID
# stores the time between compute shader dispatches
var dispatch_timer:float = 0.0
#var fish_array:Array[Node3D] = []

# data structure for host side data
class FishData:
	var mask:Array[float]
	var positions:Array[Vector3]
	var directions:Array[Vector3]
	var rates:Array[float]
	var target:Vector3
	var average_position:Vector3
	var average_direction:Vector3
	var boids_alignment:float = 0.5
	var boids_cohesion:float = 0.8
	var boids_separation:float = 1.5
	
	func _init() -> void:
		mask.resize(NUMBER)
		positions.resize(NUMBER)
		directions.resize(NUMBER)
		rates.resize(NUMBER)

# host side fish data object
var data:FishData
# storage buffers
var buffer_bytes_dict:Dictionary[String, PackedByteArray] = {}
# storage buffer reference IDs
var buffers_dict:Dictionary[String, RID] = {}
# uniforms
var uniforms_dict:Dictionary[String, RDUniform] = {}
# uniform binding list
var uniforms_binding_dict:Dictionary[String, int] = {}

# initialize compute shader parameters
func __init_compute() -> void:
	# Arrays for intermidiate results for average calcualtions
	var intermidiate_reduction_array_dummy_V3:PackedVector3Array
	var intermidiate_reduction_array_dummy_Fl:PackedFloat32Array
	# size the intemidiate results arrays, their values will never be read but they are needed to set the size of the buffers
	intermidiate_reduction_array_dummy_V3.resize(num_workgroups)
	intermidiate_reduction_array_dummy_Fl.resize(num_workgroups)
	# dummy array for params buffer
	var params_buffer_dummy:PackedFloat32Array
	params_buffer_dummy.resize(13)
	# Setup the reference to the Rendering Device
	rd = RenderingServer.create_local_rendering_device()
	# Load GLSL shader
	avg_shader = rd.shader_create_from_spirv(AVERAGE_VECTORS.get_spirv())
	boids_shader = rd.shader_create_from_spirv(FISH_SCHOOLING.get_spirv())
	# Create a compute pipeline
	avg_pipeline = rd.compute_pipeline_create(avg_shader)
	boids_pipeline = rd.compute_pipeline_create(boids_shader)
	buffer_bytes_dict["params"] = params_buffer_dummy.to_byte_array()
	buffer_bytes_dict["position"] = PackedVector3Array(data.positions).to_byte_array()
	buffer_bytes_dict["direction"] = PackedVector3Array(data.directions).to_byte_array()
	buffer_bytes_dict["mask"] = PackedFloat32Array(data.mask).to_byte_array()
	buffer_bytes_dict["rate"] = PackedFloat32Array(data.rates).to_byte_array()
	buffer_bytes_dict["avg_pos"] = intermidiate_reduction_array_dummy_V3.to_byte_array()
	buffer_bytes_dict["avg_dir"] = intermidiate_reduction_array_dummy_V3.to_byte_array()
	buffer_bytes_dict["num_act"] = intermidiate_reduction_array_dummy_Fl.to_byte_array()
	
	# this needs to match the "binding" in the shader file
	uniforms_binding_dict["params"] = 0
	uniforms_binding_dict["mask"] = 1
	uniforms_binding_dict["rate"] = 2
	uniforms_binding_dict["position"] = 3
	uniforms_binding_dict["direction"] = 4
	uniforms_binding_dict["avg_pos"] = 5
	uniforms_binding_dict["avg_dir"] = 6
	uniforms_binding_dict["num_act"] = 7

	# Create the storage buffers
	for key in buffer_bytes_dict:
		buffers_dict[key] = rd.storage_buffer_create(buffer_bytes_dict[key].size(), buffer_bytes_dict[key])
		uniforms_dict[key] = RDUniform.new()
		uniforms_dict[key].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniforms_dict[key].binding = uniforms_binding_dict[key]
		uniforms_dict[key].add_id(buffers_dict[key])

# prepare boids compute shader to run
func __setup_boids_compute() -> void:
	buffer_bytes_dict["params"] = PackedFloat32Array([data.target.x, data.target.y, data.target.z,
													data.average_position.x,data.average_position.y,data.average_position.z,
													data.average_direction.x,data.average_direction.y,data.average_direction.z,
													data.boids_cohesion, data.boids_alignment, data.boids_separation,
													dispatch_timer]).to_byte_array()
	buffer_bytes_dict["position"] = PackedVector3Array(data.positions).to_byte_array()
	buffer_bytes_dict["direction"] = PackedVector3Array(data.directions).to_byte_array()

	# Update the storage buffers
	for key in ["params", "position", "direction"]:
		rd.buffer_update(buffers_dict[key], 0, buffer_bytes_dict[key].size(), buffer_bytes_dict[key])

# calculate the average position and direction of the school
func __compute_avg_kernel() -> void:
	# create the uniform sets
	# the last parameter needs to match the "set" in the shader file
	var set_id_0:RID = rd.uniform_set_create([uniforms_dict["mask"]], avg_shader, 0)
	var set_id_1:RID = rd.uniform_set_create([uniforms_dict["position"], uniforms_dict["direction"]], avg_shader, 1)
	var set_id_2:RID = rd.uniform_set_create([uniforms_dict["avg_pos"], uniforms_dict["avg_dir"], uniforms_dict["num_act"]], avg_shader, 2)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, avg_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, set_id_0, 0)
	rd.compute_list_bind_uniform_set(compute_list, set_id_1, 1)
	rd.compute_list_bind_uniform_set(compute_list, set_id_2, 2)
	# dispatch vector will be multiplied by the layout vector in shader for total calls
	rd.compute_list_dispatch(compute_list, num_workgroups, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	
	# Read back the data from the buffers
	var pos_results_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["avg_pos"])
	var pos_results:PackedVector3Array = pos_results_bytes.to_vector3_array()
	var dir_results_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["avg_dir"])
	var dir_results:PackedVector3Array = dir_results_bytes.to_vector3_array()
	var num_act_results_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["num_act"])
	var num_act_results:PackedFloat32Array = num_act_results_bytes.to_float32_array()
	# finish the averages
	var avg_pos:Vector3 = Vector3.ZERO
	var avg_dir:Vector3 = Vector3.ZERO
	var num_act:float = 0.0
	for i in range(num_workgroups):
		avg_pos += pos_results[i]
		avg_dir += dir_results[i]
		num_act += num_act_results[i]
	# nomalize and cache results
	data.average_direction = avg_dir.normalized()
	if num_act != 0.0:
		avg_pos = avg_pos / (num_act)
	data.average_position = avg_pos

# simulate boids motion for all fish
func __compute_boids_kernel() -> void:
	__setup_boids_compute()
	# create the uniform sets
	# the last parameter needs to match the "set" in the shader file
	var set_id_0:RID = rd.uniform_set_create([uniforms_dict["params"], uniforms_dict["mask"]], boids_shader, 0)
	var set_id_1:RID = rd.uniform_set_create([uniforms_dict["rate"], uniforms_dict["position"], uniforms_dict["direction"]], boids_shader, 1)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, boids_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, set_id_0, 0)
	rd.compute_list_bind_uniform_set(compute_list, set_id_1, 1)
	# dispatch vector will be multiplied by the layout vector in shader for total calls
	rd.compute_list_dispatch(compute_list, num_workgroups, 1, 1)
	rd.compute_list_end()
	dispatch_timer = 0.0; # dispatch was just launched, 0 the timer
	rd.submit()
	rd.sync()
	
	# Read back the data from the buffers
	var pos_results_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["position"])
	var pos_results:PackedVector3Array = pos_results_bytes.to_vector3_array()
	var dir_results_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["direction"])
	var dir_results:PackedVector3Array = dir_results_bytes.to_vector3_array()
	
	# update multimesh instances to the computed positions and directions
	for i in range(NUMBER):
		var transform_matrix:Transform3D = self.multimesh.get_instance_transform(i)
		#var transform_matrix:Transform3D = fish_array[i].transform
		# look at new pointing direction
		if dir_results[i] != Vector3.ZERO:
			transform_matrix = transform_matrix.looking_at(dir_results[i] + transform_matrix.origin, Vector3.UP, true) 
		# move to new position
		if data.positions[i] != pos_results[i]:
			transform_matrix = transform_matrix.translated(pos_results[i] - data.positions[i])
		self.multimesh.set_instance_transform(i, transform_matrix)
		#fish_array[i].transform = transform_matrix
		# update position, rate, and direction
		data.positions[i] = pos_results[i]
		#data.rates[i] = new_rate[i]
		data.directions[i] = dir_results[i]

	# free local RIDs
	rd.free_rid(set_id_0)
	rd.free_rid(set_id_1)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	num_workgroups = ceili(float(NUMBER) / float(SCHOOL_SIZE))
	#fish_array.resize(NUMBER)
	data = FishData.new()
	# place the initial distribution of fish
	half_dist = dist / 2.0
	self.multimesh.instance_count = NUMBER
	for i in range(NUMBER):
		var transform_matrix := Transform3D()
		var location:Vector3 = Vector3(randf() * dist.x - half_dist.x, randf() * dist.y - half_dist.y, randf() * dist.z - half_dist.z)
		#var location := Vector3.UP
		var direction:Vector3 = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
		transform_matrix = transform_matrix.looking_at(direction + location, Vector3.UP, true)
		transform_matrix = transform_matrix.translated(location)
		#var obj:Node3D = SPINE_FISH_LP.instantiate()
		#self.add_child(obj)
		#fish_array[i] = obj
		#obj.transform = transform_matrix
		self.multimesh.set_instance_transform(i, transform_matrix)
		var rate:float = 0.5
		self.multimesh.set_instance_custom_data(i, Color(rate, randf(), randf(), randf()))
		# add fish to data
		data.positions[i] = location
		data.mask[i] = 1.0
		data.directions[i] = direction # forward direction
		data.rates[i] = rate
		
	# setup compute shader for calculating boids motion
	__init_compute()

func _physics_process(delta: float) -> void:
	world_scene.set_instance_count_text(NUMBER)
	# update host data structure with current target position
	data.target = world_scene.target.position
	# add delta time to timer value
	dispatch_timer += delta
	# run compute shaders
	__compute_avg_kernel()
	__compute_boids_kernel()

func _exit_tree() -> void:
	# remove persistent RIDs
	if not rd:
		return
	else:
		if boids_pipeline: rd.free_rid(boids_pipeline)
		if avg_pipeline: rd.free_rid(avg_pipeline)
	for key in buffers_dict:
		rd.free_rid(buffers_dict[key])
