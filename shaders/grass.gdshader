shader_type spatial;
render_mode cull_disabled;

uniform float wind_strength = 0.14;
uniform vec3 bee_position = vec3(0.0, -100.0, 0.0);

varying float v_dry;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = UV.y;
	float gust = sin(world.x * 0.07 + TIME * 0.9) * 0.5 + 0.5;
	float w = sin(world.x * 0.6 + TIME * 2.1) * 0.6 + sin(world.z * 0.5 + TIME * 1.7) * 0.4;
	vec3 offset = vec3(w * (0.4 + gust), 0.0, w * 0.4 * gust) * wind_strength * h * h;
	// Blades bend away from the bee as it brushes past.
	vec3 away = world - bee_position;
	float push = (1.0 - smoothstep(0.0, 1.3, length(away.xz))) * (1.0 - smoothstep(0.0, 1.6, abs(away.y)));
	offset.xz += normalize(away.xz + vec2(0.001)) * push * 0.55 * h;
	offset.y -= push * 0.3 * h;
	// The instance basis is a rotation with (nearly) uniform scale, so its transpose
	// divided by scale squared takes the world-space offset back to local space.
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * offset / dot(m[0], m[0]);
	v_dry = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c, c * vec3(1.35, 1.12, 0.55), v_dry);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
