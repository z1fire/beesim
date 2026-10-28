shader_type spatial;
render_mode cull_disabled;

uniform float wind_strength = 0.05;
uniform float night_glow = 0.0;

varying float v_fresh;
varying float v_highlight;
varying float v_pollinated;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float sway = sin(TIME * 1.4 + origin.x * 0.35 + origin.z * 0.21) + 0.5 * sin(TIME * 2.3 + origin.z * 0.5);
	VERTEX.x += sway * wind_strength * h * h * 0.35;
	VERTEX.z += sway * wind_strength * h * h * 0.2;
	v_fresh = INSTANCE_CUSTOM.r;
	v_highlight = INSTANCE_CUSTOM.g;
	v_pollinated = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	float fresh = clamp(v_fresh, 0.0, 1.0);
	// Drained flowers fade toward a dull grey until they refill.
	c = mix(mix(vec3(grey), c, 0.35) * 0.75, c, fresh);
	ALBEDO = c;
	ROUGHNESS = 0.65;
	SPECULAR = 0.3;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float pulse = 0.5 + 0.5 * sin(TIME * 4.0);
	EMISSION = c * (0.06 + v_highlight * (0.2 + 0.25 * pulse) + v_pollinated * 0.08 + night_glow * 0.25 * fresh);
}
