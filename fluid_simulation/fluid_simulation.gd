extends Node2D


@export var velocity_damping: float = 1
@export var interaction_radius: float = 100
@export var k: float = 3
@export var k_near: float = 6
@export var rest_density: float = 6;
@export var gravity: float = 4
@export var viscous_beta: float = 0;
@export var viscous_sigma: float = 1;

const POSITIONS_BINDING: int = 0
const PREVIOUS_POSITIONS_BINDING: int = 1
const VELOCITY_BINDING: int = 2
const FLUID_DATA_BINDING: int = 3
const PARAMS_BINDING: int = 4
const COLOR_BINDING: int = 5
const PARTICLE_COLOR_DATA_BINDING: int = 6
const MUG_COLLIDER_BINDING: int = 7

var NUM_PARTICLES: int = 1000
var MAX_PARTICLES: int = 10000

var IMAGE_SIZE = int(ceil(sqrt(MAX_PARTICLES)))

@onready var mug_collider: CollisionPolygon2D = %MugCollider

var particle_positions: ParticlePropertyVec2
var particle_velocities: ParticlePropertyVec2
var particle_previous_positions: ParticlePropertyVec2
var particle_color: ParticlePropertyVec4

var mug_verticies: ParticlePropertyVec2

var fluid_data: Image
var fluid_data_texture: ImageTexture
var particle_color_data: Image
var particle_color_texture: ImageTexture

var fluid_data_buffer : RID
var fluid_data_buffer_uniform: RDUniform
var particle_color_data_buffer: RID
var particle_color_data_uniform: RDUniform

# -------- Shaders ------
var rd : RenderingDevice
var fluid_compute_shader : RID
var fluid_pipeline : RID

var bindings: Array = []
var params_buffer: RID
var params_uniform : RDUniform
var uniform_set : RID

var fluid_pos: Array[Vector2] = []
var predicted_pos: Array[Vector2] = []
var fluid_vel: Array[Vector2] = []
var fluid_color: Array[Vector4] = []
var densities = []

var last_debug: float = 0
var mouse_down: bool = false

func _ready() -> void:
	_generate_fluid()
	_setup_compute_shader()
	_update_fluid_particles(0)
	$FluidParticles.amount = MAX_PARTICLES
	$FluidParticles.process_material.set_shader_parameter("fluid_data", fluid_data_texture)
	$FluidParticles.process_material.set_shader_parameter("fluid_color", particle_color_texture)

func _generate_fluid():
	for i in NUM_PARTICLES:
		var pos = Vector2(randf() * get_viewport_rect().size.x, randf()  * get_viewport_rect().size.y)
		fluid_pos.append(pos)
		predicted_pos.append(pos)
		densities.append(Vector2.ZERO)
		fluid_vel.append(Vector2(0, 0))
		fluid_color.append(Vector4(1.0, 0.647, 0.0, 1))
		

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
	
	particle_color_data = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH)
	particle_color_texture = ImageTexture.create_from_image(particle_color_data)

	var fmt := RDTextureFormat.new()
	fmt.width = IMAGE_SIZE
	fmt.height = IMAGE_SIZE
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	particle_positions = ParticlePropertyVec2.new(rd, fluid_pos, POSITIONS_BINDING)
	particle_velocities = ParticlePropertyVec2.new(rd, fluid_vel, VELOCITY_BINDING)
	particle_previous_positions = ParticlePropertyVec2.new(rd, predicted_pos, PREVIOUS_POSITIONS_BINDING)
	particle_color = ParticlePropertyVec4.new(rd, fluid_color, COLOR_BINDING)
	
	var polygon: Array[Vector2] = []
	for v in mug_collider.polygon:
		polygon.append(v + mug_collider.get_parent().position)

	var mug_particle_property = ParticlePropertyVec2.new(rd, polygon, MUG_COLLIDER_BINDING)
	
	var view := RDTextureView.new()
	fluid_data_buffer = rd.texture_create(fmt, view, [fluid_data.get_data()])
	fluid_data_buffer_uniform = _generate_uniform(fluid_data_buffer, RenderingDevice.UNIFORM_TYPE_IMAGE, FLUID_DATA_BINDING)

	particle_color_data_buffer = rd.texture_create(fmt, RDTextureView.new(), [particle_color_data.get_data()])
	particle_color_data_uniform = _generate_uniform(particle_color_data_buffer, RenderingDevice.UNIFORM_TYPE_IMAGE, PARTICLE_COLOR_DATA_BINDING)

	params_buffer = _generate_parameter_buffer(0)
	params_uniform = _generate_uniform(params_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, PARAMS_BINDING)

	bindings = [
		particle_positions.uniform,
		particle_previous_positions.uniform,
		particle_velocities.uniform,
		fluid_data_buffer_uniform,
		params_uniform,
		particle_color.uniform,
		particle_color_data_uniform,
		mug_particle_property.uniform,
	]

func _update_data_texture():
	var fluid_data_image_data := rd.texture_get_data(fluid_data_buffer, 0)
	fluid_data.set_data(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH, fluid_data_image_data)
	fluid_data_texture.update(fluid_data)

	var particle_color_image_data := rd.texture_get_data(particle_color_data_buffer, 0)
	particle_color_data.set_data(IMAGE_SIZE, IMAGE_SIZE, false,  Image.FORMAT_RGBAH, particle_color_image_data)
	particle_color_texture.update(particle_color_data)

func _bytes_to_packed_vector2_array(bytes: PackedByteArray) -> PackedVector2Array:
	if bytes.size() % 8 != 0:
		return []
	var result: PackedVector2Array = []
	var count: int = bytes.size() / 8.0
	result.resize(count)
	for i in count:
		result[i] = Vector2(bytes.decode_float(i * 8), bytes.decode_float(i * 8 + 4))
	return result

func _spawn_particles():
	if NUM_PARTICLES > MAX_PARTICLES:
		return
	
	var new_positions: Array[Vector2] = []
	var new_velocities: Array[Vector2] = []
	var new_colors: Array[Vector4] = []

	for i in range(-2, 2, 1):
		var pos = Vector2(get_viewport().get_mouse_position().x + i * 5, get_viewport().get_mouse_position().y)
		new_positions.append(pos)
		new_velocities.append(Vector2.ZERO)
		new_colors.append(Vector4(0.498, 1.0, 0.831, 1))

		NUM_PARTICLES += 1
	
	particle_positions.add_particles(new_positions)
	particle_previous_positions.add_particles(new_positions)
	particle_velocities.add_particles(new_velocities)
	particle_color.add_particles(new_colors)

func _update_fluid_particles(delta):
	if mouse_down:
		_spawn_particles()
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
		0,
		get_viewport().get_mouse_position().x,
		get_viewport().get_mouse_position().y,
		viscous_beta,
		viscous_sigma,
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

func _input(event):
	if event is InputEventMouseButton:
		mouse_down = 1 if event.pressed else 0

func _exit_tree():
	rd.sync()
	rd.free_rid(uniform_set)
	rd.free_rid(fluid_data_buffer)
	rd.free_rid(particle_color_data_buffer)
	rd.free_rid(params_buffer)
	rd.free_rid(particle_positions.buffer)
	rd.free_rid(particle_previous_positions.buffer)
	rd.free_rid(particle_velocities.buffer)
	rd.free_rid(fluid_compute_shader)
	rd.free_rid(fluid_pipeline)
	rd.free()
