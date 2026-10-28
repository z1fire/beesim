shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_schlick_ggx;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float f = 1.0 - abs(dot(NORMAL, VIEW));
	vec3 irid = 0.5 + 0.5 * cos(6.28318 * (f * 1.2 + v_local.x * 4.0 + vec3(0.0, 0.33, 0.67)));
	float vein = smoothstep(0.85, 1.0, abs(sin(v_local.x * 70.0 + v_local.z * 25.0)));
	ALBEDO = mix(vec3(0.9, 0.95, 1.0), irid, 0.3) * (1.0 - vein * 0.6);
	ALPHA = clamp(0.16 + 0.3 * f + vein * 0.25, 0.0, 0.85);
	ROUGHNESS = 0.1;
	SPECULAR = 0.9;
}
