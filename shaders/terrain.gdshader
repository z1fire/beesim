shader_type spatial;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = texture(detail, v_world.xz * 0.013).r;
	float b = texture(detail, v_world.xz * 0.11).r;
	float c = texture(detail, v_world.xz * 0.6).r;
	ALBEDO = COLOR.rgb * (0.72 + 0.4 * a) * (0.88 + 0.24 * b) * (0.93 + 0.14 * c);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
