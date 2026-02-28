extends Node3D

@export var radius:float = 5.0
var theta:float = 0.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	self.position = Vector3(radius, 0.0, 0.0)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	theta += delta
	self.position.x = radius * cos(0.25 * theta)
	self.position.z = radius * sin(0.25 * theta)
