class_name Fluid extends Node2D


const MAX_PARTICLES: int = 10000
var _num_particles: int = 0

# -------- Shader Bindings ------------
const POSITIONS_BINDING: int = 0
const PREVIOUS_POSITIONS_BINDING: int = 1
const VELOCITY_BINDING: int = 2
const FLUID_DATA_BINDING: int = 3
const PARAMS_BINDING: int = 4
const COLOR_BINDING: int = 5
const PARTICLE_COLOR_DATA_BINDING: int = 6
const COLLIDER_POLYGON_BINDING: int = 7

# --------- Shader Params ---------------
var _rd: RenderingDevice
var _shader_bindings: Array[RDUniform] = []
var _fluid_physics_shader: RID
var _fluid_physics_pipeline: RID
var _uniform_set : RID

# --------- Data Textures --------------
const IMAGE_SIZE = int(ceil(sqrt(MAX_PARTICLES)))
var _particle_position_image: Image
var _particle_color_image: Image
var _particle_position_texture: ImageTexture
var _particle_color_texture: ImageTexture

var _particle_position_image_buffer : RID
var _particle_position_uniform: RDUniform
var _particle_color_image_buffer: RID
var _particle_color_uniform: RDUniform

# ---------- Fluid SHader Properties -------------
var _particle_positions: FluidPropertyVec2
var _particle_velocities: FluidPropertyVec2
var _particle_previous_positions: FluidPropertyVec2
var _particle_colors: FluidPropertyVec4
var _collider_vertices: FluidPropertyVec2
var _params_buffer: RID
var _params_uniform: RDUniform

# ----------- Initial Fluid State ----------
var _initial_positions: Array[Vector2] = []
var _initial_previous_positions: Array[Vector2] = []
var _initial_velocities: Array[Vector2] = []
var _initial_colors: Array[Vector4] = []
var _initial_collider_polygon: Array[Vector2] = []


# --------- Particle Interaction Properties -----
var _collision_polygon: CollisionPolygon2D

@export var velocity_damping: float = 1
@export var interaction_radius: float = 100
@export var k: float = 3
@export var k_near: float = 6
@export var rest_density: float = 6;
@export var gravity: float = 4
@export var viscous_beta: float = 0;
@export var viscous_sigma: float = 1;

var _particle_positions_to_add: Array[Vector2] = []
var _particle_velocities_to_add: Array[Vector2] = []
var _particle_colors_to_add: Array[Vector4] = []

# -------- Lifecycle ---------
func _initialize_fluid(
	positions: Array[Vector2],
	velocities: Array[Vector2],
	colors: Array[Vector4],
) -> void:
	_initial_positions = positions
	_initial_previous_positions = positions
	_initial_velocities = velocities
	_initial_colors = colors

func _ready() -> void:
	if not $FluidParticles:
		printerr('Fluid must have child: GPUParticles2D named "FluidParticles"')
		return
	# _generate_fluid()
	_setup_compute_shader()
	_setup_gpu_particles()

	_update_fluid_params_uniform(0)
	_run_compute_shader()

func _generate_fluid():
	var positions: Array[Vector2] = []
	var vel: Array[Vector2] = []
	var colors: Array[Vector4] = []

	for i in range(_num_particles):
		var pos = Vector2(randf() * get_viewport_rect().size.x, randf()  * get_viewport_rect().size.y)
		positions.append(pos)
		vel.append(Vector2(0, 0))
		colors.append(Vector4(1.0, 0.647, 0.0, 1))
	_initialize_fluid(positions, vel, colors)


func _physics_process(delta: float) -> void:
	get_window().title = str(Engine.get_frames_per_second())
	_rd.sync()
	_update_data_texture()
	_update_collider_polygon_position()
	_flush_particles_to_add()
	_update_fluid_params_uniform(delta)
	_run_compute_shader()


# ------- Public Functions ---------
func add_particles_to_fluid(
	positions: Array[Vector2],
	velocities: Array[Vector2],
	colors: Array[Vector4],
):
	if _num_particles > MAX_PARTICLES:
		return

	_particle_positions_to_add.append_array(positions)
	_particle_velocities_to_add.append_array(velocities)
	_particle_colors_to_add.append_array(colors)

func _flush_particles_to_add():
	if _num_particles > MAX_PARTICLES:
		return

	if len(_particle_positions_to_add) == 0:
		return
	
	_num_particles += len(_particle_positions_to_add)

	_particle_positions.add_particles(_particle_positions_to_add)
	_particle_previous_positions.add_particles(_particle_positions_to_add)
	_particle_velocities.add_particles(_particle_velocities_to_add)
	_particle_colors.add_particles(_particle_colors_to_add)
	
	_particle_positions_to_add = []
	_particle_velocities_to_add = []
	_particle_colors_to_add = []
	
# -------- Setup Functions ---------
func _setup_gpu_particles() -> void:
	$FluidParticles.amount = MAX_PARTICLES
	$FluidParticles.process_material.set_shader_parameter("fluid_data", _particle_position_texture)
	$FluidParticles.process_material.set_shader_parameter("fluid_color", _particle_color_texture)

func _setup_compute_shader() -> void:
	_rd = RenderingServer.create_local_rendering_device()

	var shader_file := load("res://fluid_simulation/compute_shaders/fluid_simulation.glsl")

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_fluid_physics_shader = _rd.shader_create_from_spirv(shader_spirv)
	_fluid_physics_pipeline = _rd.compute_pipeline_create(_fluid_physics_shader)

	_particle_position_image = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH)
	_particle_position_texture = ImageTexture.create_from_image(_particle_position_image)
	
	_particle_color_image = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH)
	_particle_color_texture = ImageTexture.create_from_image(_particle_color_image)

	var fmt := RDTextureFormat.new()
	fmt.width = IMAGE_SIZE
	fmt.height = IMAGE_SIZE
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	_particle_positions = FluidPropertyVec2.new(_rd, _initial_positions, POSITIONS_BINDING)
	_particle_velocities = FluidPropertyVec2.new(_rd, _initial_velocities, VELOCITY_BINDING)
	_particle_previous_positions = FluidPropertyVec2.new(_rd, _initial_previous_positions, PREVIOUS_POSITIONS_BINDING)
	_particle_colors = FluidPropertyVec4.new(_rd, _initial_colors, COLOR_BINDING)


	_collider_vertices = FluidPropertyVec2.new(_rd, _initial_collider_polygon, COLLIDER_POLYGON_BINDING)

	var view := RDTextureView.new()
	_particle_position_image_buffer = _rd.texture_create(fmt, view, [_particle_position_image.get_data()])
	_particle_position_uniform = _generate_uniform(_particle_position_image_buffer, RenderingDevice.UNIFORM_TYPE_IMAGE, FLUID_DATA_BINDING)

	_particle_color_image_buffer = _rd.texture_create(fmt, RDTextureView.new(), [_particle_color_image.get_data()])
	_particle_color_uniform = _generate_uniform(_particle_color_image_buffer, RenderingDevice.UNIFORM_TYPE_IMAGE, PARTICLE_COLOR_DATA_BINDING)

	_params_buffer = _generate_parameter_buffer(0)
	_params_uniform = _generate_uniform(_params_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, PARAMS_BINDING)

	_shader_bindings = [
		_particle_positions.uniform,
		_particle_previous_positions.uniform,
		_particle_velocities.uniform,
		_particle_position_uniform,
		_params_uniform,
		_particle_colors.uniform,
		_particle_color_uniform,
		_collider_vertices.uniform,
	]

# -------- Running Shaders ----------
func _run_compute_shader():
	_uniform_set = _rd.uniform_set_create(_shader_bindings, _fluid_physics_shader, 0)
	
	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _fluid_physics_pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, max(ceil(_num_particles/1024.), 1), 1, 1)
	_rd.compute_list_end()
	_rd.submit()

# ---------- Update Shader Param Functions --------
func _update_fluid_params_uniform(delta: float) -> void:
	_rd.free_rid(_params_buffer)
	
	_params_buffer = _generate_parameter_buffer(delta)
	_params_uniform.clear_ids()
	_params_uniform.add_id(_params_buffer)

func _update_data_texture():
	var particle_position_image_data := _rd.texture_get_data(_particle_position_image_buffer, 0)
	_particle_position_image.set_data(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH, particle_position_image_data)
	_particle_position_texture.update(_particle_position_image)

	var particle_color_image_data := _rd.texture_get_data(_particle_color_image_buffer, 0)
	_particle_color_image.set_data(IMAGE_SIZE, IMAGE_SIZE, false,  Image.FORMAT_RGBAH, particle_color_image_data)
	_particle_color_texture.update(_particle_color_image)

func _update_collider_polygon_position() -> void:
	if not _collision_polygon:
		return

	var polygon: Array[Vector2] = []
	for v in _collision_polygon.polygon:
		polygon.append(_collision_polygon.get_parent().to_global(v))

	_collider_vertices.replace_particles(polygon)

# ---------- Helper Functions -----------
func _generate_uniform(data_buffer: RID, type: RenderingDevice.UniformType, binding: int) -> RDUniform:
	var data_uniform: RDUniform = RDUniform.new()
	data_uniform.uniform_type = type
	data_uniform.binding = binding
	data_uniform.add_id(data_buffer)
	return data_uniform

func _generate_parameter_buffer(_delta) -> RID:
	var params_buffer_bytes : PackedByteArray = PackedFloat32Array([
		_num_particles, 
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
	return _rd.storage_buffer_create(params_buffer_bytes.size(), params_buffer_bytes)


func _exit_tree():
	_rd.sync()
	_rd.free_rid(_uniform_set)
	_rd.free_rid(_particle_position_image_buffer)
	_rd.free_rid(_particle_color_image_buffer)
	_rd.free_rid(_params_buffer)
	_rd.free_rid(_particle_positions.buffer)
	_rd.free_rid(_particle_previous_positions.buffer)
	_rd.free_rid(_particle_velocities.buffer)
	_rd.free_rid(_fluid_physics_shader)
	_rd.free_rid(_fluid_physics_pipeline)
	_rd.free()
