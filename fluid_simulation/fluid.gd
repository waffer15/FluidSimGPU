extends Node2D

@export var velocity_damping: float = 1
@export var interaction_radius: float = 10
@export var k: float = 1
@export var k_near: float = 6
@export var rest_density: float = 5;
@export var gravity: float = 4

var POSITIONS_BINDING: int = 0
var PREVIOUS_POSITIONS_BINDING: int = 1
var VELOCITY_BINDING: int = 2
var FLUID_DATA_BINDING: int = 3
var PARAMS_BINDING: int = 4

var NUM_PARTICLES: int = 3000

var IMAGE_SIZE = int(ceil(sqrt(NUM_PARTICLES)))

var fluid_data: Image
var fluid_data_texture: ImageTexture
var fluid_data_buffer : RID
var fluid_pos_buffer: RID
var previous_pos_buffer: RID
var fluid_vel_buffer: RID
var densities_buffer: RID

# -------- Shaders ------
var rd : RenderingDevice
var fluid_compute_shader : RID
var fluid_pipeline : RID

var gravity_shader: RID
var gravity_pipeline: RID

var calculate_velocity_shader: RID
var calculate_velocity_pipeline: RID

var collide_with_world_boundary_shader: RID
var collide_with_world_boudary_pipeline: RID

var double_density_relaxation_shader: RID
var double_density_relaxation_pipeline: RID

var predict_position_shader: RID
var predict_position_pipeline: RID


var bindings: Array = []
var params_buffer: RID
var params_uniform : RDUniform
var uniform_set : RID

var fluid_pos = []
var predicted_pos = []
var fluid_vel = []
var densities = []

var last_debug: float = 0
var mouse_down: bool = false

func _ready() -> void:
	_generate_fluid()
	_setup_compute_shader()
	_update_fluid_particles(0)
	$FluidParticles.amount = NUM_PARTICLES
	$FluidParticles.process_material.set_shader_parameter("fluid_data", fluid_data_texture)

func _generate_fluid():
	for i in NUM_PARTICLES:
		var pos = Vector2(randf() * get_viewport_rect().size.x, randf()  * get_viewport_rect().size.y)
		fluid_pos.append(pos)
		predicted_pos.append(pos)
		densities.append(Vector2.ZERO)
		fluid_vel.append(Vector2(0, 0))

func _physics_process(delta: float) -> void:
	get_window().title = str(Engine.get_frames_per_second())
	rd.sync()
	_update_data_texture()
	_update_fluid_particles(delta)

func _setup_compute_shader() -> void:
	rd = RenderingServer.create_local_rendering_device()

	var shader_file := load("res://fluid_simulation/compute_shaders/fluid_simulation.glsl")

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	fluid_compute_shader = rd.shader_create_from_spirv(shader_spirv)
	fluid_pipeline = rd.compute_pipeline_create(fluid_compute_shader)

	fluid_data = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH)
	fluid_data_texture = ImageTexture.create_from_image(fluid_data)

	var fmt := RDTextureFormat.new()
	fmt.width = IMAGE_SIZE
	fmt.height = IMAGE_SIZE
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	fluid_pos_buffer = _generate_vec2_buffer(fluid_pos)
	var fluid_pos_uniform = _generate_uniform(fluid_pos_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, POSITIONS_BINDING)
	
	previous_pos_buffer = _generate_vec2_buffer(predicted_pos)
	var previous_pos_uniform = _generate_uniform(previous_pos_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, PREVIOUS_POSITIONS_BINDING)

	fluid_vel_buffer = _generate_vec2_buffer(fluid_vel)
	var fluid_vel_uniform = _generate_uniform(fluid_vel_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, VELOCITY_BINDING)

	var view := RDTextureView.new()
	fluid_data_buffer = rd.texture_create(fmt, view, [fluid_data.get_data()])
	
	var fluid_data_buffer_uniform = _generate_uniform(fluid_data_buffer, RenderingDevice.UNIFORM_TYPE_IMAGE, FLUID_DATA_BINDING)

	params_buffer = _generate_parameter_buffer(0)
	params_uniform = _generate_uniform(params_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, PARAMS_BINDING)

	bindings = [
		fluid_pos_uniform,
		previous_pos_uniform,
		fluid_vel_uniform,
		fluid_data_buffer_uniform,
		params_uniform
	]

func _update_data_texture():
	var fluid_data_image_data := rd.texture_get_data(fluid_data_buffer, 0)
	fluid_data.set_data(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH, fluid_data_image_data)
	fluid_data_texture.update(fluid_data)

func _update_fluid_particles(delta):
	rd.free_rid(params_buffer)
	params_buffer = _generate_parameter_buffer(delta)
	params_uniform.clear_ids()
	params_uniform.add_id(params_buffer)
	uniform_set = rd.uniform_set_create(bindings, fluid_compute_shader, 0)
	
	_run_compute_shader(fluid_pipeline)

func _generate_parameter_buffer(delta):
	var params_buffer_bytes : PackedByteArray = PackedFloat32Array([
		NUM_PARTICLES, 
		IMAGE_SIZE,
		get_viewport_rect().size.x,
		get_viewport_rect().size.y,
		0.25,
		velocity_damping,
		interaction_radius,
		k,
		k_near,
		rest_density,
		gravity,
		mouse_down,
		get_viewport().get_mouse_position().x,
		get_viewport().get_mouse_position().y,
	]).to_byte_array()
	return rd.storage_buffer_create(params_buffer_bytes.size(), params_buffer_bytes)

func _generate_vec2_buffer(data):
	var data_buffer_bytes := PackedVector2Array(data).to_byte_array()
	var data_buffer = rd.storage_buffer_create(data_buffer_bytes.size(), data_buffer_bytes)
	return data_buffer

func _run_compute_shader(pipeline):
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceil(NUM_PARTICLES/1024.), 1, 1)
	rd.compute_list_end()
	rd.submit()

func _generate_uniform(data_buffer, type, binding):
	var data_uniform = RDUniform.new()
	data_uniform.uniform_type = type
	data_uniform.binding = binding
	data_uniform.add_id(data_buffer)
	return data_uniform

func spawn_particles(positions: Array[Vector2], velocities: Array[Vector2]) -> void:
	if positions.size() != velocities.size():
		print("Warning: positions and velocities do not have the same size. Will not spawn particles")
		return
	
	for i in range(positions.size()):
		var index = NUM_PARTICLES + i - 1
		fluid_pos[index] = positions[i]
		fluid_vel[index] = velocities[i]
		predicted_pos[index] = positions[i]
		densities[index] = Vector2.ZERO
		NUM_PARTICLES += 1

func _input(event):
	if event is InputEventMouseButton:
		mouse_down = 1 if event.pressed else 0

func _exit_tree():
	rd.sync()
	rd.free_rid(uniform_set)
	rd.free_rid(fluid_data_buffer)
	rd.free_rid(params_buffer)
	rd.free_rid(fluid_pos_buffer)
	rd.free_rid(previous_pos_buffer)
	rd.free_rid(fluid_vel_buffer)
	rd.free_rid(fluid_compute_shader)
	rd.free_rid(fluid_pipeline)
	rd.free()
