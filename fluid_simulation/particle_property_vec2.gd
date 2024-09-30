class_name ParticlePropertyVec2


var _rd: RenderingDevice
var _uniform_binding: int

var buffer: RID
var uniform: RDUniform

func _init(rd: RenderingDevice, initial_values: Array[Vector2], uniform_binding: int) -> void:
	_rd = rd
	_uniform_binding = uniform_binding

	buffer = _generate_vec2_buffer(initial_values)
	uniform = _generate_uniform(buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _uniform_binding)

func add_particles(particle: Array[Vector2]) -> void:
	var buffer_data: PackedVector2Array = _bytes_to_packed_vector2_array(_rd.buffer_get_data(buffer))
	_free_data()

	buffer_data.append_array(particle)
	buffer = _generate_vec2_buffer(buffer_data)
	uniform.add_id(buffer)

func _free_data() -> void:
	_rd.free_rid(buffer)
	uniform.clear_ids()

func _bytes_to_packed_vector2_array(bytes: PackedByteArray) -> PackedVector2Array:
	if bytes.size() % 8 != 0:
		return []
	var result: PackedVector2Array = []
	var count: int = bytes.size() / 8.0
	result.resize(count)
	for i in count:
		result[i] = Vector2(bytes.decode_float(i * 8), bytes.decode_float(i * 8 + 4))
	return result

func _generate_vec2_buffer(data):
	var data_buffer_bytes := PackedVector2Array(data).to_byte_array()
	var data_buffer = _rd.storage_buffer_create(data_buffer_bytes.size(), data_buffer_bytes)
	return data_buffer

func _generate_uniform(data_buffer, type, binding):
	var data_uniform = RDUniform.new()
	data_uniform.uniform_type = type
	data_uniform.binding = binding
	data_uniform.add_id(data_buffer)
	return data_uniform
