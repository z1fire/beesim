shader_type spatial;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(detail, vec2((v_world.x + v_world.z) * 0.9, v_world.y * 0.12)).r;
	float m = texture(detail, v_world.xz * 0.3 + v_world.y * 0.05).r;
	ALBEDO = COLOR.rgb * (0.6 + 0.6 * n) * (0.85 + 0.3 * m);
	ROUGHNESS = 0.95;
}
