shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.04, 0.17, 0.2);
uniform vec3 shallow_color : source_color = vec3(0.18, 0.42, 0.36);
uniform vec3 sky_color : source_color = vec3(0.6, 0.75, 0.9);
uniform vec2 pond_center = vec2(0.0);
uniform float pond_radius = 17.0;
uniform sampler2D wave_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wave_b : hint_normal, repeat_enable, filter_linear_mipmap;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world.xz;
	vec3 n1 = texture(wave_a, uv * 0.05 + TIME * vec2(0.012, 0.008)).rgb;
	vec3 n2 = texture(wave_b, uv * 0.09 - TIME * vec2(0.01, 0.017)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	float edge = smoothstep(pond_radius * 0.35, pond_radius * 0.8, length(uv - pond_center));
	vec3 water = mix(deep_color, shallow_color, edge);
	ALBEDO = mix(water, sky_color, fres * 0.6);
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
	ALPHA = mix(0.8, 0.97, fres);
}
