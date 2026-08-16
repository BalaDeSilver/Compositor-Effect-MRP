@tool
extends WorldEnvironment

@onready var icosphere: MeshInstance3D = $Icosphere

@export var rerandomize_rotation: bool = false:
	set(value):
		if value:
			bananba = Vector3(rng.randfn(0.1, 0.8), rng.randfn(0.1, 0.8), rng.randfn(0.1, 0.8))
		rerandomize_rotation = false

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var bananba: Vector3

func _ready() -> void:
	rng.randomize()
	bananba = Vector3(rng.randfn(0.1, 0.8), rng.randfn(0.1, 0.8), rng.randfn(0.1, 0.8))


func _process(_delta: float) -> void:
	icosphere.rotation_degrees += bananba
