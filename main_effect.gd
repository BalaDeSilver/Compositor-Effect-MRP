@tool
class_name CoolEffect extends CompositorEffect

var rd: RenderingDevice
var shader: RID
var main_pipeline: RID

var nearest_sampler: RID
var fmt: RDTextureFormat
var size: Vector2i = Vector2i(1920, 1080)

var aux_scene: PackedScene = preload("res://aux.tscn")
var aux_viewports: Array[AuxViewport]

var scene_root: Node

var mask_tex: Array[Array]
var depth_tex: Array[Array]
var prev_tex: Array[Array]

var hash_array: Array[StringName] = ["One", "Two", "Three", "Four"]

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and shader:
		if shader.is_valid():
			RenderingServer.free_rid(shader)


func initialize_cs() -> void:
	aux_viewports.resize(4)
	mask_tex.resize(4)
	depth_tex.resize(4)
	prev_tex.resize(4)
	
	if Engine.is_editor_hint():
		scene_root = EditorInterface.get_edited_scene_root()
	else:
		scene_root = Engine.get_main_loop().current_scene
	
	#if compositor.compositor_effects.size() > 0:
	
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
	
	if scene_root:
		for i in 4:
			prev_tex[i].clear()
			
			aux_viewports[i] = scene_root.get_node_or_null(str(hash_array[i].hash()))
			if not aux_viewports[i]:
				aux_viewports[i] = aux_scene.instantiate()
				aux_viewports[i].name = str(hash_array[i].hash())
				scene_root.add_child(aux_viewports[i])
				#aux_viewports[i].owner = self
			
			aux_viewports[i].get_camera_3d().visible = false
			aux_viewports[i].get_camera_3d().compositor.compositor_effects[0].number = i
			aux_viewports[i].get_camera_3d().compositor.compositor_effects[0].main_shader_ref = self


func _init() -> void:
	needs_motion_vectors = true
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
	if not scene_root or not rd or not shader or not main_pipeline or not aux_viewports[0]:
		initialize_cs()
		return
		
	for i in 4:
		var current_camera: Camera3D = aux_viewports[i].get_camera_3d()
		
		if Engine.is_editor_hint():
			var editor_viewport: SubViewport = EditorInterface.get_editor_viewport_3d(i)
			var editor_camera: Camera3D = editor_viewport.get_camera_3d()
			
			current_camera.transform = editor_camera.transform
			current_camera.transform.origin += current_camera.basis.z * 0.0001
			current_camera.fov = editor_camera.fov
			current_camera.near = editor_camera.near
			current_camera.far = editor_camera.far
			
			aux_viewports[i].size = editor_viewport.size
		else:
			var game_viewport: Viewport = Engine.get_main_loop().current_scene.get_viewport()
			var game_camera: Camera3D = game_viewport.get_camera_3d()
			
			current_camera.transform = game_camera.transform
			current_camera.fov = game_camera.fov
			current_camera.near = game_camera.near
			current_camera.far = game_camera.far
			
			aux_viewports[i].size = game_viewport.size
	
	if mask_tex[0].size() < 1 or not mask_tex[0][0].is_valid():
		return
	
	if aux_viewports.size() > 0 and mask_tex and depth_tex:
		var masktex: RID
		var maskdepth: RID
		var prevtex: RID
		
		var scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
		if not scene_buffers: return
		
		size = scene_buffers.get_internal_size()
		if size.x == 0 or size.y == 0: return
		fmt.width = size.x
		fmt.height = size.y
		
		@warning_ignore_start("integer_division")
		var x_groups: int = (size.x - 1) / 16 + 1
		var y_groups: int = (size.y - 1) / 16 + 1
		@warning_ignore_restore("integer_division")
		
		var push_constants: PackedFloat32Array
		push_constants.append(size.x)
		push_constants.append(size.y)
		push_constants.append(Time.get_ticks_msec())
		
		var view_count = scene_buffers.get_view_count()
		
		for view in view_count:
			var screentex: RID = scene_buffers.get_color_layer(view)
			var motiontex: RID = scene_buffers.get_velocity_layer(view)
			
			var render_target: RID = render_data.get_render_scene_buffers().get_render_target()
			for index in range(4):
				prev_tex[index].resize(view_count)
				
				if not prev_tex[index][view]:
					prev_tex[index][view] = rd.texture_create(fmt, RDTextureView.new(), [])
				
				var viewport: Viewport
				if Engine.is_editor_hint():
					viewport = EditorInterface.get_editor_viewport_3d(index)
				else:
					viewport = scene_root.get_viewport()
				var viewport_RID: RID = viewport.get_viewport_rid()
				var viewport_render_target_RID: RID = RenderingServer.viewport_get_render_target(viewport_RID)
				
				if render_target == viewport_render_target_RID:
					masktex = mask_tex[index][view]
					maskdepth = depth_tex[index][view]
					prevtex = prev_tex[index][view]
					break
			if not masktex.is_valid() or not maskdepth.is_valid() or not prevtex.is_valid():
				print("Invalid texture")
				return
			
			var uniform_screen: RDUniform = RDUniform.new()
			uniform_screen.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_screen.binding = 0
			uniform_screen.add_id(screentex)
			
			var uniform_mask: RDUniform = RDUniform.new()
			uniform_mask.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_mask.binding = 1
			uniform_mask.add_id(masktex)
			
			var uniform_maskdepth: RDUniform = RDUniform.new()
			uniform_maskdepth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform_maskdepth.binding = 2
			uniform_maskdepth.add_id(nearest_sampler)
			uniform_maskdepth.add_id(maskdepth)
			
			var uniform_prev: RDUniform = RDUniform.new()
			uniform_prev.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_prev.binding = 3
			uniform_prev.add_id(prevtex)
			
			var uniform_motion: RDUniform = RDUniform.new()
			uniform_motion.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_motion.binding = 4
			uniform_motion.add_id(motiontex)
			
			var image_uniform_set: RID
			image_uniform_set = UniformSetCacheRD.get_cache(shader, 0, [uniform_screen, uniform_mask, uniform_maskdepth, uniform_prev, uniform_motion])
			
			var compute_list: int = rd.compute_list_begin()
			
			rd.compute_list_bind_compute_pipeline(compute_list, main_pipeline)
			rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
			rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
			rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
			rd.compute_list_end()
