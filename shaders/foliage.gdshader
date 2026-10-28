shader_type spatial;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
uniform float wind_strength = 0.15;

varying vec3 v_world;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - 3.0, 0.0);
	float s = sin(TIME * 1.2 + origin.x * 0.1 + VERTEX.y * 0.3) * wind_strength * h * 0.06;
	VERTEX.x += s;
	VERTEX.z += s * 0.6;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(detail, v_world.xz * 0.25 + v_world.y * 0.13).r;
	float m = texture(detail, v_world.zy * 0.7).r;
	ALBEDO = COLOR.rgb * (0.65 + 0.55 * n) * (0.85 + 0.3 * m);
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
