extends MultiMeshInstance3D

const FISH_SCHOOLING = preload("res://compute-shaders/fish-schooling.glsl")
# inital distrbution of fish
@export var dist:Vector3 = Vector3(8.0, 5.0, 5.0)
var half_dist:Vector3
@onready var world_scene: Node = $"../World_Scene"

# Reference to the active Rendering Device
# This is Godot's abstraction of GLSL, objects will interface with it using RIDs
var rd:RenderingDevice
# Reference for the loaded shader
var shader:RID
# Reference to the compute pipeline
var pipeline:RID
# stores the time between compute shader dispaches
var dispatch_timer:float = 0.0

# data structure for host side data
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

# host side fish data object
var data:FishData
# storage buffers
var buffer_bytes_dict:Dictionary[String, PackedByteArray] = {}
# storage buffer refernce IDs
var buffers_dict:Dictionary[String, RID] = {}
# uniforms
var uniforms_dict:Dictionary[String, RDUniform] = {}
# uniform binding list
var uniforms_binding_dict:Dictionary[String, int] = {}

# initalize compute shader parameters
func __init_compute() -> void:
	# Setup the reference to the Rendering Device
	rd = RenderingServer.create_local_rendering_device()
	# Load GLSL shader
	shader = rd.shader_create_from_spirv(FISH_SCHOOLING.get_spirv())
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)
	buffer_bytes_dict["prior"] = PackedFloat32Array(data.priorites).to_byte_array()
	buffer_bytes_dict["compute"] = PackedFloat32Array(data.mask).to_byte_array()
	buffer_bytes_dict["target"] = PackedVector3Array([data.target]).to_byte_array()
	buffer_bytes_dict["boids"] = PackedVector3Array(data.boids).to_byte_array()
	buffer_bytes_dict["time"] = PackedFloat32Array([dispatch_timer]).to_byte_array()
	buffer_bytes_dict["position"] = PackedVector3Array(data.positions).to_byte_array()
	buffer_bytes_dict["rate"] = PackedFloat32Array(data.rates).to_byte_array()
	buffer_bytes_dict["direction"] = PackedVector3Array(data.directions).to_byte_array()
	
	# this needs to match the "binding" in the shader file
	uniforms_binding_dict["prior"] = 0
	uniforms_binding_dict["compute"] = 1
	uniforms_binding_dict["target"] = 2
	uniforms_binding_dict["boids"] = 3
	uniforms_binding_dict["time"] = 4
	uniforms_binding_dict["position"] = 5
	uniforms_binding_dict["rate"] = 6
	uniforms_binding_dict["direction"] = 7

	# Create the storage buffers
	for key in buffer_bytes_dict:
		buffers_dict[key] = rd.storage_buffer_create(buffer_bytes_dict[key].size(), buffer_bytes_dict[key])
		uniforms_dict[key] = RDUniform.new()
		uniforms_dict[key].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniforms_dict[key].binding = uniforms_binding_dict[key]
		uniforms_dict[key].add_id(buffers_dict[key])

# prepare compute shader to run
func __setup_compute_step() -> void:
	buffer_bytes_dict["target"] = PackedVector3Array([data.target]).to_byte_array()
	buffer_bytes_dict["time"] = PackedFloat32Array([dispatch_timer]).to_byte_array()
	buffer_bytes_dict["position"] = PackedVector3Array(data.positions).to_byte_array()
	buffer_bytes_dict["direction"] = PackedVector3Array(data.directions).to_byte_array()

	# Update the storage buffers
	for key in ["target", "time", "position", "direction"]:
		rd.buffer_update(buffers_dict[key], 0, buffer_bytes_dict[key].size(), buffer_bytes_dict[key])

# run compute shader
func __compute_school() -> void:
	# the last parameter needs to match the "set" in the shader file
	var set_id_0:RID = rd.uniform_set_create([uniforms_dict["prior"],
											uniforms_dict["compute"], 
											uniforms_dict["target"], 
											uniforms_dict["boids"], 
											uniforms_dict["time"]]
											, shader, 0)
	var set_id_1:RID = rd.uniform_set_create([uniforms_dict["position"], 
											uniforms_dict["rate"],
											uniforms_dict["direction"]]
											, shader, 1)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, set_id_0, 0)
	rd.compute_list_bind_uniform_set(compute_list, set_id_1, 1)
	# dispatch vector will be multiplied by the layout vector in shader for total calls
	rd.compute_list_dispatch(compute_list, 1, 1, 1) # one dispatch
	rd.compute_list_end()
	dispatch_timer = 0.0; # dispatch was just launched 0 the timer
	rd.submit()
	rd.sync()
	
	# Read back the data from the buffers
	var new_pos_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["position"])
	var new_pos:PackedVector3Array = new_pos_bytes.to_vector3_array()
	var new_rate_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["rate"])
	var new_rate:PackedFloat32Array = new_rate_bytes.to_float32_array()
	var new_dir_bytes:PackedByteArray = rd.buffer_get_data(buffers_dict["direction"])
	var new_dir:PackedVector3Array = new_dir_bytes.to_vector3_array()
	
	# update multimesh instances to the computed positions and directions
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
		var transform_matrix := Transform3D()
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
		data.boids[i] = Vector3(1.0, 1.0, 1.8)
		data.priorites[i] = 1.0
		data.directions[i] = direction # forward direction
		data.rates[i] = rate
		
	# setup compute shader for calculating boids motion
	__init_compute()

func _physics_process(delta: float) -> void:
	world_scene.set_instance_count_text(self.multimesh.instance_count)
	# update host data structure with current target position
	data.target = world_scene.target.position
	# add delta time to timer value
	dispatch_timer += delta
	# run compute shader
	__setup_compute_step()
	__compute_school()

func _exit_tree() -> void:
	# remove persistent RIDs
	if not rd:
		return
	else:
		if pipeline: rd.free_rid(pipeline)
	for key in buffers_dict:
		rd.free_rid(buffers_dict[key])
