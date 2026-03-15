extends Control

@onready var fps: Label = $Background/VBoxContainer/HBoxContainer/fps
@onready var ms: Label = $Background/VBoxContainer/HBoxContainer2/ms
@onready var instance_count: Label = $Background/VBoxContainer/HBoxContainer3/instance_count

# Called every frame. 'delta' is the elapsed time since the previous frame in seconds.
func _process(delta: float) -> void:
	ms.text = "%5.3f" % (1000.0 * delta)
	fps.text = "%5.3f" % (1.0 / delta)

func set_instance_count_text(count:int):
	instance_count.text = "%d" % (count)
