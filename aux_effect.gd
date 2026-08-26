@tool
class_name AuxEffect extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var main_pipeline: RID

var nearest_sampler: RID
var fmt: RDTextureFormat
var size: Vector2i = Vector2i(1920, 1080)

var scene_buffers: RenderSceneBuffersRD

var number: int = 0
var started: bool = false

var aux_camera: Camera3D
var aux_viewport: Viewport

var target_viewport: Viewport
var target_camera: Camera3D

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
	
	var glsl_file: RDShaderFile = load("res://aux_effect.glsl")
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
	RenderingServer.call_on_render_thread(initialize_cs)
	
	var sampler_state: RDSamplerState = RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	nearest_sampler = rd.sampler_create(sampler_state)
	
	fmt = RDTextureFormat.new()
	fmt.width = size.x
	fmt.height = size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
					| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
					| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
					| RenderingDevice.TEXTURE_USAGE_CPU_READ_BIT \
					| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT


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
	
	var old_size: Vector2i = size
	size = scene_buffers.get_internal_size()
	#main_shader_ref.size = size
	#print(size)
	if size.x == 0 or size.y == 0: return
	fmt.width = size.x
	fmt.height = size.y
	
	@warning_ignore_start("integer_division")
	var x_groups: int = (size.x - 1) / 8 + 1
	var y_groups: int = (size.y - 1) / 8 + 1
	@warning_ignore_restore("integer_division")
	
	var push_constants: PackedFloat32Array
	push_constants.append(size.x)
	push_constants.append(size.y)
	
	var view_count: int = scene_buffers.get_view_count()
	
	main_shader_ref.mask_tex[number].resize(view_count)
	main_shader_ref.depth_tex[number].resize(view_count)
	
	for view in view_count:
		if not main_shader_ref.mask_tex[number][view] or not main_shader_ref.mask_tex[number][view].is_valid():
			main_shader_ref.mask_tex[number][view] = rd.texture_create(fmt, RDTextureView.new(), [])
		if not main_shader_ref.depth_tex[number][view] or not main_shader_ref.depth_tex[number][view].is_valid():
			main_shader_ref.depth_tex[number][view] = rd.texture_create(fmt, RDTextureView.new(), [])
		
		if old_size != size:
			rd.free_rid(main_shader_ref.mask_tex[number][view])
			main_shader_ref.mask_tex[number][view] = rd.texture_create(fmt, RDTextureView.new(), [])
			rd.free_rid(main_shader_ref.depth_tex[number][view])
			main_shader_ref.depth_tex[number][view] = rd.texture_create(fmt, RDTextureView.new(), [])
		
		#print(main_shader_ref.'mask_tex[number][view])
		#print(main_shader_ref.'depth_tex[number][view])
		
		var uniform_aux_out: RDUniform = RDUniform.new()
		uniform_aux_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_aux_out.binding = 0
		uniform_aux_out.add_id(main_shader_ref.mask_tex[number][view])
		
		var uniform_depth_out: RDUniform = RDUniform.new()
		uniform_depth_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_depth_out.binding = 1
		uniform_depth_out.add_id(main_shader_ref.depth_tex[number][view])
		
		var uniform_aux_in: RDUniform = RDUniform.new()
		uniform_aux_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_aux_in.binding = 2
		uniform_aux_in.add_id(scene_buffers.get_color_layer(view))
		
		var uniform_depth_in: RDUniform = RDUniform.new()
		uniform_depth_in.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_depth_in.binding = 3
		uniform_depth_in.add_id(nearest_sampler)
		uniform_depth_in.add_id(scene_buffers.get_depth_layer(view))
		
		var image_uniform_set: RID
		image_uniform_set = UniformSetCacheRD.get_cache(shader, 0, [uniform_aux_out, uniform_depth_out, uniform_aux_in, uniform_depth_in])
		
		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, main_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
