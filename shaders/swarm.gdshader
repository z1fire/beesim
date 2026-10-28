shader_type spatial;
render_mode cull_disabled;

// Swarm bees are one MultiMesh. Wing vertices are marked by vertex alpha < 0.9
// and flap up and down, each bee at its own phase.

void vertex() {
	if (COLOR.a < 0.9) {
		float flap = sin(TIME * 55.0 + float(INSTANCE_ID) * 1.7);
		VERTEX.y += flap * abs(VERTEX.x) * 0.9;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.7;
	if (COLOR.a < 0.9) {
		EMISSION = vec3(0.12, 0.14, 0.16);
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
