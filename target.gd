extends Node

@onready var fps_counter: Control = $FPS_Counter
@onready var target: Node3D = $Target
@export var radius:float = 5.0
var theta:float = 0.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	target.position = Vector3(radius, 0.0, 0.0)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	theta += delta
	target.position.x = radius * cos(0.25 * theta)
	target.position.z = radius * sin(0.15 * theta + sin(theta * 0.2 + PI))
	
func set_instance_count_text(count:int):
	fps_counter.set_instance_count_text(count)
