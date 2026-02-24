extends Control

@onready var fps: Label = $Background/VBoxContainer/HBoxContainer/fps
@onready var ms: Label = $Background/VBoxContainer/HBoxContainer2/ms

# Called every frame. 'delta' is the elapsed time since the previous frame in seconds.
func _process(delta: float) -> void:
	ms.text = "%5.3f" % (delta * 1000.0)
	fps.text = "%5.3f" % (1.0 / delta)
