shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.72, 0.25);
uniform float intensity = 0.7;

varying float v_dist;
varying float v_height;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_height = VERTEX.y / 32.0 + 0.5;
}

void fragment() {
	float rim = pow(abs(dot(NORMAL, VIEW)), 2.0);
	float fade = pow(1.0 - clamp(v_height, 0.0, 1.0), 2.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);
	ALBEDO = color * intensity * pulse;
	ALPHA = rim * fade * smoothstep(5.0, 22.0, v_dist);
}
