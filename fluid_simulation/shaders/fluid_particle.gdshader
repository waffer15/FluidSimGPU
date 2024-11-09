shader_type particles;
uniform sampler2D fluid_data;
uniform sampler2D fluid_color;
uniform vec2 scale = vec2(.1, .1);

void process() {
	ivec2 pos_image_size = textureSize(fluid_data, 0);

	ivec2 texel_pos = ivec2(int(mod(float(INDEX),float(pos_image_size.x))),
							int(float(INDEX)/float(pos_image_size.x)));

	vec4 fluid_pos = texelFetch(fluid_data, texel_pos, 0);
	mat2 scale_rot_mat = mat2(vec2(cos(fluid_pos.b), sin(fluid_pos.b)), // First column
							  vec2(-sin(fluid_pos.b), cos(fluid_pos.b))); // Sec

	vec4 particle_color = texelFetch(fluid_color, texel_pos, 0);


	scale_rot_mat[0] *= scale.x;
	scale_rot_mat[1] *= scale.y;
	TRANSFORM[3].xy = vec2(fluid_pos.r, fluid_pos.g);
	COLOR = vec4(particle_color.rgb, 1);
}
