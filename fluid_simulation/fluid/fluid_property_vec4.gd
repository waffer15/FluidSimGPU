class_name FluidPropertyVec4


var _rd: RenderingDevice
var _uniform_binding: int

var buffer: RID
var uniform: RDUniform

func _init(rd: RenderingDevice, initial_values: Array[Vector4], uniform_binding: int) -> void:
	_rd = rd
	_uniform_binding = uniform_binding

	buffer = _generate_vec4_buffer(initial_values)
	uniform = _generate_uniform(buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, _uniform_binding)

func add_particles(particle: Array[Vector4]) -> void:
	var buffer_data: PackedVector4Array = _bytes_to_packed_vector4_array(_rd.buffer_get_data(buffer))
	_free_data()

	buffer_data.append_array(particle)
	buffer = _generate_vec4_buffer(buffer_data)
	uniform.add_id(buffer)

func _free_data() -> void:
	_rd.free_rid(buffer)
	uniform.clear_ids()

func _bytes_to_packed_vector4_array(bytes: PackedByteArray) -> PackedVector4Array:
	if bytes.size() % 16 != 0:
		return []
	var result: PackedVector4Array = []
	var count: int = bytes.size() / 16.0
	result.resize(count)
	for i in count:
		result[i] = Vector4(
			bytes.decode_float(i * 16),
			bytes.decode_float(i * 16 + 4),
			bytes.decode_float(i * 16 + 8),
			bytes.decode_float(i * 16 + 12)
		)
	return result

func _generate_vec4_buffer(data) -> RID:
	var data_buffer_bytes := PackedVector4Array(data).to_byte_array()
	var data_buffer = _rd.storage_buffer_create(max(data_buffer_bytes.size(), 1), data_buffer_bytes)
	return data_buffer

func _generate_uniform(data_buffer, type, binding):
	var data_uniform = RDUniform.new()
	data_uniform.uniform_type = type
	data_uniform.binding = binding
	data_uniform.add_id(data_buffer)
	return data_uniform
