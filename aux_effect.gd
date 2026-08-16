@tool
class_name AuxEffect extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var main_pipeline: RID

var scene_buffers: RenderSceneBuffersRD

var number: int = 0
var started: bool = false

var main_shader_ref: CompositorEffect

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and shader.is_valid() and shader:
		RenderingServer.free_rid(shader)


func initialize_cs() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd:
		#print("Failed to get RD.")
		return
	#print("RD got successfully.")
	
	var glsl_file: RDShaderFile = load("res://cool_effect.glsl")
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	if not shader:
		#print("Failed to get shader.")
		return
	#print("Shader got successfully.")
	
	main_pipeline = rd.compute_pipeline_create(shader)
	if not main_pipeline:
		#print("Failed to get pipeline.")
		return
	#print("Pipeline got successfully.")


func _init() -> void:
	needs_motion_vectors = false
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT


func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	if not main_shader_ref:
		return
	
	scene_buffers = render_data.get_render_scene_buffers()
	
	if not rd or not shader or not main_pipeline:
		initialize_cs()
		return
	
	if not scene_buffers: return
	
	if not started:
		started = true
		return
	
	main_shader_ref.mask_tex[number].resize(scene_buffers.get_view_count())
	main_shader_ref.depth_tex[number].resize(scene_buffers.get_view_count())
	
	for view in scene_buffers.get_view_count():
		var aux: RID = scene_buffers.get_color_layer(view)
		var depth: RID = scene_buffers.get_depth_layer(view)
		var size = scene_buffers.get_internal_size()
		main_shader_ref.mask_tex[number][view] = aux
		main_shader_ref.depth_tex[number][view] = depth
