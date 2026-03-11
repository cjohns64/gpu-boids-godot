extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
var rate:float = 1.0
var started:bool = false

func play_anim(_rate:float) -> void:
	self.rate = _rate + randf()
	started = true
	animation_player.play("ArmatureAction", -1, _rate, false)

func _process(delta: float) -> void:
	if not animation_player.is_playing() and started:
		animation_player.play("ArmatureAction", -1, self.rate, false)
