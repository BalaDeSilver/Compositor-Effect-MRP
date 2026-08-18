@tool
class_name AuxViewport extends SubViewport

@onready var aux_camera: Camera3D = $AuxCamera

var target_viewport: Viewport
var target_camera: Camera3D

func _process(_delta: float) -> void:
	if target_camera:
		#print(target_camera)
		aux_camera.transform = target_camera.transform
		aux_camera.transform.origin += aux_camera.basis.z * 0.0001
		aux_camera.fov = target_camera.fov
		aux_camera.near = target_camera.near
		aux_camera.far = target_camera.far
		
		size = target_viewport.size
